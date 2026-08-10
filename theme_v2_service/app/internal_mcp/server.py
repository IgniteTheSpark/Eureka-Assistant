"""Local stdio MCP server for owner-scoped Theme V2 CRUD tools."""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from fastmcp import FastMCP

from app.internal_mcp.tools import EurekaToolContext, execute_tool


mcp = FastMCP("eureka-theme-v2")

# These values are supplied by the Agent host callback. They remain function
# arguments so the stdio runtime can inject them, but are omitted from the
# model-visible MCP schemas.
_TRUSTED_MUTATION_ARGS = [
    "user_id",
    "session_id",
    "source_input_turn_id",
    "tool_call_id",
]
_TRUSTED_ROOT_MUTATION_ARGS = [
    *_TRUSTED_MUTATION_ARGS,
    "intent_id",
    "intent_operation",
]
_TRUSTED_TEMPORAL_MUTATION_ARGS = [
    *_TRUSTED_ROOT_MUTATION_ARGS,
    "reference_datetime",
    "timezone_name",
]
_TRUSTED_QUERY_ARGS = ["user_id"]
_TRUSTED_CONTEXT_QUERY_ARGS = [
    "user_id",
    "session_id",
    "source_input_turn_id",
]


def _context(
    *,
    user_id: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    reference_datetime: str = "",
    timezone_name: str = "Asia/Shanghai",
    intent_id: str = "",
    intent_operation: str = "",
) -> EurekaToolContext:
    turn_id = source_input_turn_id.strip() or None
    owner_session_id = session_id.strip() or None
    reference = (
        datetime.fromisoformat(reference_datetime.replace("Z", "+00:00"))
        if reference_datetime.strip()
        else None
    )
    return EurekaToolContext(
        user_id=user_id,
        session_id=owner_session_id,
        input_turn_id=turn_id,
        idempotency_prefix=f"mcp:{turn_id or owner_session_id or user_id}",
        reference_datetime=reference,
        timezone_name=timezone_name.strip() or "Asia/Shanghai",
        intent_id=intent_id.strip() or None,
        intent_operation=intent_operation.strip() or None,
    )


async def _run(
    name: str,
    arguments: dict[str, Any],
    *,
    user_id: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    reference_datetime: str = "",
    timezone_name: str = "Asia/Shanghai",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    result = await execute_tool(
        name,
        arguments,
        context=_context(
            user_id=user_id,
            session_id=session_id,
            source_input_turn_id=source_input_turn_id,
            reference_datetime=reference_datetime,
            timezone_name=timezone_name,
            intent_id=intent_id,
            intent_operation=intent_operation,
        ),
        tool_call_id=tool_call_id or None,
    )
    return json.dumps(result, ensure_ascii=False, default=str)


@mcp.tool(exclude_args=_TRUSTED_TEMPORAL_MUTATION_ARGS)
async def tool_create_asset(
    user_skill_name: str,
    payload: str,
    user_skill_id: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
    period: str = "",
    occurred_at: str = "",
    effective_at: str = "",
    source_text: str = "",
    tool_call_id: str = "",
    reference_datetime: str = "",
    timezone_name: str = "Asia/Shanghai",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Create an asset under a registered built-in or custom skill."""
    return await _run(
        "tool_create_asset",
        {
            "user_skill_name": user_skill_name,
            "user_skill_id": user_skill_id,
            "payload": payload,
            "domain": domain,
            "period": period,
            "occurred_at": occurred_at,
            "effective_at": effective_at,
            "source_text": source_text,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        reference_datetime=reference_datetime,
        timezone_name=timezone_name,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_TEMPORAL_MUTATION_ARGS)
async def tool_create_todo(
    content: str,
    title: str = "",
    due_date: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
    period: str = "",
    occurred_at: str = "",
    source_text: str = "",
    reference_datetime: str = "",
    timezone_name: str = "Asia/Shanghai",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Create a Todo with an optional deadline and fuzzy occurrence period."""
    return await _run(
        "tool_create_todo",
        {
            "content": content,
            "title": title,
            "due_date": due_date,
            "domain": domain,
            "period": period,
            "occurred_at": occurred_at,
            "source_text": source_text,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        reference_datetime=reference_datetime,
        timezone_name=timezone_name,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_TEMPORAL_MUTATION_ARGS)
async def tool_create_note(
    content: str,
    title: str = "",
    tags: str = "",
    source_text: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
    tool_call_id: str = "",
    reference_datetime: str = "",
    timezone_name: str = "Asia/Shanghai",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Create a free-form note without inventing absent source facts."""
    return await _run(
        "tool_create_note",
        {
            "content": content,
            "title": title,
            "tags": tags,
            "domain": domain,
            "source_text": source_text,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        reference_datetime=reference_datetime,
        timezone_name=timezone_name,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_query_asset(
    user_skill_name: str = "",
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    domain: str = "",
    limit: int = 100,
    user_id: str = "default",
) -> str:
    """Query current-user assets by skill, text, date, or domain."""
    return await _run(
        "tool_query_asset",
        {
            "user_skill_name": user_skill_name,
            "contains": contains,
            "from_date": from_date,
            "to_date": to_date,
            "domain": domain,
            "limit": limit,
        },
        user_id=user_id,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_query_digest(
    from_date: str = "",
    to_date: str = "",
    domain: str = "",
    user_id: str = "default",
) -> str:
    """Return a compact asset and event digest for a time window."""
    return await _run(
        "tool_query_digest",
        {"from_date": from_date, "to_date": to_date, "domain": domain},
        user_id=user_id,
    )


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_update_asset(
    asset_id: str,
    payload_patch: str,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Merge a JSON object patch into an owner-scoped asset."""
    return await _run(
        "tool_update_asset",
        {"asset_id": asset_id, "payload_patch": payload_patch},
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_delete_asset(
    asset_id: str,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Delete one owner-scoped asset by ID."""
    return await _run(
        "tool_delete_asset",
        {"asset_id": asset_id},
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_create_contact(
    name: str,
    phone: str = "",
    company: str = "",
    title: str = "",
    email: str = "",
    notes: str = "",
    socials: dict[str, str] | None = None,
    source_input_turn_id: str = "",
    session_id: str = "",
    user_id: str = "default",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Create a first-class Contact with supported social handles."""
    return await _run(
        "tool_create_contact",
        {
            "name": name,
            "phone": phone,
            "company": company,
            "title": title,
            "email": email,
            "notes": notes,
            "socials": socials or {},
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_query_contact(
    name_query: str = "",
    user_id: str = "default",
) -> str:
    """Query Contacts and include safe exact-name matches."""
    return await _run(
        "tool_query_contact",
        {"name_query": name_query},
        user_id=user_id,
    )


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_update_contact(
    contact_id: str,
    field: str = "",
    value: str = "",
    patch: str = "",
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Update one Contact atomically; notes append and socials merge."""
    return await _run(
        "tool_update_contact",
        {
            "contact_id": contact_id,
            "field": field,
            "value": value,
            "patch": patch,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_delete_contact(
    contact_id: str,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Delete one Contact while preserving attendee name snapshots."""
    return await _run(
        "tool_delete_contact",
        {"contact_id": contact_id},
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_query_input_turn(
    contains: str = "",
    source: str = "",
    limit: int = 50,
    user_id: str = "default",
) -> str:
    """Search current-user InputTurns and return source snippets."""
    return await _run(
        "tool_query_input_turn",
        {"contains": contains, "source": source, "limit": limit},
        user_id=user_id,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_get_input_turn(
    input_turn_id: str,
    user_id: str = "default",
) -> str:
    """Fetch one owned InputTurn with complete text and ASR metadata."""
    return await _run(
        "tool_get_input_turn",
        {"input_turn_id": input_turn_id},
        user_id=user_id,
    )


@mcp.tool(exclude_args=_TRUSTED_CONTEXT_QUERY_ARGS)
async def tool_resolve_capture_target(
    entity_type: str,
    source_text: str,
    explicit_id: str = "",
    target_query: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    user_id: str = "default",
) -> str:
    """Resolve one owner-scoped mutation target without changing data."""
    return await _run(
        "tool_resolve_capture_target",
        {
            "entity_type": entity_type,
            "source_text": source_text,
            "explicit_id": explicit_id,
            "target_query": target_query,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
    )


@mcp.tool(exclude_args=_TRUSTED_TEMPORAL_MUTATION_ARGS)
async def tool_create_event(
    title: str,
    start_at: str,
    end_at: str = "",
    location: str = "",
    description: str = "",
    all_day: int = 0,
    recurrence_rule: str = "",
    source_text: str = "",
    source_input_turn_id: str = "",
    session_id: str = "",
    user_id: str = "default",
    tool_call_id: str = "",
    reference_datetime: str = "",
    timezone_name: str = "Asia/Shanghai",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Create an Event with a valid range or all-day interval."""
    return await _run(
        "tool_create_event",
        {
            "title": title,
            "start_at": start_at,
            "end_at": end_at,
            "location": location,
            "description": description,
            "all_day": bool(all_day),
            "recurrence_rule": recurrence_rule,
            "source_text": source_text,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        reference_datetime=reference_datetime,
        timezone_name=timezone_name,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_query_event(
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    status: str = "",
    limit: int = 50,
    user_id: str = "default",
) -> str:
    """Query owner-scoped Events by text, date range, or status."""
    return await _run(
        "tool_query_event",
        {
            "contains": contains,
            "from_date": from_date,
            "to_date": to_date,
            "status": status,
            "limit": limit,
        },
        user_id=user_id,
    )


@mcp.tool(exclude_args=_TRUSTED_QUERY_ARGS)
async def tool_get_event(event_id: str, user_id: str = "default") -> str:
    """Fetch one owned Event with attendee snapshots."""
    return await _run("tool_get_event", {"event_id": event_id}, user_id=user_id)


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_update_event(
    event_id: str,
    patch: str,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Update an owned Event from a JSON object patch."""
    return await _run(
        "tool_update_event",
        {"event_id": event_id, "patch": patch},
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_ROOT_MUTATION_ARGS)
async def tool_delete_event(
    event_id: str,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
    intent_id: str = "",
    intent_operation: str = "",
) -> str:
    """Delete one owner-scoped Event by ID."""
    return await _run(
        "tool_delete_event",
        {"event_id": event_id},
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
        intent_id=intent_id,
        intent_operation=intent_operation,
    )


@mcp.tool(exclude_args=_TRUSTED_MUTATION_ARGS)
async def tool_add_event_attendee(
    event_id: str,
    name: str = "",
    contact_id: str = "",
    role: str = "attendee",
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
) -> str:
    """Add a resolved Contact or unresolved name snapshot to an Event."""
    return await _run(
        "tool_add_event_attendee",
        {
            "event_id": event_id,
            "name": name,
            "contact_id": contact_id,
            "role": role,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
    )


@mcp.tool(exclude_args=_TRUSTED_MUTATION_ARGS)
async def tool_update_event_attendee(
    event_id: str,
    attendee_id: str,
    name: str | None = None,
    contact_id: str | None = None,
    role: str | None = None,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
) -> str:
    """Update, bind, or unbind an attendee on an owned Event."""
    return await _run(
        "tool_update_event_attendee",
        {
            "event_id": event_id,
            "attendee_id": attendee_id,
            "name": name,
            "contact_id": contact_id,
            "role": role,
        },
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
    )


@mcp.tool(exclude_args=_TRUSTED_MUTATION_ARGS)
async def tool_delete_event_attendee(
    event_id: str,
    attendee_id: str,
    user_id: str = "default",
    session_id: str = "",
    source_input_turn_id: str = "",
    tool_call_id: str = "",
) -> str:
    """Remove one attendee without deleting its linked Contact."""
    return await _run(
        "tool_delete_event_attendee",
        {"event_id": event_id, "attendee_id": attendee_id},
        user_id=user_id,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        tool_call_id=tool_call_id,
    )


if __name__ == "__main__":
    mcp.run(transport="stdio")
