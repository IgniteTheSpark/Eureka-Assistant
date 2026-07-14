"""Transactional, user-scoped content deletion for exhibition demo accounts."""

from __future__ import annotations

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from db.models import (
    Asset,
    AssetField,
    CompletionEvent,
    Contact,
    Event,
    EventAttendee,
    EventFile,
    File,
    FlashRecording,
    InputTurn,
    Message,
    Notification,
    Nudge,
    Pet,
    Report,
    RhythmProfile,
    Session,
    Task,
)


def _rowcount(result) -> int:
    return int(result.rowcount or 0)


async def _delete(db: AsyncSession, model, user_id: str) -> int:
    result = await db.execute(delete(model).where(model.user_id == user_id))
    return _rowcount(result)


async def reset_demo_workspace(db: AsyncSession, user_id: str) -> dict[str, int]:
    """Delete one user's workspace content using the caller's transaction.

    Account, skill configuration, connected-app credentials, and physical-card
    configuration are deliberately outside this service's deletion set. The
    caller must wrap this function in ``async with db.begin()`` so any error
    rolls back every statement together.
    """
    counts: dict[str, int] = {}

    # Sessions point back to content rows that are deleted before the sessions.
    await db.execute(
        update(Session)
        .where(Session.user_id == user_id)
        .values(event_id=None, contact_id=None, file_id=None, subject_asset_id=None)
    )

    event_ids = select(Event.id).where(Event.user_id == user_id)
    counts["event_attendees"] = _rowcount(
        await db.execute(
            delete(EventAttendee).where(EventAttendee.event_id.in_(event_ids))
        )
    )
    counts["event_files"] = _rowcount(
        await db.execute(delete(EventFile).where(EventFile.event_id.in_(event_ids)))
    )

    # FK order is intentional: dependants precede assets/entities, then input,
    # sessions, and files. MySQL foreign-key enforcement remains enabled.
    for model in (
        FlashRecording,
        Message,
        Task,
        Notification,
        Report,
        Nudge,
        CompletionEvent,
        RhythmProfile,
        AssetField,
        Asset,
        Event,
        Contact,
        InputTurn,
        Session,
        File,
        Pet,
    ):
        counts[model.__tablename__] = await _delete(db, model, user_id)

    return counts
