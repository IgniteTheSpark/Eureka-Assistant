from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import select

from app.db.models import Asset, Event, UserSkill
from app.db.session import session_scope
from app.domains.assets import service as asset_service
from app.domains.assets.schemas import AssetCreate, EventCreate


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
            "description": "Create a schema-valid current-user asset.",
            "parameters": {
                "type": "object",
                "properties": {
                    "skill_machine_name": {"type": "string"},
                    "payload": {"type": "object"},
                    "effective_at": {"type": "string"},
                    "period": {"type": "string"},
                    "occurred_at": {"type": "string"},
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
                    "attendees": {"type": "array", "items": {"type": "object"}},
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
        self, *, user_id: str, session_id: str, input_turn_id: str | None
    ) -> None:
        self.user_id = user_id
        self.session_id = session_id
        self.input_turn_id = input_turn_id

    async def execute(self, name: str, arguments: dict[str, Any]) -> ToolOutcome:
        if name == "query_assets":
            return await self._query_assets(arguments)
        if name == "create_asset":
            return await self._create_asset(arguments)
        if name == "query_events":
            return await self._query_events(arguments)
        if name == "create_event":
            return await self._create_event(arguments)
        raise ValueError("unsupported chat tool")

    async def _query_assets(self, arguments: dict[str, Any]) -> ToolOutcome:
        limit = min(max(int(arguments.get("limit", 10)), 1), 20)
        machine_name = str(arguments.get("skill_machine_name", "")).strip()
        async with session_scope() as database:
            query = (
                select(Asset, UserSkill)
                .join(UserSkill, UserSkill.id == Asset.user_skill_id)
                .where(Asset.user_id == self.user_id, UserSkill.user_id == self.user_id)
            )
            if machine_name:
                query = query.where(UserSkill.machine_name == machine_name)
            rows = (
                await database.execute(
                    query.order_by(Asset.created_at.desc(), Asset.id.desc()).limit(limit)
                )
            ).all()
        cards = [
            {
                "id": asset.id,
                "asset_id": asset.id,
                "user_skill_id": skill.id,
                "user_skill_name": skill.machine_name,
                "payload": asset.payload_json,
            }
            for asset, skill in rows
        ]
        return ToolOutcome(response={"assets": cards, "count": len(cards)}, cards=cards)

    async def _create_asset(self, arguments: dict[str, Any]) -> ToolOutcome:
        machine_name = str(arguments.get("skill_machine_name", "")).strip()
        async with session_scope() as database:
            skill = await database.scalar(
                select(UserSkill).where(
                    UserSkill.user_id == self.user_id,
                    UserSkill.machine_name == machine_name,
                )
            )
            if skill is None:
                raise LookupError("skill not found")
            command = AssetCreate(
                user_skill_id=skill.id,
                payload=arguments.get("payload") or {},
                effective_at=arguments.get("effective_at"),
                period=arguments.get("period"),
                occurred_at=arguments.get("occurred_at"),
                session_id=self.session_id,
            )
            asset = await asset_service.create_asset(database, self.user_id, command)
            asset.source_input_turn_id = self.input_turn_id
            await database.flush()
            card = {
                "id": asset.id,
                "asset_id": asset.id,
                "user_skill_id": skill.id,
                "user_skill_name": skill.machine_name,
                "payload": asset.payload_json,
            }
        return ToolOutcome(response={"asset": card}, cards=[card])

    async def _query_events(self, arguments: dict[str, Any]) -> ToolOutcome:
        limit = min(max(int(arguments.get("limit", 10)), 1), 20)
        async with session_scope() as database:
            rows = list(
                await database.scalars(
                    select(Event)
                    .where(Event.user_id == self.user_id)
                    .order_by(Event.start_at.desc(), Event.id.desc())
                    .limit(limit)
                )
            )
        events = [
            {
                "id": event.id,
                "title": event.title,
                "start_at": event.start_at.isoformat(),
                "end_at": event.end_at.isoformat(),
            }
            for event in rows
        ]
        return ToolOutcome(response={"events": events, "count": len(events)})

    async def _create_event(self, arguments: dict[str, Any]) -> ToolOutcome:
        command = EventCreate.model_validate(arguments)
        async with session_scope() as database:
            event = await asset_service.create_event(database, self.user_id, command)
            card = {
                "id": event.id,
                "user_skill_name": "event",
                "payload": {
                    "title": event.title,
                    "description": event.description,
                    "start_at": event.start_at.isoformat(),
                    "end_at": event.end_at.isoformat(),
                },
            }
        return ToolOutcome(response={"event": card}, cards=[card])
