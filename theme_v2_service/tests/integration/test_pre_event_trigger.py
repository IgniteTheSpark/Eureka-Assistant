from datetime import datetime, timedelta

from sqlalchemy import func, select

from app.db.models import Event
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.triggers.models import TriggerExecution, TriggerTracker
from app.domains.triggers.pre_event_report import (
    expire_stale_pre_event_executions,
    scan_pre_event_window,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _event(
    session,
    *,
    title: str = "合作讨论",
    start_at: datetime,
    status: str = "scheduled",
    all_day: bool = False,
) -> Event:
    event = Event(
        user_id="user-1",
        title=title,
        start_at=start_at,
        end_at=start_at + timedelta(hours=1),
        all_day=all_day,
        status=status,
    )
    session.add(event)
    await session.flush()
    return event


async def test_t_minus_sixty_creates_one_execution_and_notification(session):
    event = await _event(session, start_at=NOW + timedelta(hours=1))

    assert await scan_pre_event_window(session, now=NOW) == 1
    assert await scan_pre_event_window(session, now=NOW) == 0

    execution = await session.scalar(select(TriggerExecution))
    notification = await session.scalar(select(Notification))
    assert execution.tracker_id is None
    assert execution.revision == 1
    assert execution.last_notified_revision == 1
    assert execution.payload_json == {
        "event_id": event.id,
        "event_start_at": "2026-07-31T11:00:00Z",
        "event_title": "合作讨论",
    }
    assert execution.dedupe_key == (
        f"pre_event_report:{event.id}:2026-07-31T11:00:00Z"
    )
    assert notification.type == "report_available"
    assert notification.title == "“合作讨论”将在 1 小时后开始"
    assert notification.body == "需要准备一份会前调研吗？"
    assert notification.link == f"report-start:{execution.id}:1"
    assert await session.scalar(
        select(func.count()).select_from(TriggerTracker)
    ) == 0


async def test_scan_skips_ineligible_and_outside_window_events(session):
    await _event(
        session,
        title="all-day",
        start_at=NOW + timedelta(minutes=30),
        all_day=True,
    )
    await _event(
        session,
        title="cancelled",
        start_at=NOW + timedelta(minutes=30),
        status="cancelled",
    )
    await _event(session, title="started", start_at=NOW)
    await _event(session, title="later", start_at=NOW + timedelta(hours=2))

    assert await scan_pre_event_window(session, now=NOW) == 0
    assert await session.scalar(
        select(func.count()).select_from(TriggerExecution)
    ) == 0


async def test_reschedule_expires_old_execution_and_creates_new_one(session):
    event = await _event(session, start_at=NOW + timedelta(minutes=30))
    assert await scan_pre_event_window(session, now=NOW) == 1
    original = await session.scalar(select(TriggerExecution))

    event.start_at = NOW + timedelta(minutes=45)
    event.end_at = NOW + timedelta(hours=1, minutes=45)
    await session.flush()
    assert await expire_stale_pre_event_executions(session, now=NOW) == 1
    assert await scan_pre_event_window(session, now=NOW) == 1

    executions = list(
        await session.scalars(
            select(TriggerExecution).order_by(TriggerExecution.created_at)
        )
    )
    assert len(executions) == 2
    assert original.status == "expired"
    assert executions[-1].status == "available"
    assert executions[-1].dedupe_key.endswith("2026-07-31T10:45:00Z")
    assert await session.scalar(
        select(func.count()).select_from(Notification)
    ) == 2


async def test_cancelled_and_started_executions_expire(session):
    cancelled = await _event(
        session,
        title="cancelled",
        start_at=NOW + timedelta(minutes=20),
    )
    started = await _event(
        session,
        title="started",
        start_at=NOW + timedelta(minutes=10),
    )
    assert await scan_pre_event_window(session, now=NOW) == 2

    cancelled.status = "cancelled"
    await session.flush()
    assert await expire_stale_pre_event_executions(
        session,
        now=NOW + timedelta(minutes=10),
    ) == 2

    statuses = list(
        await session.scalars(select(TriggerExecution.status))
    )
    assert statuses == ["expired", "expired"]


async def test_t_minus_thirty_and_fifteen_reminders_can_coexist(session):
    event = await _event(session, start_at=NOW + timedelta(hours=1))
    for threshold in (30, 15):
        await create_notification(
            session,
            NotificationCreate(
                user_id="user-1",
                type="reminder",
                title=f"Event starts in {threshold} minutes",
                link=f"reminder:event:{event.id}:{threshold}",
            ),
        )

    assert await scan_pre_event_window(session, now=NOW) == 1

    notifications = list(await session.scalars(select(Notification)))
    assert sorted(item.type for item in notifications) == [
        "reminder",
        "reminder",
        "report_available",
    ]
    assert sum(item.type == "report_available" for item in notifications) == 1
