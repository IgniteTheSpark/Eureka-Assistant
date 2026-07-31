from datetime import date, datetime, timedelta

from sqlalchemy import func, select

from app.db.models import Event
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.triggers.maintenance import (
    TriggerMaintenanceResult,
    run_trigger_maintenance,
)
from app.domains.triggers.models import TriggerExecution, TriggerTracker
from app.domains.triggers.pre_event_report import scan_pre_event_window


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _proactive(
    session,
    *,
    scope_id: str = "skill-1",
    revision: int = 2,
):
    tracker = TriggerTracker(
        user_id="user-1",
        trigger_type="proactive_summary",
        scope_type="user_skill",
        scope_id=scope_id,
        cycle_started_at=NOW - timedelta(days=10),
        new_asset_count=8,
        last_notified_local_date=date(2026, 7, 30),
    )
    session.add(tracker)
    await session.flush()
    execution = TriggerExecution(
        user_id="user-1",
        trigger_type="proactive_summary",
        workflow_type="report_generation",
        tracker_id=tracker.id,
        scope_type="user_skill",
        scope_id=scope_id,
        status="available",
        dedupe_key=f"proactive_summary:{tracker.id}:cycle-1",
        revision=revision,
        payload_json={
            "primary_skill_id": scope_id,
            "asset_ids": [f"asset-{index}" for index in range(8)],
            "scope_started_at": "2026-07-21T10:00:00Z",
            "scope_ended_at": "2026-07-31T10:00:00Z",
            "asset_count": 8,
        },
        first_fired_at=NOW - timedelta(days=1),
        last_fired_at=NOW,
        last_notified_revision=revision - 1,
    )
    session.add(execution)
    await session.flush()
    tracker.active_execution_id = execution.id
    return tracker, execution


async def test_repairs_available_execution_with_unnotified_revision(session):
    tracker, execution = await _proactive(session)

    result = await run_trigger_maintenance(session, now=NOW)

    assert result.notifications_repaired == 1
    notification = await session.scalar(select(Notification))
    assert notification.link == f"report-start:{execution.id}:2"
    assert execution.last_notified_revision == 2
    assert tracker.last_notified_local_date == date(2026, 7, 31)


async def test_existing_notification_repairs_stale_ack_without_duplicate(session):
    tracker, execution = await _proactive(session)
    await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="report_available",
            title="already created",
            link=f"report-start:{execution.id}:2",
        ),
    )

    result = await run_trigger_maintenance(session, now=NOW)

    assert result.notifications_repaired == 1
    assert await session.scalar(
        select(func.count()).select_from(Notification)
    ) == 1
    assert execution.last_notified_revision == 2
    assert tracker.last_notified_local_date == date(2026, 7, 31)


async def test_repairs_tracker_references_to_missing_or_expired_execution(session):
    missing = TriggerTracker(
        user_id="user-1",
        trigger_type="proactive_summary",
        scope_type="user_skill",
        scope_id="skill-missing",
        cycle_started_at=NOW,
        active_execution_id="missing-execution",
    )
    session.add(missing)
    expired_tracker, expired_execution = await _proactive(
        session,
        scope_id="skill-expired",
    )
    expired_execution.status = "expired"
    await session.flush()

    result = await run_trigger_maintenance(session, now=NOW)

    assert result.trackers_repaired == 2
    assert missing.active_execution_id is None
    assert expired_tracker.active_execution_id is None


async def test_cancelled_and_started_event_executions_are_compensated(session):
    cancelled = Event(
        user_id="user-1",
        title="cancelled",
        start_at=NOW + timedelta(minutes=10),
        end_at=NOW + timedelta(hours=1),
        all_day=False,
        status="scheduled",
    )
    started = Event(
        user_id="user-1",
        title="started",
        start_at=NOW + timedelta(minutes=5),
        end_at=NOW + timedelta(hours=1),
        all_day=False,
        status="scheduled",
    )
    session.add_all([cancelled, started])
    await session.flush()
    assert await scan_pre_event_window(session, now=NOW) == 2
    cancelled.status = "cancelled"
    await session.flush()

    result = await run_trigger_maintenance(
        session,
        now=NOW + timedelta(minutes=5),
    )

    assert result.expired == 2
    statuses = list(await session.scalars(select(TriggerExecution.status)))
    assert statuses == ["expired", "expired"]


async def test_same_maintenance_window_is_repeat_safe(session):
    session.add(
        Event(
            user_id="user-1",
            title="upcoming",
            start_at=NOW + timedelta(minutes=30),
            end_at=NOW + timedelta(hours=1),
            all_day=False,
            status="scheduled",
        )
    )
    await session.flush()

    first = await run_trigger_maintenance(session, now=NOW)
    second = await run_trigger_maintenance(session, now=NOW)

    assert first == TriggerMaintenanceResult(
        expired=0,
        fired=1,
        notifications_repaired=0,
        trackers_repaired=0,
    )
    assert second == TriggerMaintenanceResult(0, 0, 0, 0)
    assert await session.scalar(
        select(func.count()).select_from(TriggerExecution)
    ) == 1
    assert await session.scalar(
        select(func.count()).select_from(Notification)
    ) == 1
