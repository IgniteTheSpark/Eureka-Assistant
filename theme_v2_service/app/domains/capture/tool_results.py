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
_QUERY_TOOLS_BY_TYPE: dict[str, frozenset[str]] = {
    "event": frozenset({"tool_query_event"}),
    "contact": frozenset({"tool_query_contact"}),
}
_DEFAULT_QUERY_TOOLS = frozenset({"tool_query_asset"})
_MUTATION_TOOLS_BY_OPERATION: dict[str, dict[str, str]] = {
    "create": {
        "event": "tool_create_event",
        "contact": "tool_create_contact",
        "todo": "tool_create_todo",
        "notes": "tool_create_note",
        "default": "tool_create_asset",
    },
    "update": {
        "event": "tool_update_event",
        "contact": "tool_update_contact",
        "default": "tool_update_asset",
    },
    "delete": {
        "event": "tool_delete_event",
        "contact": "tool_delete_contact",
        "default": "tool_delete_asset",
    },
}
_ALL_MUTATION_TOOLS = _ASSET_MUTATIONS | _EVENT_MUTATIONS | _CONTACT_MUTATIONS


def tool_effect_for_name(tool_name: str) -> str:
    if tool_name.startswith("tool_query_"):
        return "query"
    if tool_name.startswith("tool_create_") or tool_name.startswith("tool_add_"):
        return "create"
    if tool_name.startswith("tool_update_"):
        return "update"
    if tool_name.startswith("tool_delete_"):
        return "delete"
    return "other"


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


def _entity_key(intent_type: str) -> str:
    return {
        "event": "event_id",
        "contact": "contact_id",
    }.get(intent_type, "asset_id")


def _expected_mutation_tool(intent: FlashIntent) -> str | None:
    by_type = _MUTATION_TOOLS_BY_OPERATION.get(intent.operation)
    if by_type is None:
        return None
    return by_type.get(intent.type, by_type["default"])


def _successful_mutation(
    intent: FlashIntent,
    events: list[tuple[str, dict[str, Any], dict[str, Any]]],
) -> dict[str, Any] | None:
    expected_name = _expected_mutation_tool(intent)
    if expected_name is None:
        return None
    entity_key = _entity_key(intent.type)
    for name, _arguments, payload in reversed(events):
        if name != expected_name or payload.get("ok") is not True:
            continue
        if not payload.get(entity_key):
            continue
        result = dict(payload)
        result.setdefault("operation_tool", name)
        return result
    return None


def _successful_query(
    intent: FlashIntent,
    events: list[tuple[str, dict[str, Any], dict[str, Any]]],
) -> dict[str, Any] | None:
    allowed_names = _QUERY_TOOLS_BY_TYPE.get(intent.type, _DEFAULT_QUERY_TOOLS)
    for name, _arguments, payload in reversed(events):
        if name in allowed_names and payload.get("ok") is True:
            return dict(payload)
    return None


def _has_successful_mutation(
    events: list[tuple[str, dict[str, Any], dict[str, Any]]],
) -> bool:
    return any(
        name in _ALL_MUTATION_TOOLS and payload.get("ok") is True
        for name, _arguments, payload in events
    )


def _query_answer(
    intent: FlashIntent,
    parsed: dict[str, Any] | None,
    final_text: str,
    query_result: dict[str, Any],
) -> str:
    answer = parsed.get("answer") if isinstance(parsed, dict) else None
    if isinstance(answer, str) and answer.strip():
        return answer.strip()
    if parsed is None and final_text.strip():
        return final_text.strip()

    records = query_result.get("assets")
    if intent.type == "expense" and isinstance(records, list):
        amounts = []
        for record in records:
            payload = record.get("payload") if isinstance(record, dict) else None
            amount = payload.get("amount") if isinstance(payload, dict) else None
            if isinstance(amount, (int, float)) and not isinstance(amount, bool):
                amounts.append(float(amount))
        if amounts:
            total = sum(amounts)
            rendered = str(int(total)) if total.is_integer() else f"{total:g}"
            return f"最近共消费 {rendered} 元。"
    if isinstance(records, list):
        return f"共查到 {len(records)} 条记录。"
    return "已完成查询。"


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

    if intent.operation == "query":
        queried = _successful_query(intent, events)
        if queried is not None:
            return FlashExecutionItem(
                intent=intent,
                status="reply",
                result={
                    "answer": _query_answer(intent, parsed, final_text, queried),
                    "sources": queried,
                },
                tool_events=captured_events,
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
            error_code="intent_query_ungrounded",
        )

    if intent.operation == "answer":
        if _has_successful_mutation(events):
            return FlashExecutionItem(
                intent=intent,
                status="error",
                tool_events=captured_events,
                error_code="intent_unexpected_mutation",
            )
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

    mutation = _successful_mutation(intent, events)
    if mutation is not None:
        return FlashExecutionItem(
            intent=intent,
            status="success",
            result=mutation,
            tool_events=captured_events,
        )

    if _has_successful_mutation(events):
        return FlashExecutionItem(
            intent=intent,
            status="error",
            tool_events=captured_events,
            error_code="intent_effect_mismatch",
        )

    if intent.type == "contact":
        candidates = _grounded_contact_candidates(events)
        wants_confirmation = (
            isinstance(parsed, dict)
            and parsed.get("status") == "pending_confirmation"
        )
        if candidates and wants_confirmation:
            extracted_update = parsed.get("extracted_update")
            if not isinstance(extracted_update, dict):
                extracted_update = {}
            return FlashExecutionItem(
                intent=intent,
                status="pending_confirmation",
                result={
                    "candidates": candidates,
                    "extracted_update": extracted_update,
                    "operation": "create_or_update",
                },
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
