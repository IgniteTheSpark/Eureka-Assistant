from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

from app.domains.capture.agent import CaptureRecordCommand
from app.domains.sessions.tools import SessionToolExecutor


@dataclass(frozen=True)
class ContactCommandResult:
    status: Literal["success", "pending_confirmation", "error"]
    contact_action: str | None = None
    contact_id: str | None = None
    contact: dict[str, Any] = field(default_factory=dict)
    candidates: list[dict[str, Any]] = field(default_factory=list)
    error: str | None = None


async def execute_contact_command(
    command: CaptureRecordCommand,
    executor: SessionToolExecutor,
    *,
    tool_call_prefix: str = "contact",
) -> ContactCommandResult:
    if command.kind != "contact":
        raise ValueError("contact executor requires a contact command")

    queried = await executor.execute(
        "tool_query_contact",
        {"name_query": command.name or "", "limit": 50},
        tool_call_id=f"{tool_call_prefix}-query",
    )
    if not queried.response.get("ok"):
        return ContactCommandResult(
            status="error",
            error=str(queried.response.get("error") or "联系人查询失败"),
        )
    candidates = [
        dict(candidate)
        for candidate in queried.response.get("exact_contacts") or []
        if isinstance(candidate, dict)
    ]
    if len(candidates) > 1:
        return ContactCommandResult(
            status="pending_confirmation",
            candidates=candidates,
        )

    if command.operation == "delete":
        if not candidates:
            return ContactCommandResult(status="error", error="未找到该联系人")
        deleted = await executor.execute(
            "tool_delete_contact",
            {"contact_id": candidates[0]["contact_id"]},
            tool_call_id=f"{tool_call_prefix}-delete",
        )
        return _success_or_error(deleted.response)

    if not candidates:
        created = await executor.execute(
            "tool_create_contact",
            {"name": command.name, **command.contact_patch},
            tool_call_id=f"{tool_call_prefix}-create",
        )
        return _success_or_error(created.response)

    contact_id = str(candidates[0].get("contact_id") or "")
    if not command.contact_patch:
        return ContactCommandResult(
            status="success",
            contact_action="updated",
            contact_id=contact_id,
            contact=dict(candidates[0]),
        )

    last_response: dict[str, Any] = dict(candidates[0])
    call_index = 0
    for field_name, value in _field_updates(command.contact_patch):
        updated = await executor.execute(
            "tool_update_contact",
            {"contact_id": contact_id, "field": field_name, "value": value},
            tool_call_id=f"{tool_call_prefix}-update-{call_index}",
        )
        call_index += 1
        if not updated.response.get("ok"):
            return ContactCommandResult(
                status="error",
                error=str(updated.response.get("error") or "联系人更新失败"),
            )
        last_response = updated.response
    return _success_or_error(last_response)


def _field_updates(patch: dict[str, Any]):
    for field_name in ("phone", "company", "title", "email"):
        if field_name in patch:
            yield field_name, str(patch[field_name] or "")
    notes = patch.get("notes")
    if isinstance(notes, str):
        notes = [notes]
    for note in notes or []:
        normalized = str(note).strip()
        if normalized:
            yield "notes", normalized
    socials = patch.get("socials")
    if isinstance(socials, dict):
        for network, handle in socials.items():
            yield str(network), str(handle or "")


def _success_or_error(response: dict[str, Any]) -> ContactCommandResult:
    if not response.get("ok"):
        return ContactCommandResult(
            status="error",
            error=str(response.get("error") or "联系人操作失败"),
        )
    return ContactCommandResult(
        status="success",
        contact_action=str(response.get("contact_action") or "updated"),
        contact_id=str(response.get("contact_id") or "") or None,
        contact={
            key: value
            for key, value in response.items()
            if key not in {"ok", "contact_action"}
        },
    )
