from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.internal_mcp.tools import EurekaToolContext, execute_tool


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
    ) -> None:
        self.user_id = user_id
        self.session_id = session_id
        self.input_turn_id = input_turn_id

    async def execute(
        self,
        name: str,
        arguments: dict[str, Any],
        *,
        tool_call_id: str | None = None,
    ) -> ToolOutcome:
        internal_name = {
            "query_assets": "tool_query_asset",
            "create_asset": "tool_create_asset",
            "query_events": "tool_query_event",
            "create_event": "tool_create_event",
        }.get(name)
        if internal_name is None:
            raise ValueError("unsupported chat tool")
        normalized = dict(arguments)
        if "skill_machine_name" in normalized:
            normalized["user_skill_name"] = normalized.pop("skill_machine_name")
        result = await execute_tool(
            internal_name,
            normalized,
            context=EurekaToolContext(
                user_id=self.user_id,
                session_id=self.session_id,
                input_turn_id=self.input_turn_id,
                idempotency_prefix=f"chat:{self.input_turn_id or self.session_id}",
            ),
            tool_call_id=tool_call_id,
        )
        return ToolOutcome(
            response=result,
            cards=_cards_for_result(internal_name, result),
        )


def _cards_for_result(name: str, result: dict[str, Any]) -> list[dict]:
    if not result.get("ok"):
        return []
    if name in {"tool_create_asset", "tool_update_asset"}:
        return [
            {
                "id": result.get("asset_id"),
                "asset_id": result.get("asset_id"),
                "user_skill_name": result.get("user_skill_name"),
                "payload": result.get("payload") or {},
            }
        ]
    if name in {"tool_create_event", "tool_update_event"}:
        return [
            {
                "id": result.get("event_id"),
                "event_id": result.get("event_id"),
                "user_skill_name": "event",
                "payload": {
                    "title": result.get("title"),
                    "description": result.get("description"),
                    "start_at": result.get("start_at"),
                    "end_at": result.get("end_at"),
                    "location": result.get("location"),
                },
            }
        ]
    if name == "tool_query_asset":
        return [dict(item) for item in result.get("assets") or []]
    if name == "tool_query_event":
        return [dict(item) for item in result.get("events") or []]
    return []
