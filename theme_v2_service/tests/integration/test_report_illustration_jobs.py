from datetime import datetime

import pytest

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.illustration_jobs import (
    enqueue_report_illustration,
    execute_report_illustration_job,
)
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.providers import GeneratedImage
from app.domains.reports.storage import StoredObject
from app.jobs.models import JobDeferred


NOW = datetime(2026, 8, 11, 10, 0, 0)


class _Provider:
    def __init__(self) -> None:
        self.calls = 0

    async def generate(self, prompt: str) -> GeneratedImage:
        self.calls += 1
        assert prompt == "abstract football systems"
        return GeneratedImage(data=b"image-bytes", mime_type="image/png")


class _Storage:
    async def put(self, key: str, content: bytes, mime_type: str) -> StoredObject:
        assert content == b"image-bytes"
        return StoredObject(
            key=key,
            size_bytes=len(content),
            mime_type=mime_type,
            sha256="0" * 64,
        )

    async def get(self, key: str) -> bytes:
        return b"image-bytes"


async def _seed_child(session) -> tuple[ReportGenerationRun, WorkflowJob]:
    run = ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state="generating",
        launch_context={},
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    child = await enqueue_report_illustration(
        session,
        run=run,
        parent_job_id="parent-1",
        prompt="abstract football systems",
        policy="optional",
    )
    child.status = "running"
    child.lease_owner = "illustration-worker"
    child.attempt = 1
    await session.commit()
    return run, child


async def test_illustration_job_persists_file_before_report_attach(session):
    _, child = await _seed_child(session)
    provider = _Provider()

    with pytest.raises(JobDeferred):
        await execute_report_illustration_job(
            child,
            provider=provider,
            storage=_Storage(),
            now=NOW,
        )

    async with AsyncSessionFactory() as database_session:
        stored = await database_session.get(WorkflowJob, child.id)
        assert stored.status == "queued"
        assert stored.checkpoint_json["phase"] == "stored"
        assert stored.checkpoint_json["file_id"]
    assert provider.calls == 1


async def test_retry_with_file_checkpoint_does_not_call_provider_again(session):
    _, child = await _seed_child(session)
    provider = _Provider()
    with pytest.raises(JobDeferred):
        await execute_report_illustration_job(
            child,
            provider=provider,
            storage=_Storage(),
            now=NOW,
        )

    async with AsyncSessionFactory() as database_session:
        async with database_session.begin():
            stored = await database_session.get(WorkflowJob, child.id)
            stored.status = "running"
            stored.lease_owner = "illustration-worker-2"
            stored.attempt = 2
        await database_session.refresh(stored)
        retry_job = stored

    with pytest.raises(JobDeferred):
        await execute_report_illustration_job(
            retry_job,
            provider=provider,
            storage=_Storage(),
            now=NOW,
        )

    assert provider.calls == 1
