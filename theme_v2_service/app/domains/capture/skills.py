from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

from app.domains.capture.agent import CaptureRecordCommand
from app.domains.capture.contact_skill import execute_contact_command
from app.domains.sessions.tools import SessionToolExecutor


@dataclass(frozen=True)
class FlashSkillResult:
    status: Literal["success", "pending_confirmation", "error"]
    operation: str
    kind: str
    entity_id: str | None = None
    action: str | None = None
    snapshot: dict[str, Any] = field(default_factory=dict)
    snapshots: list[dict[str, Any]] = field(default_factory=list)
    candidates: list[dict[str, Any]] = field(default_factory=list)
    error: str | None = None


async def execute_capture_command(
    command: CaptureRecordCommand,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str = "flash",
) -> FlashSkillResult:
    if command.kind == "contact":
        contact = await execute_contact_command(
            command,
            executor,
            tool_call_prefix=tool_call_prefix,
        )
        return FlashSkillResult(
            status=contact.status,
            operation=command.operation or "create_or_update",
            kind="contact",
            entity_id=contact.contact_id,
            action=contact.contact_action,
            snapshot=contact.contact,
            candidates=contact.candidates,
            error=contact.error,
        )
    if command.kind == "event":
        return await _execute_event(
            command,
            executor,
            tool_call_prefix=tool_call_prefix,
        )
    return await _execute_asset(
        command,
        executor,
        tool_call_prefix=tool_call_prefix,
    )


async def _execute_asset(
    command: CaptureRecordCommand,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str,
) -> FlashSkillResult:
    operation = command.operation or "create"
    skill_name = command.skill_machine_name or ""
    if operation == "create":
        tool_name, arguments = _asset_create_call(command)
        outcome = await executor.execute(
            tool_name,
            arguments,
            tool_call_id=f"{tool_call_prefix}-create",
        )
        return _asset_outcome(operation, skill_name, outcome.response)

    if operation == "query":
        outcome = await executor.execute(
            "tool_query_asset",
            _asset_query_arguments(command),
            tool_call_id=f"{tool_call_prefix}-query",
        )
        if not outcome.response.get("ok"):
            return _error(operation, "asset", outcome.response)
        assets = [
            dict(item)
            for item in outcome.response.get("assets") or []
            if isinstance(item, dict)
        ]
        return FlashSkillResult(
            status="success",
            operation=operation,
            kind="asset",
            snapshots=assets,
            snapshot=assets[0] if len(assets) == 1 else {},
            entity_id=str(assets[0].get("asset_id") or "")
            if len(assets) == 1
            else None,
        )

    target = await _resolve_single_asset(
        command,
        executor,
        tool_call_prefix=tool_call_prefix,
    )
    if isinstance(target, FlashSkillResult):
        return target
    asset_id = str(target.get("asset_id") or "")
    if operation == "update":
        outcome = await executor.execute(
            "tool_update_asset",
            {"asset_id": asset_id, "payload_patch": command.payload},
            tool_call_id=f"{tool_call_prefix}-update",
        )
    else:
        outcome = await executor.execute(
            "tool_delete_asset",
            {"asset_id": asset_id},
            tool_call_id=f"{tool_call_prefix}-delete",
        )
    return _asset_outcome(operation, skill_name, outcome.response)


def _asset_create_call(command: CaptureRecordCommand) -> tuple[str, dict[str, Any]]:
    payload = command.payload
    temporal = {
        "source_text": command.source_text,
        "period": command.period or "",
        "occurred_at": command.occurred_at.isoformat()
        if command.occurred_at is not None
        else "",
        "domain": command.domain or "",
    }
    if command.skill_machine_name == "todo":
        title = str(payload.get("title") or payload.get("content") or "").strip()
        return "tool_create_todo", {
            "title": title,
            "content": str(payload.get("content") or title),
            "due_date": str(payload.get("due_date") or ""),
            **temporal,
        }
    if command.skill_machine_name == "notes":
        return "tool_create_note", {
            "title": str(payload.get("title") or ""),
            "content": str(payload.get("content") or command.source_text),
            "domain": command.domain or "",
        }
    return "tool_create_asset", {
        "user_skill_name": command.skill_machine_name or "",
        "payload": payload,
        "effective_at": command.effective_at.isoformat()
        if command.effective_at is not None
        else "",
        **temporal,
    }


def _asset_query_arguments(command: CaptureRecordCommand) -> dict[str, Any]:
    return {
        "user_skill_name": command.skill_machine_name or "",
        "contains": (command.match_text or "").strip(),
        "limit": 20,
    }


async def _resolve_single_asset(
    command: CaptureRecordCommand,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str,
) -> dict[str, Any] | FlashSkillResult:
    if (command.target_id or "").strip():
        return {"asset_id": command.target_id}
    outcome = await executor.execute(
        "tool_query_asset",
        _asset_query_arguments(command),
        tool_call_id=f"{tool_call_prefix}-query",
    )
    if not outcome.response.get("ok"):
        return _error(command.operation or "query", "asset", outcome.response)
    assets = [
        dict(item)
        for item in outcome.response.get("assets") or []
        if isinstance(item, dict)
    ]
    if not assets:
        return FlashSkillResult(
            status="error",
            operation=command.operation or "query",
            kind="asset",
            error="未找到要处理的记录",
        )
    if len(assets) > 1:
        return FlashSkillResult(
            status="error",
            operation=command.operation or "query",
            kind="asset",
            snapshots=assets,
            error="找到多个可能的记录，未执行变更",
        )
    return assets[0]


def _asset_outcome(
    operation: str,
    skill_name: str,
    response: dict[str, Any],
) -> FlashSkillResult:
    if not response.get("ok"):
        return _error(operation, "asset", response)
    snapshot = dict(response)
    snapshot.setdefault("user_skill_name", skill_name)
    return FlashSkillResult(
        status="success",
        operation=operation,
        kind="asset",
        entity_id=str(response.get("asset_id") or "") or None,
        snapshot=snapshot,
    )


async def _execute_event(
    command: CaptureRecordCommand,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str,
) -> FlashSkillResult:
    operation = command.operation or "create"
    if operation == "query":
        queried = await executor.execute(
            "tool_query_event",
            _event_query_arguments(command),
            tool_call_id=f"{tool_call_prefix}-query",
        )
        if not queried.response.get("ok"):
            return _error(operation, "event", queried.response)
        events = [
            dict(item)
            for item in queried.response.get("events") or []
            if isinstance(item, dict)
        ]
        return FlashSkillResult(
            status="success",
            operation=operation,
            kind="event",
            snapshots=events,
            snapshot=events[0] if len(events) == 1 else {},
            entity_id=str(events[0].get("event_id") or "")
            if len(events) == 1
            else None,
        )
    if operation == "create":
        created = await executor.execute(
            "tool_create_event",
            {
                "title": command.title or "",
                "source_text": command.source_text,
                "description": command.description or "",
                "location": command.location or "",
                "start_at": command.start_at.isoformat() if command.start_at else "",
                "end_at": command.end_at.isoformat() if command.end_at else "",
                "all_day": int(command.all_day),
            },
            tool_call_id=f"{tool_call_prefix}-create",
        )
        if not created.response.get("ok"):
            return _error(operation, "event", created.response)
        event_id = str(created.response.get("event_id") or "")
        for index, attendee in enumerate(command.attendees):
            contact_id = await _unique_contact_id(
                attendee,
                executor,
                tool_call_prefix=f"{tool_call_prefix}-attendee-{index}",
            )
            added = await executor.execute(
                "tool_add_event_attendee",
                {
                    "event_id": event_id,
                    "name": attendee,
                    "contact_id": contact_id or "",
                    "role": "attendee",
                },
                tool_call_id=f"{tool_call_prefix}-attendee-{index}-add",
            )
            if not added.response.get("ok"):
                return _error(operation, "event", added.response)
        if command.attendees:
            refreshed = await executor.execute(
                "tool_get_event",
                {"event_id": event_id},
                tool_call_id=f"{tool_call_prefix}-get",
            )
            if refreshed.response.get("ok"):
                created = refreshed
        return FlashSkillResult(
            status="success",
            operation=operation,
            kind="event",
            entity_id=event_id,
            snapshot=dict(created.response),
        )

    target = await _resolve_single_event(
        command,
        executor,
        tool_call_prefix=tool_call_prefix,
    )
    if isinstance(target, FlashSkillResult):
        return target
    event_id = str(target.get("event_id") or "")
    if operation == "delete":
        outcome = await executor.execute(
            "tool_delete_event",
            {"event_id": event_id},
            tool_call_id=f"{tool_call_prefix}-delete",
        )
    else:
        patch = {
            key: value
            for key, value in {
                "title": command.title,
                "description": command.description,
                "location": command.location,
                "start_at": command.start_at.isoformat()
                if command.start_at is not None
                else None,
                "end_at": command.end_at.isoformat()
                if command.end_at is not None
                else None,
                "all_day": command.all_day if command.all_day else None,
            }.items()
            if value is not None
        }
        outcome = await executor.execute(
            "tool_update_event",
            {"event_id": event_id, "patch": patch},
            tool_call_id=f"{tool_call_prefix}-update",
        )
    if not outcome.response.get("ok"):
        return _error(operation, "event", outcome.response)
    return FlashSkillResult(
        status="success",
        operation=operation,
        kind="event",
        entity_id=event_id,
        snapshot=dict(outcome.response),
    )


def _event_query_arguments(command: CaptureRecordCommand) -> dict[str, Any]:
    return {
        "contains": (
            command.match_text or command.title or ""
        ).strip(),
        "limit": 20,
    }


async def _resolve_single_event(
    command: CaptureRecordCommand,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str,
) -> dict[str, Any] | FlashSkillResult:
    if (command.target_id or "").strip():
        return {"event_id": command.target_id}
    queried = await executor.execute(
        "tool_query_event",
        _event_query_arguments(command),
        tool_call_id=f"{tool_call_prefix}-query",
    )
    if not queried.response.get("ok"):
        return _error(command.operation or "query", "event", queried.response)
    events = [
        dict(item)
        for item in queried.response.get("events") or []
        if isinstance(item, dict)
    ]
    if len(events) != 1:
        return FlashSkillResult(
            status="error",
            operation=command.operation or "query",
            kind="event",
            snapshots=events,
            error="未找到唯一日程，未执行变更",
        )
    return events[0]


async def _unique_contact_id(
    name: str,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str,
) -> str | None:
    queried = await executor.execute(
        "tool_query_contact",
        {"name_query": name, "limit": 50},
        tool_call_id=f"{tool_call_prefix}-query",
    )
    if not queried.response.get("ok"):
        return None
    exact = queried.response.get("exact_contacts") or []
    if len(exact) != 1 or not isinstance(exact[0], dict):
        return None
    return str(exact[0].get("contact_id") or "") or None


def _error(
    operation: str,
    kind: str,
    response: dict[str, Any],
) -> FlashSkillResult:
    return FlashSkillResult(
        status="error",
        operation=operation,
        kind=kind,
        error=str(response.get("error") or "记录处理失败"),
    )
