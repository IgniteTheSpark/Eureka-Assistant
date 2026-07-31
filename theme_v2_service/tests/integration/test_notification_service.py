from datetime import datetime, timedelta

from sqlalchemy import func, select

from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import (
    create_notification,
    delete_notification,
    list_notifications,
    mark_all_read,
    mark_read,
    prune_notifications,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _create(
    session,
    *,
    user_id: str,
    title: str,
    created_at: datetime,
    read: bool = False,
):
    notification = await create_notification(
        session,
        NotificationCreate(
            user_id=user_id,
            type="report_done",
            title=title,
        ),
    )
    notification.created_at = created_at
    notification.read = read
    await session.flush()
    return notification


async def test_notification_and_outbox_commit_together(session):
    notification = await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="report_done",
            title="报告已生成",
            link="report:r1",
        ),
    )
    await session.commit()

    events = list(await session.scalars(select(OutboxEvent)))
    assert len(events) == 1
    assert events[0].aggregate_id == notification.id
    assert events[0].event_type == "notification.created"
    assert events[0].payload_json == {"notification_id": notification.id}


async def test_rollback_removes_notification_and_outbox(session):
    await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="report_done",
            title="不会提交",
        ),
    )

    await session.rollback()

    notification_count = await session.scalar(
        select(func.count()).select_from(Notification)
    )
    outbox_count = await session.scalar(select(func.count()).select_from(OutboxEvent))
    assert notification_count == 0
    assert outbox_count == 0


async def test_list_is_newest_first_and_reports_unread(session):
    older = await _create(
        session,
        user_id="user-1",
        title="older",
        created_at=NOW - timedelta(minutes=2),
        read=True,
    )
    newer = await _create(
        session,
        user_id="user-1",
        title="newer",
        created_at=NOW - timedelta(minutes=1),
    )
    await _create(
        session,
        user_id="user-2",
        title="other",
        created_at=NOW,
    )
    await session.commit()

    notifications, unread = await list_notifications(session, "user-1", limit=30)

    assert [item.id for item in notifications] == [newer.id, older.id]
    assert unread == 1


async def test_mark_read_is_owner_scoped_and_idempotent(session):
    own = await _create(
        session,
        user_id="user-1",
        title="own",
        created_at=NOW,
    )
    other = await _create(
        session,
        user_id="user-2",
        title="other",
        created_at=NOW,
    )
    await session.commit()

    assert not await mark_read(session, "user-1", other.id)
    assert await mark_read(session, "user-1", own.id)
    assert await mark_read(session, "user-1", own.id)
    await session.commit()

    await session.refresh(own)
    await session.refresh(other)
    assert own.read is True
    assert other.read is False


async def test_mark_all_read_updates_only_current_user(session):
    first = await _create(
        session,
        user_id="user-1",
        title="first",
        created_at=NOW,
    )
    second = await _create(
        session,
        user_id="user-1",
        title="second",
        created_at=NOW,
        read=True,
    )
    other = await _create(
        session,
        user_id="user-2",
        title="other",
        created_at=NOW,
    )
    await session.commit()

    assert await mark_all_read(session, "user-1") == 1
    assert await mark_all_read(session, "user-1") == 0
    await session.commit()

    for item in (first, second, other):
        await session.refresh(item)
    assert first.read is True
    assert second.read is True
    assert other.read is False


async def test_delete_is_owner_scoped_and_idempotent(session):
    own = await _create(
        session,
        user_id="user-1",
        title="own",
        created_at=NOW,
    )
    other = await _create(
        session,
        user_id="user-2",
        title="other",
        created_at=NOW,
    )
    await session.commit()

    assert not await delete_notification(session, "user-1", other.id)
    assert await delete_notification(session, "user-1", own.id)
    assert not await delete_notification(session, "user-1", own.id)
    await session.commit()

    assert await session.get(Notification, own.id) is None
    assert await session.get(Notification, other.id) is not None


async def test_prune_deletes_only_rows_older_than_fourteen_days(session):
    expired = await _create(
        session,
        user_id="user-1",
        title="expired",
        created_at=NOW - timedelta(days=14, microseconds=1),
    )
    boundary = await _create(
        session,
        user_id="user-1",
        title="boundary",
        created_at=NOW - timedelta(days=14),
    )
    recent = await _create(
        session,
        user_id="user-2",
        title="recent",
        created_at=NOW - timedelta(days=1),
    )
    await session.commit()

    assert await prune_notifications(session, now=NOW) == 1
    await session.commit()

    assert await session.get(Notification, expired.id) is None
    assert await session.get(Notification, boundary.id) is not None
    assert await session.get(Notification, recent.id) is not None


async def test_create_truncates_title_to_storage_limit(session):
    notification = await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="report_done",
            title="x" * 300,
        ),
    )

    assert notification.title == "x" * 255
