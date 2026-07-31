from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select

from app.domains.triggers.models import (
    TriggerCountedAsset,
    TriggerExecution,
    TriggerTracker,
)
from app.domains.triggers.service import (
    ExecutionExpired,
    ExecutionNotFound,
    consume_execution,
    dismiss_execution,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _proactive_execution(session, *, user_id: str = "user-1"):
    tracker = TriggerTracker(
        user_id=user_id,
        trigger_type="proactive_summary",
        scope_type="user_skill",
        scope_id="skill-1",
        cycle_started_at=NOW - timedelta(days=10),
        new_asset_count=2,
    )
    session.add(tracker)
    await session.flush()
    execution = TriggerExecution(
        user_id=user_id,
        trigger_type="proactive_summary",
        workflow_type="report_generation",
        tracker_id=tracker.id,
        scope_type="user_skill",
        scope_id="skill-1",
        status="available",
        dedupe_key=f"proactive_summary:{tracker.id}:cycle-1",
        revision=2,
        payload_json={"asset_ids": ["asset-1", "asset-2"]},
        first_fired_at=NOW - timedelta(days=1),
        last_fired_at=NOW,
    )
    session.add(execution)
    await session.flush()
    tracker.active_execution_id = execution.id
    session.add_all(
        [
            TriggerCountedAsset(tracker_id=tracker.id, asset_id="asset-1"),
            TriggerCountedAsset(tracker_id=tracker.id, asset_id="asset-2"),
        ]
    )
    await session.flush()
    return tracker, execution


async def test_dismiss_moves_seven_day_window_from_latest_request(session):
    tracker, execution = await _proactive_execution(session)

    await dismiss_execution(
        session,
        user_id="user-1",
        execution_id=execution.id,
        now=NOW,
    )
    assert tracker.dismissed_until == NOW + timedelta(days=7)

    later = NOW + timedelta(days=2)
    await dismiss_execution(
        session,
        user_id="user-1",
        execution_id=execution.id,
        now=later,
    )
    assert tracker.dismissed_until == later + timedelta(days=7)
    assert execution.status == "available"
    assert tracker.new_asset_count == 2


async def test_consumption_is_idempotent_and_resets_proactive_cycle(session):
    tracker, execution = await _proactive_execution(session)

    consumed = await consume_execution(
        session,
        user_id="user-1",
        execution_id=execution.id,
        workflow_run_id="run-1",
        now=NOW,
    )

    assert consumed.status == "consumed"
    assert consumed.workflow_run_id == "run-1"
    assert consumed.consumed_at == NOW
    assert tracker.active_execution_id is None
    assert tracker.last_consumed_at == NOW
    assert tracker.proactive_suppressed_until == NOW + timedelta(days=7)
    assert tracker.cycle_started_at == NOW
    assert tracker.new_asset_count == 0
    assert await session.scalar(
        select(func.count()).select_from(TriggerCountedAsset)
    ) == 0

    repeated = await consume_execution(
        session,
        user_id="user-1",
        execution_id=execution.id,
        workflow_run_id="run-2",
        now=NOW + timedelta(days=1),
    )

    assert repeated.workflow_run_id == "run-1"
    assert tracker.cycle_started_at == NOW
    assert tracker.proactive_suppressed_until == NOW + timedelta(days=7)


async def test_expired_and_cross_user_consumption_are_distinct(session):
    _, execution = await _proactive_execution(session)
    execution.status = "expired"
    await session.flush()

    with pytest.raises(ExecutionExpired):
        await consume_execution(
            session,
            user_id="user-1",
            execution_id=execution.id,
            workflow_run_id="run-1",
            now=NOW,
        )
    with pytest.raises(ExecutionNotFound):
        await consume_execution(
            session,
            user_id="user-2",
            execution_id=execution.id,
            workflow_run_id="run-1",
            now=NOW,
        )


async def test_tracker_free_pre_event_execution_can_be_consumed(session):
    execution = TriggerExecution(
        user_id="user-1",
        trigger_type="pre_event_report",
        workflow_type="report_generation",
        tracker_id=None,
        scope_type="event",
        scope_id="event-1",
        status="available",
        dedupe_key="pre_event_report:event-1:start-1",
        revision=1,
        payload_json={"event_id": "event-1"},
        first_fired_at=NOW,
        last_fired_at=NOW,
    )
    session.add(execution)
    await session.flush()

    consumed = await consume_execution(
        session,
        user_id="user-1",
        execution_id=execution.id,
        workflow_run_id="run-1",
        now=NOW,
    )

    assert consumed.status == "consumed"
    assert consumed.workflow_run_id == "run-1"
    assert await session.scalar(select(func.count()).select_from(TriggerTracker)) == 0
