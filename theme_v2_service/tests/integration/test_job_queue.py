import asyncio
from datetime import datetime, timedelta

import pytest

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.jobs.queue import (
    claim_next_job,
    complete_job,
    enqueue_job,
    fail_job,
    renew_lease,
)


NOW = datetime(2026, 7, 31, 8, 0, 0)


async def _seed_job(
    *,
    dedupe_key: str,
    max_attempts: int = 3,
) -> str:
    async with AsyncSessionFactory() as session:
        async with session.begin():
            job = await enqueue_job(
                session,
                job_type="probe",
                dedupe_key=dedupe_key,
                available_at=NOW,
                max_attempts=max_attempts,
            )
            job_id = job.id
    return job_id


async def _claim(owner: str, now: datetime = NOW):
    async with AsyncSessionFactory() as session:
        async with session.begin():
            return await claim_next_job(
                session,
                owner=owner,
                now=now,
                lease_seconds=60,
            )


async def test_enqueue_is_idempotent_by_dedupe_key(session):
    first = await enqueue_job(
        session,
        job_type="probe",
        dedupe_key="probe:dedupe",
        available_at=NOW,
    )
    second = await enqueue_job(
        session,
        job_type="probe",
        dedupe_key="probe:dedupe",
        available_at=NOW,
    )

    assert second.id == first.id


async def test_two_workers_cannot_claim_the_same_job(session):
    job_id = await _seed_job(dedupe_key="probe:concurrency")

    first, second = await asyncio.gather(
        _claim("worker-a"),
        _claim("worker-b"),
    )

    claimed = [job.id for job in (first, second) if job is not None]
    assert claimed == [job_id]


async def test_expired_lease_can_be_reclaimed(session):
    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            job = WorkflowJob(
                job_type="probe",
                status="running",
                attempt=1,
                max_attempts=3,
                available_at=NOW - timedelta(minutes=5),
                lease_owner="dead-worker",
                lease_expires_at=NOW - timedelta(seconds=1),
                input_dedupe_key="probe:expired",
            )
            database_session.add(job)
            await database_session.flush()
            job_id = job.id

    reclaimed = await _claim("worker-b")

    assert reclaimed.id == job_id
    assert reclaimed.lease_owner == "worker-b"
    assert reclaimed.attempt == 2


async def test_worker_lane_claims_only_included_types(session):
    await enqueue_job(
        session,
        job_type="report_pipeline",
        dedupe_key="lane:primary",
        available_at=NOW,
    )
    illustration = await enqueue_job(
        session,
        job_type="report_illustration",
        dedupe_key="lane:illustration",
        available_at=NOW,
    )
    await session.commit()

    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            claimed = await claim_next_job(
                database_session,
                owner="illustration-worker",
                now=NOW,
                lease_seconds=60,
                include_job_types={"report_illustration"},
            )

    assert claimed.id == illustration.id


async def test_worker_lane_can_exclude_job_types(session):
    primary = await enqueue_job(
        session,
        job_type="report_pipeline",
        dedupe_key="lane:primary-exclude",
        available_at=NOW,
    )
    await enqueue_job(
        session,
        job_type="report_illustration",
        dedupe_key="lane:illustration-exclude",
        available_at=NOW,
    )
    await session.commit()

    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            claimed = await claim_next_job(
                database_session,
                owner="primary-worker",
                now=NOW,
                lease_seconds=60,
                exclude_job_types={"report_illustration"},
            )

    assert claimed.id == primary.id


async def test_worker_lane_rejects_include_and_exclude_together(session):
    with pytest.raises(ValueError, match="include_job_types"):
        await claim_next_job(
            session,
            owner="invalid-worker",
            now=NOW,
            lease_seconds=60,
            include_job_types={"report_illustration"},
            exclude_job_types={"report_pipeline"},
        )


async def test_only_lease_owner_can_complete_job(session):
    job_id = await _seed_job(dedupe_key="probe:complete")
    await _claim("worker-a")

    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            assert not await complete_job(
                database_session,
                job_id=job_id,
                owner="worker-b",
                now=NOW + timedelta(seconds=2),
            )
            assert await complete_job(
                database_session,
                job_id=job_id,
                owner="worker-a",
                now=NOW + timedelta(seconds=2),
            )

        completed = await database_session.get(WorkflowJob, job_id)
        assert completed.status == "succeeded"
        assert completed.lease_owner is None


async def test_only_lease_owner_can_renew_job(session):
    job_id = await _seed_job(dedupe_key="probe:renew")
    await _claim("worker-a")

    renewed_until = NOW + timedelta(seconds=120)
    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            assert not await renew_lease(
                database_session,
                job_id=job_id,
                owner="worker-b",
                now=NOW + timedelta(seconds=60),
                lease_seconds=60,
            )
            assert await renew_lease(
                database_session,
                job_id=job_id,
                owner="worker-a",
                now=NOW + timedelta(seconds=60),
                lease_seconds=60,
            )

        renewed = await database_session.get(WorkflowJob, job_id)
        assert renewed.lease_expires_at == renewed_until


async def test_retryable_failure_requeues_then_exhausts(session):
    job_id = await _seed_job(
        dedupe_key="probe:retry",
        max_attempts=2,
    )
    await _claim("worker-a")

    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            assert await fail_job(
                database_session,
                job_id=job_id,
                owner="worker-a",
                now=NOW,
                error_code="temporary",
                error_message="retry",
                retryable=True,
                jitter_seconds=0,
            )
        queued = await database_session.get(WorkflowJob, job_id)
        assert queued.status == "queued"
        retry_at = queued.available_at

    await _claim("worker-b", now=retry_at)
    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            assert await fail_job(
                database_session,
                job_id=job_id,
                owner="worker-b",
                now=retry_at,
                error_code="temporary",
                error_message="exhausted",
                retryable=True,
                jitter_seconds=0,
            )
        failed = await database_session.get(WorkflowJob, job_id)
        assert failed.status == "failed"
        assert failed.completed_at == retry_at
