from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

import json

from sqlalchemy import delete, func, select, update
from sqlalchemy.dialects.mysql import insert as mysql_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import new_uuid, utc_now
from app.db.models import Asset, Contact, Event, UserSkill
from app.domains.notifications.service import publish_domain_event
from app.domains.sessions.legacy_assistant import LegacyChatContext
from app.domains.sessions.models import (
    AgentPendingAction,
    ChatSession,
    InputTurn,
    SessionMessage,
)
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


async def get_or_create_daily_flash_session(
    database: AsyncSession,
    user_id: str,
    session_date: date,
) -> ChatSession:
    """Return the physical daily Flash Session under a row lock.

    MySQL's upsert closes the absent-row race without rolling back the caller's
    capture transaction. The unique key is scoped to flash + local date, while
    ordinary chat sessions keep a null date.
    """
    now = utc_now()
    candidate_id = new_uuid()
    statement = mysql_insert(ChatSession).values(
        id=candidate_id,
        user_id=user_id,
        session_type="flash",
        session_date=session_date,
        revision=0,
        title=f"{session_date.month}月{session_date.day}日 闪念",
        subject_type=None,
        subject_id=None,
        context_asset_ids_json=[],
        created_at=now,
        updated_at=now,
    )
    await database.execute(
        statement.on_duplicate_key_update(id=ChatSession.id)
    )
    model = await database.scalar(
        select(ChatSession)
        .where(
            ChatSession.user_id == user_id,
            ChatSession.session_type == "flash",
            ChatSession.session_date == session_date,
        )
        .with_for_update()
    )
    if model is None:
        raise RuntimeError("daily flash session upsert failed")
    return model


async def create_input_turn(
    database: AsyncSession,
    model: ChatSession,
    *,
    text: str,
    source: str,
    file_id: str | None = None,
    recording_id: str | None = None,
    segments: list | None = None,
    asr_provider: str | None = None,
    language: str | None = None,
    provenance: dict | None = None,
) -> InputTurn:
    # The Session row is the allocation lock for monotonically ordered turns.
    locked = await database.scalar(
        select(ChatSession)
        .where(
            ChatSession.id == model.id,
            ChatSession.user_id == model.user_id,
        )
        .with_for_update()
    )
    if locked is None:
        raise LookupError("session not found")
    latest = await database.scalar(
        select(func.max(InputTurn.turn_index)).where(
            InputTurn.session_id == model.id
        )
    )
    turn = InputTurn(
        user_id=model.user_id,
        session_id=model.id,
        turn_index=int(latest) + 1 if latest is not None else 0,
        file_id=file_id,
        recording_id=recording_id,
        text=text,
        segments_json=segments or [],
        source=source,
        asr_provider=asr_provider,
        language=language,
        provenance_json=provenance or {},
    )
    database.add(turn)
    await database.flush()
    return turn


async def publish_session_changed(
    database: AsyncSession,
    model: ChatSession,
    *,
    reason: str,
) -> None:
    model.revision = int(model.revision or 0) + 1
    model.updated_at = utc_now()
    await database.flush()
    await publish_domain_event(
        database,
        event_type="session_changed",
        aggregate_type="chat_session",
        aggregate_id=model.id,
        user_id=model.user_id,
        payload={
            "session_id": model.id,
            "session_date": (
                model.session_date.isoformat() if model.session_date else None
            ),
            "revision": model.revision,
            "reason": reason,
        },
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
        "session_date": model.session_date.isoformat() if model.session_date else None,
        "revision": model.revision,
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
                    Asset.migrated_contact_id.is_(None),
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
                    Asset.user_id == model.user_id,
                    Asset.id.in_(command.add),
                    Asset.migrated_contact_id.is_(None),
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
    database: AsyncSession,
    model: ChatSession,
    *,
    input_turn_id: str,
    timezone_name: str,
    limit: int = 30,
) -> LegacyChatContext:
    context_ids = [str(value) for value in (model.context_asset_ids_json or [])]
    asset_query = (
        select(Asset, UserSkill)
        .join(UserSkill, UserSkill.id == Asset.user_skill_id)
        .where(
            Asset.user_id == model.user_id,
            UserSkill.user_id == model.user_id,
            Asset.migrated_contact_id.is_(None),
        )
        .order_by(Asset.created_at.desc(), Asset.id.desc())
        .limit(limit)
    )
    rows = (await database.execute(asset_query)).all()
    assets = [
        {
            "id": asset.id,
            "skill": skill.display_name,
            "payload": asset.payload_json,
            "machine_name": skill.machine_name,
            "display_name": skill.display_name,
            "domain": asset.domain,
            "period": asset.period,
            "source_input_turn_id": asset.source_input_turn_id,
            "from_this_session": asset.session_id == model.id,
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
    contacts = list(
        await database.scalars(
            select(Contact)
            .where(Contact.user_id == model.user_id)
            .order_by(Contact.updated_at.desc(), Contact.id.desc())
            .limit(limit)
        )
    )
    skills = list(
        await database.scalars(
            select(UserSkill)
            .where(UserSkill.user_id == model.user_id, UserSkill.enabled.is_(True))
            .order_by(UserSkill.position, UserSkill.created_at, UserSkill.id)
        )
    )
    turns = list(
        await database.scalars(
            select(InputTurn)
            .where(
                InputTurn.user_id == model.user_id,
                InputTurn.session_id == model.id,
            )
            .order_by(InputTurn.turn_index.desc())
            .limit(limit)
        )
    )
    turns.reverse()
    pending_actions = list(
        await database.scalars(
            select(AgentPendingAction)
            .where(
                AgentPendingAction.user_id == model.user_id,
                AgentPendingAction.session_id == model.id,
                AgentPendingAction.status == "pending",
            )
            .order_by(AgentPendingAction.created_at, AgentPendingAction.id)
            .limit(limit)
        )
    )
    payload = {
        "session": {
            "id": model.id,
            "type": model.session_type,
            "date": model.session_date.isoformat() if model.session_date else None,
            "subject_type": model.subject_type,
            "subject_id": model.subject_id,
            "attached_asset_ids": context_ids,
        },
        "enabled_skills": [
            {
                "machine_name": skill.machine_name,
                "display_name": skill.display_name,
                "description": skill.description,
                "domain": skill.domain,
                "schema": skill.schema_json,
                "queryable_fields": skill.queryable_fields_json,
            }
            for skill in skills
        ],
        "session_input_turns": [
            {
                "id": turn.id,
                "index": turn.turn_index,
                "source": turn.source,
                "text": turn.text,
                "created_at": _utc_z(turn.created_at),
            }
            for turn in turns
        ],
        "pending_actions": [
            {
                "id": action.id,
                "kind": action.kind,
                "operation": action.operation,
                "input_turn_id": action.input_turn_id,
                "candidates": action.candidates_json or [],
                "intent": action.intent_json or {},
            }
            for action in pending_actions
        ],
        "assets": assets,
        "events": [
            {
                "id": event.id,
                "title": event.title,
                "description": event.description,
                "location": event.location,
                "start_at": _utc_z(event.start_at),
                "end_at": _utc_z(event.end_at),
                "status": event.status,
                "source_input_turn_id": event.source_input_turn_id,
                "attendees": [
                    {
                        "id": attendee.id,
                        "name": attendee.name_raw,
                        "contact_id": attendee.contact_id,
                    }
                    for attendee in event.attendees
                ],
            }
            for event in events
        ],
        "contacts": [
            {
                "id": contact.id,
                "name": contact.name,
                "phone": contact.phone,
                "company": contact.company,
                "title": contact.title,
                "email": contact.email,
                "notes": contact.notes_json,
                "socials": contact.socials_json,
                "source_input_turn_id": contact.source_input_turn_id,
                "from_this_session": contact.session_id == model.id,
            }
            for contact in contacts
        ],
    }
    now_local = datetime.now(ZoneInfo(timezone_name)).isoformat()
    return LegacyChatContext(
        session_id=model.id,
        input_turn_id=input_turn_id,
        session_type=model.session_type,
        now_local=now_local,
        records_json=json.dumps(payload, ensure_ascii=False, default=str),
    )


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
    turn = await create_input_turn(
        database,
        model,
        text=user_text,
        source="typed",
        provenance={"kind": "session_chat", "route": "/api/chat"},
    )
    user_message = SessionMessage(
        session_id=model.id,
        user_id=model.user_id,
        role="user",
        status="done",
        text=user_text,
        input_turn_id=turn.id,
    )
    agent_message = SessionMessage(
        session_id=model.id,
        user_id=model.user_id,
        role="agent",
        status="running",
        text="",
        input_turn_id=turn.id,
    )
    database.add_all([user_message, agent_message])
    if not model.title:
        normalized = " ".join(user_text.split())
        model.title = normalized[:30] + ("…" if len(normalized) > 30 else "")
    model.updated_at = utc_now()
    await database.flush()
    await publish_session_changed(database, model, reason="chat_turn_created")
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
