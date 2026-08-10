from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from app.internal_mcp.runtime import (
    InternalMCPRuntime,
    InternalMCPTrustedContext,
    get_internal_mcp_runtime,
)
from app.domains.sessions.card_contract import (
    SessionCardSource,
    SessionCardSourceKind,
    cards_from_tool_result,
)


CHAT_TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "query_assets",
            "description": "Query the current user's recent assets.",
            "parameters": {
                "type": "object",
                "properties": {
                    "skill_machine_name": {"type": "string"},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 20},
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_asset",
            "description": "Create a current-user asset through Eureka CRUD.",
            "parameters": {
                "type": "object",
                "properties": {
                    "skill_machine_name": {"type": "string"},
                    "payload": {"type": "object"},
                    "effective_at": {"type": "string"},
                    "period": {"type": "string"},
                    "occurred_at": {"type": "string"},
                    "domain": {"type": "string"},
                },
                "required": ["skill_machine_name", "payload"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_events",
            "description": "Query the current user's recent calendar events.",
            "parameters": {
                "type": "object",
                "properties": {
                    "limit": {"type": "integer", "minimum": 1, "maximum": 20}
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_event",
            "description": "Create a current-user calendar event with a complete range.",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "location": {"type": "string"},
                    "start_at": {"type": "string"},
                    "end_at": {"type": "string"},
                    "all_day": {"type": "boolean"},
                },
                "required": ["title", "start_at", "end_at"],
                "additionalProperties": False,
            },
        },
    },
]


PENDING_ACTION_TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "resolve_pending_contact",
            "description": (
                "Resolve a contact confirmation already present in pending_actions. "
                "Both IDs must be copied from that stored context."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "pending_action_id": {"type": "string"},
                    "contact_id": {"type": "string"},
                },
                "required": ["pending_action_id", "contact_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "cancel_pending_action",
            "description": (
                "Cancel a confirmation already present in pending_actions without "
                "mutating any contact."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "pending_action_id": {"type": "string"},
                },
                "required": ["pending_action_id"],
                "additionalProperties": False,
            },
        },
    },
]


@dataclass(frozen=True)
class ToolOutcome:
    response: dict[str, Any]
    cards: list[dict] = field(default_factory=list)


class SessionToolExecutor:
    def __init__(
        self,
        *,
        user_id: str,
        session_id: str,
        input_turn_id: str | None,
        reference_datetime: datetime | None = None,
        source_kind: SessionCardSourceKind = "chat",
        runtime: InternalMCPRuntime | None = None,
    ) -> None:
        self.user_id = user_id
        self.session_id = session_id
        self.input_turn_id = input_turn_id
        self.reference_datetime = reference_datetime
        self.source_kind = source_kind
        self.runtime = runtime or get_internal_mcp_runtime()

    async def definitions(self) -> list[dict[str, Any]]:
        return [
            *(await self.runtime.list_openai_tools()),
            *PENDING_ACTION_TOOL_DEFINITIONS,
        ]

    async def execute(
        self,
        name: str,
        arguments: dict[str, Any],
        *,
        tool_call_id: str | None = None,
    ) -> ToolOutcome:
        if name in {"resolve_pending_contact", "cancel_pending_action"}:
            return await self._execute_pending_action(name, arguments)
        internal_name = {
            "query_assets": "tool_query_asset",
            "create_asset": "tool_create_asset",
            "query_events": "tool_query_event",
            "create_event": "tool_create_event",
        }.get(name, name)
        normalized = dict(arguments)
        normalized.pop("reference_datetime", None)
        if internal_name == "tool_create_todo" and self.reference_datetime is not None:
            normalized["reference_datetime"] = self.reference_datetime.isoformat()
        if "skill_machine_name" in normalized:
            normalized["user_skill_name"] = normalized.pop("skill_machine_name")
        for json_field in ("payload", "payload_patch", "patch"):
            if isinstance(normalized.get(json_field), dict):
                normalized[json_field] = json.dumps(
                    normalized[json_field], ensure_ascii=False
                )
        result = await self.runtime.call_tool(
            internal_name,
            normalized,
            trusted=InternalMCPTrustedContext(
                user_id=self.user_id,
                session_id=self.session_id,
                input_turn_id=self.input_turn_id,
                tool_call_id=tool_call_id,
            ),
        )
        cards: list[dict] = []
        if self.session_id and self.input_turn_id:
            cards = cards_from_tool_result(
                internal_name,
                result,
                SessionCardSource(
                    session_id=self.session_id,
                    input_turn_id=self.input_turn_id,
                    kind=self.source_kind,
                ),
            )
        return ToolOutcome(response=result, cards=cards)

    async def _execute_pending_action(
        self,
        name: str,
        arguments: dict[str, Any],
    ) -> ToolOutcome:
        from app.db.session import session_scope
        from app.domains.sessions import pending_actions

        action_id = arguments.get("pending_action_id")
        if not isinstance(action_id, str) or not action_id:
            return ToolOutcome(
                response={"ok": False, "error": "pending_action_id is required"}
            )
        try:
            async with session_scope() as database:
                if name == "resolve_pending_contact":
                    contact_id = arguments.get("contact_id")
                    if not isinstance(contact_id, str) or not contact_id:
                        return ToolOutcome(
                            response={
                                "ok": False,
                                "error": "contact_id is required",
                            }
                        )
                    action = await pending_actions.resolve_contact_pending_action(
                        database,
                        self.user_id,
                        action_id,
                        contact_id=contact_id,
                        resolution_source="chat",
                        session_id=self.session_id,
                    )
                else:
                    action = await pending_actions.cancel_pending_action(
                        database,
                        self.user_id,
                        action_id,
                        resolution_source="chat",
                        session_id=self.session_id,
                    )
                payload = pending_actions.pending_action_payload(action)
        except (
            pending_actions.PendingActionNotFound,
            pending_actions.PendingActionInvalid,
            pending_actions.PendingActionConflict,
        ) as exc:
            return ToolOutcome(response={"ok": False, "error": str(exc)})
        return ToolOutcome(response={"ok": True, "pending_action": payload})
