from __future__ import annotations

from datetime import datetime, timezone

import json

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import new_uuid, utc_now
from app.db.models import Asset, Event, UserSkill
from app.domains.sessions.models import ChatSession, SessionMessage
from app.domains.sessions.schemas import SessionContextUpdate, SessionCreate


def _utc_z(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


async def get_session(
    database: AsyncSession, user_id: str, session_id: str
) -> ChatSession | None:
    return await database.scalar(
        select(ChatSession).where(
            ChatSession.id == session_id, ChatSession.user_id == user_id
        )
    )


async def create_or_peek_session(
    database: AsyncSession, user_id: str, command: SessionCreate
) -> ChatSession | None:
    existing = None
    if command.subject_type and command.subject_id:
        existing = await database.scalar(
            select(ChatSession).where(
                ChatSession.user_id == user_id,
                ChatSession.subject_type == command.subject_type,
                ChatSession.subject_id == command.subject_id,
            )
        )
    if existing is not None or command.peek_only:
        return existing
    model = ChatSession(
        user_id=user_id,
        session_type=command.session_type,
        subject_type=command.subject_type,
        subject_id=command.subject_id,
    )
    database.add(model)
    await database.flush()
    return model


async def list_sessions(
    database: AsyncSession, user_id: str, *, limit: int = 100
) -> list[ChatSession]:
    return list(
        await database.scalars(
            select(ChatSession)
            .where(ChatSession.user_id == user_id)
            .order_by(ChatSession.updated_at.desc(), ChatSession.id.desc())
            .limit(limit)
        )
    )


def session_list_item(model: ChatSession) -> dict:
    return {
        "id": model.id,
        "title": model.title,
        "session_type": model.session_type,
        "subject_type": model.subject_type,
        "subject_id": model.subject_id,
        "created_at": _utc_z(model.created_at),
        "updated_at": _utc_z(model.updated_at),
    }


def _asset_label(asset: Asset, skill: UserSkill) -> str:
    payload = asset.payload_json or {}
    for key in ("title", "name", "content", "description"):
        value = str(payload.get(key, "")).strip()
        if value:
            return value[:80]
    return skill.display_name


async def session_detail(
    database: AsyncSession, model: ChatSession
) -> dict:
    ids = [str(value) for value in (model.context_asset_ids_json or [])]
    contexts: list[dict] = []
    if ids:
        rows = (
            await database.execute(
                select(Asset, UserSkill)
                .join(UserSkill, UserSkill.id == Asset.user_skill_id)
                .where(
                    Asset.user_id == model.user_id,
                    UserSkill.user_id == model.user_id,
                    Asset.id.in_(ids),
                )
            )
        ).all()
        by_id = {
            asset.id: {"id": asset.id, "label": _asset_label(asset, skill)}
            for asset, skill in rows
        }
        contexts = [by_id[item_id] for item_id in ids if item_id in by_id]
    return {**session_list_item(model), "context_assets": contexts}


async def update_context(
    database: AsyncSession,
    model: ChatSession,
    command: SessionContextUpdate,
) -> None:
    current = [str(value) for value in (model.context_asset_ids_json or [])]
    removals = set(command.remove)
    current = [item for item in current if item not in removals]
    if command.add:
        owned = set(
            await database.scalars(
                select(Asset.id).where(
                    Asset.user_id == model.user_id, Asset.id.in_(command.add)
                )
            )
        )
        if owned != set(command.add):
            raise LookupError("asset not found")
        for item in command.add:
            if item not in current:
                current.append(item)
    model.context_asset_ids_json = current
    model.updated_at = utc_now()
    await database.flush()


async def list_messages(
    database: AsyncSession, user_id: str, session_id: str
) -> list[SessionMessage]:
    return list(
        await database.scalars(
            select(SessionMessage)
            .where(
                SessionMessage.user_id == user_id,
                SessionMessage.session_id == session_id,
            )
            .order_by(SessionMessage.created_at, SessionMessage.id)
        )
    )


async def build_chat_context(
    database: AsyncSession, model: ChatSession, *, limit: int = 30
) -> str:
    context_ids = [str(value) for value in (model.context_asset_ids_json or [])]
    asset_query = (
        select(Asset, UserSkill)
        .join(UserSkill, UserSkill.id == Asset.user_skill_id)
        .where(Asset.user_id == model.user_id, UserSkill.user_id == model.user_id)
        .order_by(Asset.created_at.desc(), Asset.id.desc())
        .limit(limit)
    )
    rows = (await database.execute(asset_query)).all()
    assets = [
        {
            "id": asset.id,
            "skill": skill.display_name,
            "payload": asset.payload_json,
            "occurred_at": (
                _utc_z(asset.occurred_at) if asset.occurred_at is not None else None
            ),
            "created_at": _utc_z(asset.created_at),
            "attached": asset.id in context_ids,
        }
        for asset, skill in rows
    ]
    events = list(
        await database.scalars(
            select(Event)
            .where(Event.user_id == model.user_id)
            .order_by(Event.start_at.desc(), Event.id.desc())
            .limit(limit)
        )
    )
    payload = {
        "assets": assets,
        "events": [
            {
                "id": event.id,
                "title": event.title,
                "description": event.description,
                "start_at": _utc_z(event.start_at),
                "end_at": _utc_z(event.end_at),
            }
            for event in events
        ],
    }
    return json.dumps(payload, ensure_ascii=False, default=str)


def message_payload(message: SessionMessage) -> dict:
    return {
        "id": message.id,
        "role": message.role,
        "status": message.status,
        "text": message.text,
        "input_turn_id": message.input_turn_id,
        "tool_call": message.tool_call_json,
        "tool_result": message.tool_result_json,
        "cards": message.cards_json or [],
        "elapsed_ms": message.elapsed_ms,
        "total_tokens": message.token_count,
        "created_at": _utc_z(message.created_at),
    }


async def create_turn(
    database: AsyncSession,
    model: ChatSession,
    user_text: str,
) -> tuple[SessionMessage, SessionMessage]:
    turn_id = new_uuid()
    user_message = SessionMessage(
        session_id=model.id,
        user_id=model.user_id,
        role="user",
        status="done",
        text=user_text,
        input_turn_id=turn_id,
    )
    agent_message = SessionMessage(
        session_id=model.id,
        user_id=model.user_id,
        role="agent",
        status="running",
        text="",
        input_turn_id=turn_id,
    )
    database.add_all([user_message, agent_message])
    if not model.title:
        normalized = " ".join(user_text.split())
        model.title = normalized[:30] + ("…" if len(normalized) > 30 else "")
    model.updated_at = utc_now()
    await database.flush()
    return user_message, agent_message


async def delete_session(
    database: AsyncSession, user_id: str, session_id: str
) -> bool:
    model = await get_session(database, user_id, session_id)
    if model is None:
        return False
    await database.execute(
        update(Asset)
        .where(Asset.user_id == user_id, Asset.session_id == session_id)
        .values(session_id=None, source_input_turn_id=None)
    )
    await database.execute(
        delete(ChatSession).where(
            ChatSession.id == session_id, ChatSession.user_id == user_id
        )
    )
    await database.flush()
    return True
