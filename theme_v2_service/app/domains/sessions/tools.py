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


_AGENT_PERIOD_ALIASES = {
    "凌晨": "凌晨",
    "清晨": "上午",
    "早晨": "上午",
    "早上": "上午",
    "上午": "上午",
    "中午": "中午",
    "午后": "下午",
    "下午": "下午",
    "傍晚": "晚上",
    "晚上": "晚上",
    "今晚": "晚上",
    "夜里": "晚上",
    "夜间": "晚上",
}

_ROOT_TARGET_ID_ARGUMENTS = {
    "tool_update_asset": "asset_id",
    "tool_delete_asset": "asset_id",
    "tool_update_contact": "contact_id",
    "tool_delete_contact": "contact_id",
    "tool_update_event": "event_id",
    "tool_delete_event": "event_id",
}


def _canonical_agent_period(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    stripped = value.strip()
    return _AGENT_PERIOD_ALIASES.get(stripped, stripped)


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
        timezone_name: str = "Asia/Shanghai",
        capture_source_text: str | None = None,
        capture_domain: str | None = None,
        capture_intent_id: str | None = None,
        capture_operation: str | None = None,
        capture_target_id: str | None = None,
        source_kind: SessionCardSourceKind = "chat",
        runtime: InternalMCPRuntime | None = None,
    ) -> None:
        self.user_id = user_id
        self.session_id = session_id
        self.input_turn_id = input_turn_id
        self.reference_datetime = reference_datetime
        self.timezone_name = timezone_name
        self.capture_source_text = (capture_source_text or "").strip()
        self.capture_domain = (capture_domain or "").strip()
        self.capture_intent_id = (capture_intent_id or "").strip()
        self.capture_operation = (capture_operation or "").strip()
        self.capture_target_id = (capture_target_id or "").strip()
        self.source_kind = source_kind
        self.runtime = runtime or get_internal_mcp_runtime()

    def with_capture_target(self, target_id: str) -> SessionToolExecutor:
        """Return an executor that enforces the server-resolved mutation target."""
        return SessionToolExecutor(
            user_id=self.user_id,
            session_id=self.session_id,
            input_turn_id=self.input_turn_id,
            reference_datetime=self.reference_datetime,
            timezone_name=self.timezone_name,
            capture_source_text=self.capture_source_text,
            capture_domain=self.capture_domain,
            capture_intent_id=self.capture_intent_id,
            capture_operation=self.capture_operation,
            capture_target_id=target_id,
            source_kind=self.source_kind,
            runtime=self.runtime,
        )

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
        normalized.pop("timezone_name", None)
        target_argument = _ROOT_TARGET_ID_ARGUMENTS.get(internal_name)
        if (
            target_argument is not None
            and self.capture_operation in {"update", "delete"}
            and self.capture_target_id
        ):
            normalized[target_argument] = self.capture_target_id
        if internal_name in {
            "tool_create_asset",
            "tool_create_todo",
            "tool_create_note",
            "tool_create_event",
        }:
            if self.capture_source_text:
                normalized["source_text"] = self.capture_source_text
            if self.capture_domain and internal_name != "tool_create_event":
                normalized["domain"] = self.capture_domain
        if "period" in normalized:
            normalized["period"] = _canonical_agent_period(normalized["period"])
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
                reference_datetime=self.reference_datetime,
                timezone_name=self.timezone_name,
                intent_id=self.capture_intent_id or None,
                intent_operation=self.capture_operation or None,
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
