from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable
from typing import Any

import litellm

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.agent_runner import (
    PermanentAgentRunError,
    RetryableAgentRunError,
    run_agent_once,
    stable_capture_tool_call_id,
)
from app.domains.capture.dispatcher import decode_dispatcher_output
from app.domains.capture.execution import (
    FlashExecutionContext,
    FlashExecutionItem,
    FlashExecutionResult,
    PermanentFlashExecutionError,
    RetryableFlashExecutionError,
)
from app.domains.capture.intent_normalizer import normalize_intents
from app.domains.capture.json_output import extract_json_object
from app.domains.capture.pipeline import (
    aggregate_execution,
    run_custom_skill_fallback,
    run_event_to_todo_fallback,
)
from app.domains.capture.skill_factory import (
    make_builtin_skill_agent,
    make_custom_skill_agent,
    make_dispatcher_agent,
)
from app.domains.capture.tool_results import resolve_agent_result
from app.domains.sessions.tools import SessionToolExecutor
from app.observability import metrics


Completion = Callable[..., Awaitable[Any]]
_BUILTIN_SKILLS = frozenset(
    {"todo", "event", "expense", "contact", "notes", "qa"}
)
_CONTACT_SCALAR_PATCH_FIELDS = frozenset(
    {"name", "phone", "company", "title", "email"}
)


def _contact_pending_candidates(raw_candidates: Any) -> list[dict[str, Any]]:
    if not isinstance(raw_candidates, list):
        return []
    candidates: list[dict[str, Any]] = []
    for raw in raw_candidates:
        if not isinstance(raw, dict):
            continue
        snapshot = raw.get("snapshot")
        source = dict(snapshot) if isinstance(snapshot, dict) else dict(raw)
        contact_id = str(
            source.get("contact_id") or raw.get("entity_id") or ""
        ).strip()
        if not contact_id:
            continue
        candidates.append(
            {
                "contact_id": contact_id,
                "name": source.get("name"),
                "company": source.get("company"),
                "title": source.get("title"),
            }
        )
    return candidates


def _contact_pending_patch(raw_patch: Any) -> dict[str, Any]:
    if not isinstance(raw_patch, dict):
        return {}
    patch: dict[str, Any] = {}
    for field in _CONTACT_SCALAR_PATCH_FIELDS:
        value = raw_patch.get(field)
        if isinstance(value, (str, int, float)):
            patch[field] = str(value)
    notes = raw_patch.get("notes")
    if isinstance(notes, str) and notes.strip():
        patch["notes"] = [notes.strip()]
    elif isinstance(notes, list):
        normalized_notes = [
            str(item).strip() for item in notes if str(item).strip()
        ]
        if normalized_notes:
            patch["notes"] = normalized_notes
    socials = raw_patch.get("socials")
    if isinstance(socials, dict):
        normalized_socials = {
            str(key).strip(): str(value).strip()
            for key, value in socials.items()
            if str(key).strip() and str(value).strip()
        }
        if normalized_socials:
            patch["socials"] = normalized_socials
    return patch


class LiteLLMLegacyFlashProvider:
    """Theme V2 execution kernel with legacy Flash behavior and trusted MCP writes."""

    def __init__(
        self,
        *,
        model: str,
        api_key: str | None,
        timeout_seconds: float,
        completion: Completion = litellm.acompletion,
    ) -> None:
        self.model = model
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds
        self._completion = completion

    async def execute(
        self,
        *,
        context: FlashExecutionContext,
        tool_runtime: Any | None = None,
    ) -> FlashExecutionResult:
        transcript = context.transcript.strip()
        if not transcript:
            raise PermanentFlashExecutionError("capture transcript is empty")

        enabled = tuple(skill for skill in context.skills if skill.enabled)
        custom_skills = tuple(
            skill for skill in enabled if skill.machine_name not in _BUILTIN_SKILLS
        )
        custom_by_name = {skill.machine_name: skill for skill in custom_skills}
        custom_by_id = {
            skill.user_skill_id: skill
            for skill in custom_skills
            if skill.user_skill_id
        }
        dispatcher = make_dispatcher_agent(custom_skills)
        dispatcher_message = (
            f"reference_datetime={context.reference_datetime.isoformat()}\n"
            "BEGIN_UNTRUSTED_TRANSCRIPT\n"
            f"{transcript}\n"
            "END_UNTRUSTED_TRANSCRIPT"
        )
        try:
            dispatch_run = await run_agent_once(
                dispatcher,
                dispatcher_message,
                None,
                model=self.model,
                api_key=self.api_key,
                timeout_seconds=self.timeout_seconds,
                recording_id=context.recording_id,
                intent_ordinal=-1,
                completion=self._completion,
            )
        except RetryableAgentRunError as exc:
            raise RetryableFlashExecutionError(
                "flash dispatcher provider unavailable"
            ) from exc
        except PermanentAgentRunError as exc:
            raise PermanentFlashExecutionError(
                "flash dispatcher response invalid"
            ) from exc

        if extract_json_object(dispatch_run.text) is None:
            metrics.increment(
                "flash_dispatch_fallback_total",
                labels={"reason_code": "dispatcher_output_invalid"},
            )
        intents = normalize_intents(
            decode_dispatcher_output(dispatch_run.text, fallback_text=transcript),
            custom_skill_names=set(custom_by_name),
            custom_skills=custom_skills,
        )
        if not intents:
            raise PermanentFlashExecutionError("flash dispatcher produced no intent")

        outcomes = await asyncio.gather(
            *(
                self._run_intent(
                    context=context,
                    intent=intent,
                    intent_ordinal=ordinal,
                    custom_skill=(
                        custom_by_id.get(intent.custom_skill_id)
                        if intent.custom_skill_id
                        else custom_by_name.get(intent.type)
                    ),
                    executor=SessionToolExecutor(
                        user_id=context.user_id,
                        session_id=context.session_id,
                        input_turn_id=context.input_turn_id,
                        reference_datetime=context.reference_datetime,
                        timezone_name=context.timezone_name,
                        capture_source_text=intent.source_text,
                        capture_domain=intent.domain,
                        capture_intent_id=intent.intent_id,
                        capture_operation=intent.operation,
                        source_kind="capture",
                        runtime=tool_runtime,
                    ),
                )
                for ordinal, intent in enumerate(intents)
            ),
            return_exceptions=True,
        )

        items: list[FlashExecutionItem] = []
        usage_tokens = dispatch_run.usage_tokens
        retryable_errors: list[BaseException] = []
        for intent, outcome in zip(intents, outcomes, strict=True):
            metrics.increment(
                "flash_intent_total",
                labels={"intent_type": intent.type},
            )
            if isinstance(outcome, BaseException):
                metrics.increment(
                    "flash_intent_failed_total",
                    labels={
                        "intent_type": intent.type,
                        "reason_code": (
                            "infrastructure_unavailable"
                            if isinstance(outcome, RetryableFlashExecutionError)
                            else "execution_invalid"
                        ),
                    },
                )
                if isinstance(outcome, RetryableFlashExecutionError):
                    retryable_errors.append(outcome)
                    code = "intent_infrastructure_unavailable"
                else:
                    code = "intent_execution_failed"
                items.append(
                    FlashExecutionItem(
                        intent=intent,
                        status="error",
                        error_code=code,
                    )
                )
                continue
            item, tokens = outcome
            items.append(item)
            usage_tokens += tokens
            if item.status == "error":
                metrics.increment(
                    "flash_intent_failed_total",
                    labels={
                        "intent_type": intent.type,
                        "reason_code": item.error_code or "unknown",
                    },
                )

        if retryable_errors and not any(item.status != "error" for item in items):
            raise RetryableFlashExecutionError(
                "flash intent infrastructure unavailable"
            ) from retryable_errors[0]

        result = aggregate_execution(items, usage_tokens=usage_tokens)
        if result.warnings and any(item.status != "error" for item in result.items):
            metrics.increment("flash_capture_partial_total")
        if result.items and all(item.status == "error" for item in result.items):
            metrics.increment("flash_capture_failed_total")
        return result

    async def _run_intent(
        self,
        *,
        context: FlashExecutionContext,
        intent,
        intent_ordinal: int,
        custom_skill: CaptureSkill | None,
        executor: SessionToolExecutor,
    ) -> tuple[FlashExecutionItem, int]:
        if intent.routing_error:
            return (
                FlashExecutionItem(
                    intent=intent,
                    status="error",
                    error_code=f"intent_{intent.routing_error}",
                ),
                0,
            )
        resolved_target: dict[str, Any] | None = None
        if intent.operation in {"update", "delete"}:
            try:
                target_outcome = await executor.execute(
                    "tool_resolve_capture_target",
                    {
                        "entity_type": intent.type,
                        "source_text": intent.source_text,
                        "explicit_id": intent.target_id or "",
                        "target_query": intent.target_query or "",
                    },
                )
            except Exception as exc:
                raise RetryableFlashExecutionError(
                    "capture target resolver unavailable"
                ) from exc
            target_response = target_outcome.response
            if target_response.get("ok") is not True:
                return (
                    FlashExecutionItem(
                        intent=intent,
                        status="error",
                        error_code="intent_target_resolution_failed",
                    ),
                    0,
                )
            target_status = str(target_response.get("status") or "")
            target_id = str(target_response.get("entity_id") or "").strip()
            if target_status != "resolved" or not target_id:
                stable_candidates = (
                    _contact_pending_candidates(
                        target_response.get("candidates")
                    )
                    if intent.type == "contact"
                    else [
                        dict(item)
                        for item in target_response.get("candidates") or []
                        if isinstance(item, dict)
                    ]
                )
                pending_result: dict[str, Any] = {
                    "operation": intent.operation,
                    "candidates": stable_candidates,
                }
                if intent.type == "contact":
                    contact_patch = _contact_pending_patch(
                        intent.contact_patch
                    )
                    contact_names = {
                        str(candidate.get("name") or "").strip()
                        for candidate in stable_candidates
                        if str(candidate.get("name") or "").strip()
                    }
                    pending_result.update(
                        {
                            "name": (
                                (intent.target_query or "").strip()
                                or (
                                    next(iter(contact_names))
                                    if len(contact_names) == 1
                                    else "联系人"
                                )
                            ),
                            "extracted_update": contact_patch,
                        }
                    )
                    if intent.operation == "update" and not contact_patch:
                        return (
                            FlashExecutionItem(
                                intent=intent,
                                status="error",
                                error_code="intent_pending_patch_missing",
                            ),
                            0,
                        )
                actionable_contact_ambiguity = (
                    intent.type == "contact"
                    and target_status == "ambiguous"
                    and bool(stable_candidates)
                )
                return (
                    FlashExecutionItem(
                        intent=intent,
                        status=(
                            "pending_confirmation"
                            if actionable_contact_ambiguity
                            else "error"
                        ),
                        result=(
                            pending_result
                            if actionable_contact_ambiguity
                            else {}
                        ),
                        error_code=(
                            None
                            if actionable_contact_ambiguity
                            else (
                                "intent_target_ambiguous"
                                if target_status == "ambiguous"
                                else "intent_target_not_found"
                            )
                        ),
                    ),
                    0,
                )
            resolved_target = {
                "entity_id": target_id,
                "entity_type": str(
                    target_response.get("entity_type") or intent.type
                ),
                "resolution_source": str(
                    target_response.get("resolution_source") or ""
                ),
            }
            intent = intent.model_copy(update={"target_id": target_id})
            executor = executor.with_capture_target(target_id)

            if intent.operation == "delete":
                delete_tool, target_argument = {
                    "contact": ("tool_delete_contact", "contact_id"),
                    "event": ("tool_delete_event", "event_id"),
                }.get(intent.type, ("tool_delete_asset", "asset_id"))
                arguments = {target_argument: target_id}
                trusted_call_id = stable_capture_tool_call_id(
                    recording_id=context.recording_id,
                    intent_ordinal=intent_ordinal,
                    tool_name=delete_tool,
                    arguments=arguments,
                )
                try:
                    outcome = await executor.execute(
                        delete_tool,
                        arguments,
                        tool_call_id=trusted_call_id,
                    )
                except Exception as exc:
                    raise RetryableFlashExecutionError(
                        "capture delete tool unavailable"
                    ) from exc
                return (
                    resolve_agent_result(
                        intent=intent,
                        final_text="",
                        tool_events=(
                            {
                                "name": delete_tool,
                                "effect": "delete",
                                "args": arguments,
                                "response": dict(outcome.response),
                                "tool_call_id": trusted_call_id,
                            },
                        ),
                    ),
                    0,
                )

        try:
            agent = (
                make_custom_skill_agent(
                    custom_skill,
                    operation=intent.operation,
                )
                if custom_skill is not None
                else make_builtin_skill_agent(
                    intent.type,
                    operation=intent.operation,
                )
            )
        except ValueError:
            agent = make_builtin_skill_agent(
                "notes",
                operation=(
                    intent.operation
                    if intent.operation in {"create", "query", "update", "delete"}
                    else "create"
                ),
            )
            intent = intent.model_copy(
                update={
                    "type": "notes",
                    "operation": (
                        intent.operation
                        if intent.operation in {"create", "query", "update", "delete"}
                        else "create"
                    ),
                }
            )

        message = json.dumps(
            {
                "intent_id": intent.intent_id,
                "intent_ordinal": intent.ordinal,
                "operation": intent.operation,
                "source_text": intent.source_text,
                "user_text": context.transcript,
                "reference_datetime": context.reference_datetime.isoformat(),
                "domain": intent.domain,
                "resolved_target": resolved_target,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
        try:
            run = await run_agent_once(
                agent,
                message,
                executor,
                model=self.model,
                api_key=self.api_key,
                timeout_seconds=self.timeout_seconds,
                recording_id=context.recording_id,
                intent_ordinal=intent_ordinal,
                completion=self._completion,
            )
        except RetryableAgentRunError as exc:
            raise RetryableFlashExecutionError(
                "flash skill infrastructure unavailable"
            ) from exc
        except PermanentAgentRunError:
            return (
                FlashExecutionItem(
                    intent=intent,
                    status="error",
                    error_code="intent_agent_output_invalid",
                ),
                0,
            )

        resolved = resolve_agent_result(
            intent=intent,
            final_text=run.text,
            tool_events=run.tool_events,
        )
        if resolved.status == "success" and extract_json_object(run.text) is None:
            metrics.increment(
                "flash_tool_recovered_total",
                labels={"intent_type": intent.type},
            )

        try:
            if (
                custom_skill is not None
                and intent.operation == "create"
                and resolved.status == "error"
                and resolved.error_code
                in {"intent_agent_output_invalid", "intent_ungrounded_mutation"}
            ):
                metrics.increment(
                    "flash_custom_fallback_total",
                    labels={"intent_type": intent.type},
                )
                resolved = await run_custom_skill_fallback(
                    intent=intent,
                    skill=custom_skill,
                    executor=executor,
                    tool_call_prefix=(
                        f"capture:{context.recording_id}:{intent_ordinal}:fallback"
                    ),
                    reference_datetime=context.reference_datetime,
                )
            elif (
                intent.type == "event"
                and intent.operation == "create"
                and resolved.status == "error"
            ):
                resolved = await run_event_to_todo_fallback(
                    intent=intent,
                    executor=executor,
                    tool_call_prefix=(
                        f"capture:{context.recording_id}:{intent_ordinal}:event-fallback"
                    ),
                    reference_datetime=context.reference_datetime,
                )
        except Exception as exc:
            raise RetryableFlashExecutionError(
                "flash fallback infrastructure unavailable"
            ) from exc
        return resolved, run.usage_tokens
