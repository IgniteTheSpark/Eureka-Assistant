"""Live-MySQL integration checks for the exhibition workspace reset service.

Run inside the backend container:
    python -m scripts.test_demo_reset
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import uuid

from sqlalchemy import delete, func, select

from core.demo_reset import reset_demo_workspace
from db.database import AsyncSessionLocal, async_engine
from db.models import (
    Asset,
    AssetField,
    Card,
    CardBinding,
    CompletionEvent,
    ConnectedApp,
    Contact,
    Event,
    EventAttendee,
    EventFile,
    File,
    FlashRecording,
    GlobalSkill,
    InputTurn,
    Message,
    Notification,
    Nudge,
    Pet,
    Report,
    RhythmProfile,
    Session,
    Task,
    User,
    UserSkill,
)


CONTENT_MODELS = (
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
)


async def _count(model, user_id: str) -> int:
    async with AsyncSessionLocal() as db:
        value = await db.scalar(
            select(func.count()).select_from(model).where(model.user_id == user_id)
        )
        return int(value or 0)


async def _count_event_join(model, user_id: str) -> int:
    async with AsyncSessionLocal() as db:
        value = await db.scalar(
            select(func.count())
            .select_from(model)
            .join(Event, model.event_id == Event.id)
            .where(Event.user_id == user_id)
        )
        return int(value or 0)


async def _seed_workspace(db, user_id: str, user_skill_id: uuid.UUID, tag: str) -> None:
    session = Session(user_id=user_id, session_type="flash", title=tag)
    file = File(user_id=user_id, storage_url=f"fixture://{tag}", file_type="audio/mpeg")
    db.add_all((session, file))
    await db.flush()

    turn = InputTurn(
        user_id=user_id,
        session_id=session.id,
        file_id=file.id,
        index=0,
        text=tag,
        source="voice",
    )
    db.add(turn)
    await db.flush()

    asset = Asset(
        user_id=user_id,
        user_skill_id=user_skill_id,
        session_id=session.id,
        source_input_turn_id=turn.id,
        payload={"fixture": tag},
    )
    contact = Contact(user_id=user_id, name=tag, source_input_turn_id=turn.id)
    event = Event(
        user_id=user_id,
        title=tag,
        start_at=datetime.now(timezone.utc),
        source_input_turn_id=turn.id,
    )
    db.add_all((asset, contact, event))
    await db.flush()

    session.event_id = event.id
    session.contact_id = contact.id
    session.file_id = file.id
    session.subject_asset_id = asset.id
    db.add_all(
        (
            AssetField(
                asset_id=asset.id,
                user_id=user_id,
                field_name="fixture",
                value_text=tag,
            ),
            EventAttendee(event_id=event.id, contact_id=contact.id, role="attendee"),
            EventFile(event_id=event.id, file_id=file.id, kind="attachment"),
            Message(session_id=session.id, user_id=user_id, role="user", text=tag),
            Task(
                user_id=user_id,
                user_text=tag,
                result_asset_id=asset.id,
                session_id=session.id,
                source_input_turn_id=turn.id,
            ),
            Notification(user_id=user_id, type="fixture", title=tag),
            Report(
                user_id=user_id,
                title=tag,
                genre="digest",
                content_md=tag,
                html=f"<p>{tag}</p>",
            ),
            Nudge(user_id=user_id, type="A", kind="fixture", text=tag),
            CompletionEvent(user_id=user_id, source="record", ref=str(asset.id)),
            RhythmProfile(user_id=user_id, skill=tag, sample_n=1),
            Pet(user_id=user_id, seed=tag),
            FlashRecording(
                user_id=user_id,
                file_id=file.id,
                card_sn=tag,
                device_file_name=f"{tag}.mp3",
                client_task_id=tag,
                source="offline",
                s3_key=f"fixture/{tag}.mp3",
                tencent_status="finished",
                tencent_task_response={},
                upload_status="uploaded",
                process_status="done",
                session_id=session.id,
                input_turn_id=turn.id,
            ),
        )
    )


async def _cleanup_fixture(user_ids: tuple[str, str], skill_id: int, card_ids: list[uuid.UUID]) -> None:
    """Remove only rows created by this invocation, even after a failed assertion."""
    async with AsyncSessionLocal() as db:
        async with db.begin():
            for user_id in user_ids:
                event_ids = select(Event.id).where(Event.user_id == user_id)
                await db.execute(delete(EventAttendee).where(EventAttendee.event_id.in_(event_ids)))
                await db.execute(delete(EventFile).where(EventFile.event_id.in_(event_ids)))
                await db.execute(
                    Session.__table__.update()
                    .where(Session.user_id == user_id)
                    .values(event_id=None, contact_id=None, file_id=None, subject_asset_id=None)
                )
                for model in CONTENT_MODELS:
                    await db.execute(delete(model).where(model.user_id == user_id))
                await db.execute(delete(CardBinding).where(CardBinding.user_id == user_id))
                await db.execute(delete(ConnectedApp).where(ConnectedApp.user_id == user_id))
                await db.execute(delete(UserSkill).where(UserSkill.user_id == user_id))
                await db.execute(delete(User).where(User.id == user_id))
            await db.execute(delete(Card).where(Card.id.in_(card_ids)))
            await db.execute(delete(GlobalSkill).where(GlobalSkill.id == skill_id))


async def test_reset_is_user_scoped() -> None:
    suffix = uuid.uuid4().hex[:12]
    user_ids = (f"demo-reset-a-{suffix}", f"demo-reset-b-{suffix}")
    card_ids: list[uuid.UUID] = []
    skill_id = -1

    try:
        async with AsyncSessionLocal() as db:
            async with db.begin():
                skill = GlobalSkill(name=f"reset-fixture-{suffix}")
                users = [
                    User(id=user_ids[0], email=f"demo-reset-a-{suffix}@example.com", password_hash="fixture"),
                    User(id=user_ids[1], email=f"demo-reset-b-{suffix}@example.com", password_hash="fixture"),
                ]
                db.add_all((skill, *users))
                await db.flush()
                skill_id = skill.id

                for user_id in user_ids:
                    user_skill = UserSkill(user_id=user_id, skill_id=skill.id, display_name="fixture")
                    card = Card(
                        card_sn=f"{user_id}-sn",
                        card_device_uuid=f"{user_id}-device",
                    )
                    db.add_all((user_skill, card))
                    await db.flush()
                    card_ids.append(card.id)
                    db.add_all(
                        (
                            ConnectedApp(
                                user_id=user_id,
                                connector_id="fixture",
                                auth_type="token",
                                credentials_enc="fixture",
                            ),
                            CardBinding(
                                user_id=user_id,
                                card_id=card.id,
                                card_app_uuid=f"{user_id}-app",
                                active_card_id=card.id,
                            ),
                        )
                    )
                    await _seed_workspace(db, user_id, user_skill.id, user_id)

        # A caller-owned transaction must make every deletion reversible.
        try:
            async with AsyncSessionLocal() as db:
                async with db.begin():
                    await reset_demo_workspace(db, user_ids[0])
                    raise RuntimeError("forced rollback")
        except RuntimeError as exc:
            assert str(exc) == "forced rollback"
        assert await _count(Asset, user_ids[0]) == 1
        assert await _count_event_join(EventAttendee, user_ids[0]) == 1
        assert await _count_event_join(EventFile, user_ids[0]) == 1

        async with AsyncSessionLocal() as db:
            async with db.begin():
                counts = await reset_demo_workspace(db, user_ids[0])

        assert counts["assets"] == 1
        assert counts["event_attendees"] == 1
        assert counts["event_files"] == 1
        for model in CONTENT_MODELS:
            assert counts[model.__tablename__] == 1, model.__tablename__
        for model in (EventAttendee, EventFile):
            assert await _count_event_join(model, user_ids[0]) == 0, model.__tablename__
            assert await _count_event_join(model, user_ids[1]) == 1, model.__tablename__
        for model in CONTENT_MODELS:
            assert await _count(model, user_ids[0]) == 0, model.__tablename__
            assert await _count(model, user_ids[1]) == 1, model.__tablename__

        for model in (UserSkill, ConnectedApp, CardBinding):
            assert await _count(model, user_ids[0]) == 1, model.__tablename__
            assert await _count(model, user_ids[1]) == 1, model.__tablename__
        async with AsyncSessionLocal() as db:
            assert await db.scalar(select(func.count()).select_from(User).where(User.id.in_(user_ids))) == 2
            assert await db.scalar(select(func.count()).select_from(Card).where(Card.id.in_(card_ids))) == 2
            assert await db.scalar(select(func.count()).select_from(GlobalSkill).where(GlobalSkill.id == skill_id)) == 1
    finally:
        if skill_id != -1:
            await _cleanup_fixture(user_ids, skill_id, card_ids)


async def main() -> None:
    try:
        await test_reset_is_user_scoped()
        print("PASS - demo reset is user-scoped, preserves configuration, and rolls back")
    finally:
        await async_engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
