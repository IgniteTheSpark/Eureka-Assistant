import asyncio
from datetime import datetime

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import DBAPIError, IntegrityError

from app.db.session import AsyncSessionFactory
from app.domains.triggers.models import (
    TriggerCountedAsset,
    TriggerExecution,
    TriggerTracker,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _seed_tracker() -> str:
    async with AsyncSessionFactory() as session:
        tracker = TriggerTracker(
            user_id="user-1",
            trigger_type="proactive_summary",
            scope_type="user_skill",
            scope_id="skill-1",
            cycle_started_at=NOW,
        )
        session.add(tracker)
        await session.commit()
        return tracker.id


async def _count_asset(tracker_id: str, asset_id: str) -> bool:
    async with AsyncSessionFactory() as session:
        session.add(
            TriggerCountedAsset(
                tracker_id=tracker_id,
                asset_id=asset_id,
                counted_at=NOW,
            )
        )
        try:
            await session.commit()
        except IntegrityError:
            await session.rollback()
            return False
        return True


async def test_same_asset_is_counted_once_under_concurrency(session):
    tracker_id = await _seed_tracker()

    inserted = await asyncio.gather(
        _count_asset(tracker_id, "asset-1"),
        _count_asset(tracker_id, "asset-1"),
    )

    assert sorted(inserted) == [False, True]
    async with AsyncSessionFactory() as check:
        assert await check.scalar(
            select(func.count()).select_from(TriggerCountedAsset)
        ) == 1


async def test_tracker_scope_is_unique(session):
    values = {
        "user_id": "user-1",
        "trigger_type": "proactive_summary",
        "scope_type": "user_skill",
        "scope_id": "skill-1",
        "cycle_started_at": NOW,
    }
    session.add_all([TriggerTracker(**values), TriggerTracker(**values)])

    with pytest.raises(IntegrityError):
        await session.commit()
    await session.rollback()


async def test_execution_revision_must_be_positive(session):
    session.add(
        TriggerExecution(
            user_id="user-1",
            trigger_type="pre_event_report",
            workflow_type="report_generation",
            scope_type="event",
            scope_id="event-1",
            status="available",
            dedupe_key="pre_event_report:event-1:2026-07-31T10:00:00",
            revision=0,
            payload_json={},
            first_fired_at=NOW,
            last_fired_at=NOW,
        )
    )

    with pytest.raises(DBAPIError):
        await session.commit()
    await session.rollback()
