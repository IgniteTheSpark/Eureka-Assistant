import random
from datetime import datetime, timedelta

from sqlalchemy import and_, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.db.models import WorkflowJob
from app.jobs.models import JobStatus
from app.observability import metrics


async def enqueue_job(
    session: AsyncSession,
    *,
    job_type: str,
    run_id: str | None = None,
    dedupe_key: str | None = None,
    available_at: datetime | None = None,
    max_attempts: int = 3,
) -> WorkflowJob:
    if dedupe_key is not None:
        existing = await session.scalar(
            select(WorkflowJob).where(
                WorkflowJob.input_dedupe_key == dedupe_key
            )
        )
        if existing is not None:
            return existing

    job = WorkflowJob(
        run_id=run_id,
        job_type=job_type,
        status=JobStatus.QUEUED.value,
        max_attempts=max_attempts,
        available_at=available_at or utc_now(),
        input_dedupe_key=dedupe_key,
    )
    session.add(job)
    await session.flush()
    return job


async def enqueue_or_requeue_job(
    session: AsyncSession,
    *,
    job_type: str,
    run_id: str,
    dedupe_key: str,
    available_at: datetime | None = None,
    max_attempts: int = 3,
) -> WorkflowJob:
    job = await session.scalar(
        select(WorkflowJob)
        .where(WorkflowJob.input_dedupe_key == dedupe_key)
        .with_for_update()
    )
    if job is None:
        return await enqueue_job(
            session,
            job_type=job_type,
            run_id=run_id,
            dedupe_key=dedupe_key,
            available_at=available_at,
            max_attempts=max_attempts,
        )
    if job.status in {JobStatus.QUEUED.value, JobStatus.RUNNING.value}:
        return job
    now = available_at or utc_now()
    job.job_type = job_type
    job.run_id = run_id
    job.status = JobStatus.QUEUED.value
    job.attempt = 0
    job.max_attempts = max_attempts
    job.available_at = now
    job.lease_owner = None
    job.lease_expires_at = None
    job.checkpoint_json = None
    job.error_code = None
    job.error_message = None
    job.started_at = None
    job.completed_at = None
    job.updated_at = now
    await session.flush()
    return job


async def claim_next_job(
    session: AsyncSession,
    *,
    owner: str,
    now: datetime,
    lease_seconds: int,
) -> WorkflowJob | None:
    candidate = await session.scalar(
        select(WorkflowJob)
        .where(
            or_(
                and_(
                    WorkflowJob.status == JobStatus.QUEUED.value,
                    WorkflowJob.available_at <= now,
                ),
                and_(
                    WorkflowJob.status == JobStatus.RUNNING.value,
                    WorkflowJob.lease_expires_at < now,
                ),
            )
        )
        .order_by(WorkflowJob.available_at, WorkflowJob.created_at)
        .with_for_update(skip_locked=True)
        .limit(1)
    )
    if candidate is None:
        return None

    recovered_expired_lease = candidate.status == JobStatus.RUNNING.value
    candidate.status = JobStatus.RUNNING.value
    candidate.attempt += 1
    candidate.lease_owner = owner
    candidate.lease_expires_at = now + timedelta(seconds=lease_seconds)
    candidate.started_at = candidate.started_at or now
    candidate.updated_at = now
    await session.flush()
    if recovered_expired_lease:
        metrics.increment("job_lease_recovered_total")
    return candidate


async def renew_lease(
    session: AsyncSession,
    *,
    job_id: str,
    owner: str,
    now: datetime,
    lease_seconds: int,
) -> bool:
    result = await session.execute(
        update(WorkflowJob)
        .where(
            WorkflowJob.id == job_id,
            WorkflowJob.status == JobStatus.RUNNING.value,
            WorkflowJob.lease_owner == owner,
        )
        .values(
            lease_expires_at=now + timedelta(seconds=lease_seconds),
            updated_at=now,
        )
    )
    return result.rowcount == 1


async def complete_job(
    session: AsyncSession,
    *,
    job_id: str,
    owner: str,
    now: datetime,
) -> bool:
    result = await session.execute(
        update(WorkflowJob)
        .where(
            WorkflowJob.id == job_id,
            WorkflowJob.status == JobStatus.RUNNING.value,
            WorkflowJob.lease_owner == owner,
        )
        .values(
            status=JobStatus.SUCCEEDED.value,
            lease_owner=None,
            lease_expires_at=None,
            error_code=None,
            error_message=None,
            completed_at=now,
            updated_at=now,
        )
    )
    return result.rowcount == 1


async def defer_job(
    session: AsyncSession,
    *,
    job_id: str,
    owner: str,
    now: datetime,
    available_at: datetime,
    checkpoint: dict | None = None,
) -> bool:
    job = await session.scalar(
        select(WorkflowJob)
        .where(
            WorkflowJob.id == job_id,
            WorkflowJob.status == JobStatus.RUNNING.value,
            WorkflowJob.lease_owner == owner,
        )
        .with_for_update()
    )
    if job is None:
        return False
    job.status = JobStatus.QUEUED.value
    job.available_at = available_at
    job.lease_owner = None
    job.lease_expires_at = None
    job.checkpoint_json = checkpoint
    job.error_code = None
    job.error_message = None
    job.updated_at = now
    await session.flush()
    return True


def _retry_delay_seconds(
    attempt: int,
    *,
    jitter_seconds: float | None,
) -> float:
    base = min(300.0, float(2 ** max(attempt - 1, 0)))
    jitter = (
        random.uniform(0, min(base * 0.25, 30.0))
        if jitter_seconds is None
        else jitter_seconds
    )
    return base + max(0.0, jitter)


async def fail_job(
    session: AsyncSession,
    *,
    job_id: str,
    owner: str,
    now: datetime,
    error_code: str,
    error_message: str,
    retryable: bool,
    jitter_seconds: float | None = None,
) -> bool:
    job = await session.scalar(
        select(WorkflowJob)
        .where(
            WorkflowJob.id == job_id,
            WorkflowJob.status == JobStatus.RUNNING.value,
            WorkflowJob.lease_owner == owner,
        )
        .with_for_update()
    )
    if job is None:
        return False

    job.error_code = error_code
    job.error_message = error_message
    job.lease_owner = None
    job.lease_expires_at = None
    job.updated_at = now
    if retryable and job.attempt < job.max_attempts:
        job.status = JobStatus.QUEUED.value
        job.available_at = now + timedelta(
            seconds=_retry_delay_seconds(
                job.attempt,
                jitter_seconds=jitter_seconds,
            )
        )
        metrics.increment("job_retry_total")
    else:
        job.status = JobStatus.FAILED.value
        job.completed_at = now
    await session.flush()
    return True
