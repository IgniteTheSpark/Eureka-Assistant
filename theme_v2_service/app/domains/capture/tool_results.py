from __future__ import annotations

import json
from typing import Any, Iterable

from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.execution import FlashExecutionItem
from app.domains.capture.json_output import extract_json_object


_ASSET_MUTATIONS = frozenset(
    {
        "tool_create_asset",
        "tool_create_todo",
        "tool_create_note",
        "tool_update_asset",
        "tool_delete_asset",
    }
)
_EVENT_MUTATIONS = frozenset(
    {"tool_create_event", "tool_update_event", "tool_delete_event"}
)
_CONTACT_MUTATIONS = frozenset(
    {"tool_create_contact", "tool_update_contact", "tool_delete_contact"}
)
_QUERY_TOOLS = frozenset(
    {"tool_query_asset", "tool_query_event", "tool_query_contact", "tool_query_digest"}
)


def _json_dict(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        return dict(value)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return None
        return dict(parsed) if isinstance(parsed, dict) else None
    return None


def unwrap_mcp_response(response: Any) -> dict[str, Any] | None:
    """Return the domain payload from normalized or FastMCP-wrapped output."""
    if not isinstance(response, dict):
        return None

    structured = response.get("structuredContent")
    if structured is None:
        structured = response.get("structured_content")
    if isinstance(structured, dict) and "result" in structured:
        parsed = _json_dict(structured.get("result"))
        if parsed is not None:
            return parsed

    content = response.get("content")
    if isinstance(content, list):
        for item in content:
            if not isinstance(item, dict):
                continue
            parsed = _json_dict(item.get("text"))
            if parsed is not None:
                return parsed

    return dict(response)


def _events(
    tool_events: Iterable[dict[str, Any]],
) -> list[tuple[str, dict[str, Any], dict[str, Any]]]:
    normalized: list[tuple[str, dict[str, Any], dict[str, Any]]] = []
    for event in tool_events:
        if not isinstance(event, dict):
            continue
        name = str(event.get("name") or "")
        payload = unwrap_mcp_response(event.get("response"))
        if not name or payload is None:
            continue
        arguments = event.get("args")
        normalized.append(
            (name, dict(arguments) if isinstance(arguments, dict) else {}, payload)
        )
    return normalized


def _mutation_contract(intent_type: str) -> tuple[frozenset[str], str]:
    if intent_type == "event":
        return _EVENT_MUTATIONS, "event_id"
    if intent_type == "contact":
        return _CONTACT_MUTATIONS, "contact_id"
    return _ASSET_MUTATIONS, "asset_id"


def _successful_mutation(
    intent: FlashIntent,
    events: list[tuple[str, dict[str, Any], dict[str, Any]]],
) -> dict[str, Any] | None:
    allowed_names, entity_key = _mutation_contract(intent.type)
    for name, _arguments, payload in reversed(events):
        if name not in allowed_names or payload.get("ok") is not True:
            continue
        if not payload.get(entity_key):
            continue
        result = dict(payload)
        result.setdefault("operation_tool", name)
        return result
    return None


def _grounded_contact_candidates(
    events: list[tuple[str, dict[str, Any], dict[str, Any]]],
) -> list[dict[str, Any]]:
    for name, _arguments, payload in reversed(events):
        if name != "tool_query_contact" or payload.get("ok") is not True:
            continue
        raw = payload.get("exact_contacts")
        if not isinstance(raw, list) or len(raw) < 2:
            raw = payload.get("contacts")
        candidates = [dict(item) for item in raw or [] if isinstance(item, dict)]
        if len(candidates) >= 2:
            return candidates
    return []


def _successful_query(
    events: list[tuple[str, dict[str, Any], dict[str, Any]]],
) -> dict[str, Any] | None:
    for name, _arguments, payload in reversed(events):
        if name in _QUERY_TOOLS and payload.get("ok") is True:
            return dict(payload)
    return None


def _claims_mutation(payload: dict[str, Any]) -> bool:
    return any(
        payload.get(key)
        for key in ("asset_id", "event_id", "contact_id", "attendee_id")
    )


def resolve_agent_result(
    *,
    intent: FlashIntent,
    final_text: str,
    tool_events: Iterable[dict[str, Any]],
) -> FlashExecutionItem:
    captured_events = tuple(dict(item) for item in tool_events if isinstance(item, dict))
    events = _events(captured_events)
    parsed = extract_json_object(final_text)

    mutation = _successful_mutation(intent, events)
    if mutation is not None:
        return FlashExecutionItem(
            intent=intent,
            status="success",
            result=mutation,
            tool_events=captured_events,
        )

    if intent.type == "qa":
        answer = parsed.get("answer") if isinstance(parsed, dict) else None
        if not isinstance(answer, str) or not answer.strip():
            answer = final_text.strip() if final_text.strip() and parsed is None else ""
        if answer:
            return FlashExecutionItem(
                intent=intent,
                status="reply",
                result={"answer": answer.strip()},
                tool_events=captured_events,
            )

    if intent.type == "contact":
        candidates = _grounded_contact_candidates(events)
        wants_confirmation = (
            isinstance(parsed, dict)
            and parsed.get("status") == "pending_confirmation"
        )
        if candidates and wants_confirmation:
            return FlashExecutionItem(
                intent=intent,
                status="pending_confirmation",
                result={"candidates": candidates},
                tool_events=captured_events,
            )

    queried = _successful_query(events)
    if queried is not None and intent.type != "contact":
        return FlashExecutionItem(
            intent=intent,
            status="success",
            result=queried,
            tool_events=captured_events,
        )

    if isinstance(parsed, dict) and _claims_mutation(parsed):
        return FlashExecutionItem(
            intent=intent,
            status="error",
            tool_events=captured_events,
            error_code="intent_ungrounded_mutation",
        )

    if any(payload.get("ok") is False for _name, _args, payload in events):
        return FlashExecutionItem(
            intent=intent,
            status="error",
            tool_events=captured_events,
            error_code="intent_tool_rejected",
        )

    return FlashExecutionItem(
        intent=intent,
        status="error",
        tool_events=captured_events,
        error_code="intent_agent_output_invalid",
    )
