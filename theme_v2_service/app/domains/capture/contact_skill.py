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

    updated = await executor.execute(
        "tool_update_contact",
        {"contact_id": contact_id, "patch": command.contact_patch},
        tool_call_id=f"{tool_call_prefix}-update",
    )
    return _success_or_error(updated.response)


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
