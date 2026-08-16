from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select

from app.db.models import Asset, Event, UserSkill
from app.domains.notifications.models import (
    Notification,
    OutboxEvent,
    ReminderDelivery,
)
from app.domains.reminders.maintenance import dispatch_due_reminders


UTC = timezone.utc


async def _counts(session) -> tuple[int, int, int]:
    notifications = await session.scalar(select(func.count()).select_from(Notification))
    outbox = await session.scalar(select(func.count()).select_from(OutboxEvent))
    deliveries = await session.scalar(
        select(func.count()).select_from(ReminderDelivery)
    )
    return int(notifications or 0), int(outbox or 0), int(deliveries or 0)


async def _todo(session, *, payload: dict) -> None:
    session.add(
        UserSkill(
            id="skill-todo",
            user_id="user-1",
            machine_name="todo",
            display_name="待办",
            schema_json={},
            render_spec_json={},
        )
    )
    await session.flush()
    session.add(
        Asset(
            id="todo-1",
            user_id="user-1",
            user_skill_id="skill-todo",
            payload_json=payload,
        )
    )
    await session.flush()


async def test_todo_missing_preferences_dispatches_default_once(session):
    await _todo(
        session,
        payload={
            "title": "提交方案",
            "due_date": "2026-08-10T10:00:00Z",
            "status": "pending",
        },
    )
    now = datetime(2026, 8, 10, 9, 45, tzinfo=UTC)

    first = await dispatch_due_reminders(
        session,
        now=now,
        timezone_name="Asia/Shanghai",
    )
    second = await dispatch_due_reminders(
        session,
        now=now + timedelta(seconds=10),
        timezone_name="Asia/Shanghai",
    )

    assert first == 1
    assert second == 0
    assert await _counts(session) == (1, 1, 1)
    notification = await session.scalar(select(Notification))
    assert notification is not None
    assert notification.type == "todo_reminder"
    assert notification.link == "/assets/todo-1"


async def test_timed_event_dispatches_each_configured_offset_once(session):
    session.add(
        Event(
            id="event-1",
            user_id="user-1",
            title="项目会",
            start_at=datetime(2026, 8, 10, 10, 0),
            end_at=datetime(2026, 8, 10, 11, 0),
            all_day=False,
            status="scheduled",
            reminder_offsets_json=[60, 15],
        )
    )
    await session.flush()

    at_one_hour = await dispatch_due_reminders(
        session,
        now=datetime(2026, 8, 10, 9, 0, tzinfo=UTC),
        timezone_name="Asia/Shanghai",
    )
    at_fifteen = await dispatch_due_reminders(
        session,
        now=datetime(2026, 8, 10, 9, 45, tzinfo=UTC),
        timezone_name="Asia/Shanghai",
    )
    repeated = await dispatch_due_reminders(
        session,
        now=datetime(2026, 8, 10, 9, 45, 20, tzinfo=UTC),
        timezone_name="Asia/Shanghai",
    )

    assert (at_one_hour, at_fifteen, repeated) == (1, 1, 0)
    assert await _counts(session) == (2, 2, 2)


async def test_all_day_event_anchors_to_nine_local(session):
    session.add(
        Event(
            id="event-all-day",
            user_id="user-1",
            title="全天活动",
            start_at=datetime(2026, 8, 10, 0, 0),
            end_at=datetime(2026, 8, 11, 0, 0),
            all_day=True,
            status="scheduled",
            reminder_offsets_json=None,
        )
    )
    await session.flush()

    dispatched = await dispatch_due_reminders(
        session,
        now=datetime(2026, 8, 10, 0, 45, tzinfo=UTC),
        timezone_name="Asia/Shanghai",
    )

    assert dispatched == 1
    notification = await session.scalar(select(Notification))
    assert notification is not None
    assert notification.type == "event_reminder"


async def test_disabled_or_inactive_records_do_not_dispatch(session):
    await _todo(
        session,
        payload={
            "title": "已关闭提醒",
            "due_date": "2026-08-10T10:00:00Z",
            "status": "pending",
            "reminder_offsets_minutes": [],
        },
    )
    session.add(
        Event(
            id="event-cancelled",
            user_id="user-1",
            title="取消的会议",
            start_at=datetime(2026, 8, 10, 10, 0),
            end_at=datetime(2026, 8, 10, 11, 0),
            all_day=False,
            status="cancelled",
            reminder_offsets_json=[15],
        )
    )
    await session.flush()

    dispatched = await dispatch_due_reminders(
        session,
        now=datetime(2026, 8, 10, 9, 45, tzinfo=UTC),
        timezone_name="Asia/Shanghai",
    )

    assert dispatched == 0
    assert await _counts(session) == (0, 0, 0)
