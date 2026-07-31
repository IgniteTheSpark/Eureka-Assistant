from datetime import datetime, timedelta

from sqlalchemy import func, select

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.maintenance import (
    NOTIFICATION_PRUNE_JOB_TYPE,
    ensure_notification_prune_job,
    handle_notification_prune,
)
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.jobs.registry import registry


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _create_at(session, title: str, created_at: datetime) -> str:
    notification = await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="maintenance-test",
            title=title,
        ),
    )
    notification.created_at = created_at
    await session.flush()
    return notification.id


async def test_notification_prune_handler_deletes_only_expired_rows(
    session,
    monkeypatch,
):
    expired_id = await _create_at(
        session,
        "expired",
        NOW - timedelta(days=14, microseconds=1),
    )
    boundary_id = await _create_at(
        session,
        "boundary",
        NOW - timedelta(days=14),
    )
    await session.commit()
    monkeypatch.setattr(
        "app.domains.notifications.maintenance.utc_now",
        lambda: NOW,
    )

    await handle_notification_prune(
        WorkflowJob(job_type=NOTIFICATION_PRUNE_JOB_TYPE)
    )

    async with AsyncSessionFactory() as check:
        assert await check.get(Notification, expired_id) is None
        assert await check.get(Notification, boundary_id) is not None


async def test_prune_job_is_deduped_per_utc_date(session):
    first = await ensure_notification_prune_job(now=NOW)
    repeated = await ensure_notification_prune_job(
        now=NOW + timedelta(hours=12)
    )
    next_day = await ensure_notification_prune_job(
        now=NOW + timedelta(days=1)
    )

    assert repeated.id == first.id
    assert next_day.id != first.id
    async with AsyncSessionFactory() as check:
        jobs = (
            await check.scalars(
                select(WorkflowJob)
                .where(WorkflowJob.job_type == NOTIFICATION_PRUNE_JOB_TYPE)
                .order_by(WorkflowJob.input_dedupe_key)
            )
        ).all()
        assert [job.input_dedupe_key for job in jobs] == [
            "maintenance:notification-prune:2026-07-31",
            "maintenance:notification-prune:2026-08-01",
        ]
        assert await check.scalar(
            select(func.count()).select_from(WorkflowJob)
        ) == 2


def test_global_worker_registry_contains_notification_prune_handler():
    assert registry.resolve(NOTIFICATION_PRUNE_JOB_TYPE) is handle_notification_prune
