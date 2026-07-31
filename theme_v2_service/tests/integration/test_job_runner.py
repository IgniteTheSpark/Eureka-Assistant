from datetime import datetime

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.jobs.queue import enqueue_job
from app.jobs.registry import JobHandlerRegistry
from app.jobs.runner import run_worker_once


NOW = datetime(2026, 7, 31, 9, 0, 0)


async def _seed_job(dedupe_key: str, job_type: str = "probe") -> str:
    async with AsyncSessionFactory() as session:
        async with session.begin():
            job = await enqueue_job(
                session,
                job_type=job_type,
                dedupe_key=dedupe_key,
                available_at=NOW,
            )
            return job.id


async def test_worker_commits_claim_before_running_handler(session):
    job_id = await _seed_job("runner:success")
    registry = JobHandlerRegistry()
    observed = []

    async def handler(job):
        async with AsyncSessionFactory() as database_session:
            persisted = await database_session.get(WorkflowJob, job.id)
            observed.append((persisted.status, persisted.lease_owner))

    registry.register("probe", handler)

    assert await run_worker_once(
        registry,
        owner="worker-a",
        now=NOW,
        lease_seconds=60,
    )

    async with AsyncSessionFactory() as database_session:
        completed = await database_session.get(WorkflowJob, job_id)
        assert completed.status == "succeeded"
    assert observed == [("running", "worker-a")]


async def test_worker_requeues_sanitized_handler_failure(session):
    job_id = await _seed_job("runner:failure")
    registry = JobHandlerRegistry()

    async def handler(job):
        raise RuntimeError("private asset body")

    registry.register("probe", handler)

    assert await run_worker_once(
        registry,
        owner="worker-a",
        now=NOW,
        lease_seconds=60,
    )

    async with AsyncSessionFactory() as database_session:
        failed = await database_session.get(WorkflowJob, job_id)
        assert failed.status == "queued"
        assert failed.error_code == "handler_error"
        assert failed.error_message == "RuntimeError"


async def test_worker_permanently_fails_unknown_job_type(session):
    job_id = await _seed_job("runner:unknown", job_type="unknown")

    assert await run_worker_once(
        JobHandlerRegistry(),
        owner="worker-a",
        now=NOW,
        lease_seconds=60,
    )

    async with AsyncSessionFactory() as database_session:
        failed = await database_session.get(WorkflowJob, job_id)
        assert failed.status == "failed"
        assert failed.error_code == "unknown_job_type"
