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
        )
        if not intents:
            raise PermanentFlashExecutionError("flash dispatcher produced no intent")

        executor = SessionToolExecutor(
            user_id=context.user_id,
            session_id=context.session_id,
            input_turn_id=context.input_turn_id,
            runtime=tool_runtime,
        )
        outcomes = await asyncio.gather(
            *(
                self._run_intent(
                    context=context,
                    intent=intent,
                    intent_ordinal=ordinal,
                    custom_skill=custom_by_name.get(intent.type),
                    executor=executor,
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
        try:
            agent = (
                make_custom_skill_agent(custom_skill)
                if custom_skill is not None
                else make_builtin_skill_agent(intent.type)
            )
        except ValueError:
            agent = make_builtin_skill_agent("notes")
            intent = intent.model_copy(update={"type": "notes"})

        message = json.dumps(
            {
                "source_text": intent.source_text,
                "user_text": context.transcript,
                "reference_datetime": context.reference_datetime.isoformat(),
                "domain": intent.domain,
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
            elif intent.type == "event" and resolved.status == "error":
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
