from __future__ import annotations

from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.domains.contacts import service as contact_service
from app.domains.sessions import service as session_service
from app.domains.sessions.models import (
    AgentPendingAction,
    ChatSession,
    SessionMessage,
)


class PendingActionNotFound(LookupError):
    pass


class PendingActionInvalid(ValueError):
    pass


class PendingActionConflict(RuntimeError):
    pass


def pending_action_payload(action: AgentPendingAction) -> dict:
    return {
        "id": action.id,
        "kind": action.kind,
        "operation": action.operation,
        "status": action.status,
        "session_id": action.session_id,
        "input_turn_id": action.input_turn_id,
        "agent_message_id": action.agent_message_id,
        "candidates": action.candidates_json or [],
        "intent": action.intent_json or {},
        "selected_contact_id": action.selected_entity_id,
        "resolution_source": action.resolution_source,
        "resolved_at": action.resolved_at.isoformat()
        if action.resolved_at is not None
        else None,
    }


async def _owned_pending_action(
    database: AsyncSession,
    user_id: str,
    action_id: str,
    *,
    session_id: str | None = None,
) -> AgentPendingAction:
    ownership = [
        AgentPendingAction.id == action_id,
        AgentPendingAction.user_id == user_id,
    ]
    if session_id is not None:
        ownership.append(AgentPendingAction.session_id == session_id)
    action = await database.scalar(
        select(AgentPendingAction)
        .where(*ownership)
        .with_for_update()
    )
    if action is None:
        raise PendingActionNotFound("pending action not found")
    if action.kind != "contact":
        raise PendingActionInvalid("unsupported pending action kind")
    return action


async def resolve_contact_pending_action(
    database: AsyncSession,
    user_id: str,
    action_id: str,
    *,
    contact_id: str,
    resolution_source: str,
    session_id: str | None = None,
) -> AgentPendingAction:
    action = await _owned_pending_action(
        database,
        user_id,
        action_id,
        session_id=session_id,
    )
    if action.status == "resolved":
        if action.selected_entity_id == contact_id:
            return action
        raise PendingActionConflict("pending action already resolved")
    if action.status == "cancelled":
        raise PendingActionConflict("pending action already cancelled")

    candidates = [
        dict(item)
        for item in action.candidates_json or []
        if isinstance(item, dict)
    ]
    allowed_ids = {str(item.get("contact_id") or "") for item in candidates}
    if contact_id not in allowed_ids:
        raise PendingActionInvalid("contact is not a stored candidate")
    contact = await contact_service.get_contact(database, user_id, contact_id)
    if contact is None:
        raise PendingActionInvalid("candidate contact no longer exists")

    snapshot = next(
        item for item in candidates if str(item.get("contact_id")) == contact_id
    )
    if action.operation == "delete":
        deleted = await contact_service.delete_contact(database, user_id, contact_id)
        if deleted is None:
            raise PendingActionInvalid("candidate contact no longer exists")
        card = {
            "card_type": "contact",
            "contact_id": contact_id,
            "contact_action": "deleted",
            "title": snapshot.get("name") or "联系人",
            "subtitle": "已删除",
            "icon": "👤",
            "accent_color": "neutral",
        }
    elif action.operation == "create_or_update":
        patch = (action.intent_json or {}).get("patch") or {}
        if not isinstance(patch, dict):
            raise PendingActionInvalid("stored contact patch is invalid")
        await _apply_patch(database, user_id, contact_id, patch)
        contact = await contact_service.get_contact(database, user_id, contact_id)
        assert contact is not None
        card = {
            "card_type": "contact",
            "contact_id": contact.id,
            "contact_action": "updated",
            "title": contact.name,
            "subtitle": "已更新",
            "name": contact.name,
            "company": contact.company,
            "job_title": contact.title,
            "phone": contact.phone,
            "email": contact.email,
            "icon": "👤",
            "accent_color": "neutral",
        }
    else:
        raise PendingActionInvalid("unsupported contact operation")

    action.status = "resolved"
    action.selected_entity_id = contact_id
    action.resolution_source = resolution_source
    action.resolved_at = utc_now()
    action.updated_at = utc_now()
    await _replace_pending_card(database, action, card)
    await database.flush()
    return action


async def cancel_pending_action(
    database: AsyncSession,
    user_id: str,
    action_id: str,
    *,
    resolution_source: str,
    session_id: str | None = None,
) -> AgentPendingAction:
    action = await _owned_pending_action(
        database,
        user_id,
        action_id,
        session_id=session_id,
    )
    if action.status == "cancelled":
        return action
    if action.status == "resolved":
        raise PendingActionConflict("pending action already resolved")
    action.status = "cancelled"
    action.resolution_source = resolution_source
    action.resolved_at = utc_now()
    action.updated_at = utc_now()
    await _replace_pending_card(
        database,
        action,
        {
            "card_type": "pending_cancelled",
            "title": (action.intent_json or {}).get("name") or "联系人",
            "subtitle": "已取消本次修改",
            "icon": "👤",
            "accent_color": "neutral",
        },
    )
    await database.flush()
    return action


async def _apply_patch(
    database: AsyncSession,
    user_id: str,
    contact_id: str,
    patch: dict,
) -> None:
    for field_name in ("phone", "company", "title", "email"):
        if field_name in patch:
            await contact_service.update_contact_field(
                database,
                user_id,
                contact_id,
                field=field_name,
                value=str(patch[field_name] or ""),
            )
    notes = patch.get("notes")
    if isinstance(notes, str):
        notes = [notes]
    for note in notes or []:
        if str(note).strip():
            await contact_service.update_contact_field(
                database,
                user_id,
                contact_id,
                field="notes",
                value=str(note),
            )
    socials = patch.get("socials")
    if isinstance(socials, dict):
        for network, handle in socials.items():
            await contact_service.update_contact_field(
                database,
                user_id,
                contact_id,
                field=str(network),
                value=str(handle or ""),
            )


async def _replace_pending_card(
    database: AsyncSession,
    action: AgentPendingAction,
    replacement: dict,
) -> None:
    if action.agent_message_id:
        message = await database.get(SessionMessage, action.agent_message_id)
        if message is not None:
            message.cards_json = [
                replacement
                if isinstance(card, dict)
                and card.get("pending_action_id") == action.id
                else card
                for card in message.cards_json or []
            ]
            remaining = await database.scalar(
                select(func.count())
                .select_from(AgentPendingAction)
                .where(
                    AgentPendingAction.agent_message_id == message.id,
                    AgentPendingAction.status == "pending",
                    AgentPendingAction.id != action.id,
                )
            )
            message.status = "waiting_confirmation" if remaining else "done"
            message.updated_at = utc_now()
    chat = await database.get(ChatSession, action.session_id)
    if chat is not None:
        await session_service.publish_session_changed(
            database,
            chat,
            reason="pending_action_resolved",
        )
