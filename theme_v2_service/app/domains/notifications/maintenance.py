import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.db.base import utc_now
from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.service import prune_notifications
from app.jobs.queue import enqueue_job


NOTIFICATION_PRUNE_JOB_TYPE = "notification_prune"
_SCHEDULER_INTERVAL_SECONDS = 3600
logger = logging.getLogger(__name__)


def _utc_date(now: datetime) -> str:
    if now.tzinfo is not None:
        now = now.astimezone(timezone.utc).replace(tzinfo=None)
    return now.date().isoformat()


async def handle_notification_prune(job: WorkflowJob) -> None:
    del job
    async with AsyncSessionFactory() as session:
        await prune_notifications(session, now=utc_now())
        await session.commit()


async def ensure_notification_prune_job(*, now: datetime) -> WorkflowJob:
    dedupe_key = f"maintenance:notification-prune:{_utc_date(now)}"
    async with AsyncSessionFactory() as session:
        try:
            job = await enqueue_job(
                session,
                job_type=NOTIFICATION_PRUNE_JOB_TYPE,
                dedupe_key=dedupe_key,
                available_at=now.replace(tzinfo=None),
            )
            await session.commit()
            return job
        except IntegrityError:
            await session.rollback()
            existing = await session.scalar(
                select(WorkflowJob).where(
                    WorkflowJob.input_dedupe_key == dedupe_key
                )
            )
            if existing is None:
                raise
            return existing


async def run_notification_prune_scheduler(
    *,
    stop_event: asyncio.Event,
    interval_seconds: float = _SCHEDULER_INTERVAL_SECONDS,
) -> None:
    while not stop_event.is_set():
        try:
            await ensure_notification_prune_job(now=utc_now())
        except Exception:
            logger.exception("failed to schedule notification pruning")

        try:
            await asyncio.wait_for(
                stop_event.wait(),
                timeout=interval_seconds,
            )
        except TimeoutError:
            pass
