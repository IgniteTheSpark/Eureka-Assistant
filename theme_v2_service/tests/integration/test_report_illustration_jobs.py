from datetime import datetime

import pytest

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.illustration_jobs import (
    enqueue_report_illustration,
    execute_report_illustration_job,
    mark_illustration_failed,
)
from app.domains.reports.models import File, Report, ReportGenerationRun, ReportShare
from app.domains.reports.providers import GeneratedImage
from app.domains.reports.pipeline import wait_for_illustration_result
from app.domains.reports.rendering import render_report_presentation
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


async def test_parent_observes_a_stored_image_inside_its_budget(session):
    _, child = await _seed_child(session)
    child.checkpoint_json = {
        **child.checkpoint_json,
        "phase": "stored",
        "file_id": "file-1",
    }
    await session.commit()

    result = await wait_for_illustration_result(
        job_id=child.id,
        timeout_seconds=0.01,
        poll_seconds=0.001,
    )

    assert result == {
        "status": "ready",
        "job_id": child.id,
        "file_id": "file-1",
    }


async def test_parent_timeout_does_not_cancel_the_child(session):
    _, child = await _seed_child(session)
    child.status = "queued"
    child.lease_owner = None
    await session.commit()

    result = await wait_for_illustration_result(
        job_id=child.id,
        timeout_seconds=0.001,
        poll_seconds=0.001,
    )

    await session.refresh(child)
    assert result == {"status": "pending", "job_id": child.id}
    assert child.status == "queued"


async def test_attach_patches_only_trusted_slot_and_increments_revision(session):
    run, child = await _seed_child(session)
    file = File(
        user_id=run.user_id,
        purpose="report_illustration",
        mime_type="image/png",
        size_bytes=11,
        sha256="0" * 64,
        storage_key="reports/test/image.png",
    )
    session.add(file)
    await session.flush()
    pending_html = render_report_presentation(
        title="Football systems",
        content_md="Readable report body",
        chart_svgs={},
        media_urls={},
        illustration_status="pending",
    ).html
    report = Report(
        user_id=run.user_id,
        generation_run_id=run.id,
        title="Football systems",
        template_id="pre_event_briefing",
        template_version="1.0.0",
        base_family="briefing_research",
        content_md="Readable report body",
        html=pending_html,
        spec_json={"generated_file_ids": []},
        share_card_spec={"headline": "Football systems"},
        tokens_used=1,
        gen_ms=1,
        illustration_status="pending",
        illustration_job_id=child.id,
        revision=1,
    )
    session.add(report)
    await session.flush()
    share = ReportShare(
        report_id=report.id,
        user_id=run.user_id,
        token_hash="share-token",
        status="active",
        snapshot_content_md=report.content_md,
        snapshot_spec_json={},
        snapshot_html=pending_html,
        media_map_json={},
    )
    session.add(share)
    run.state = "illustration_pending"
    run.report_id = report.id
    run.completed_at = NOW
    child.checkpoint_json = {
        **child.checkpoint_json,
        "phase": "stored",
        "file_id": file.id,
    }
    await session.commit()
    provider = _Provider()

    await execute_report_illustration_job(
        child,
        provider=provider,
        storage=_Storage(),
        now=NOW,
    )

    await session.refresh(report)
    await session.refresh(run)
    await session.refresh(share)
    assert provider.calls == 0
    assert report.illustration_status == "ready"
    assert report.revision == 2
    assert report.html.count('id="reka-report-illustration"') == 1
    assert f'/api/files/{file.id}' in report.html
    assert "Readable report body" in report.html
    assert report.spec_json["generated_file_ids"] == [file.id]
    assert report.share_card_spec["illustration_file_id"] == file.id
    assert run.state == "completed"
    assert share.snapshot_html == pending_html


async def test_terminal_failure_removes_placeholder_and_completes_run(session):
    run, child = await _seed_child(session)
    pending_html = render_report_presentation(
        title="Football systems",
        content_md="Readable body survives image failure",
        chart_svgs={},
        media_urls={},
        illustration_status="pending",
    ).html
    report = Report(
        user_id=run.user_id,
        generation_run_id=run.id,
        title="Football systems",
        template_id="pre_event_briefing",
        template_version="1.0.0",
        base_family="briefing_research",
        content_md="Readable body survives image failure",
        html=pending_html,
        spec_json={"generated_file_ids": []},
        share_card_spec={"headline": "Football systems"},
        tokens_used=1,
        gen_ms=1,
        illustration_status="pending",
        illustration_job_id=child.id,
        revision=1,
    )
    session.add(report)
    await session.flush()
    run.state = "illustration_pending"
    run.report_id = report.id
    run.completed_at = NOW
    await session.commit()

    assert await mark_illustration_failed(
        session,
        job=child,
        error_code="provider_timeout",
        now=NOW,
    )
    await session.commit()

    await session.refresh(report)
    await session.refresh(run)
    assert report.illustration_status == "failed"
    assert report.revision == 2
    assert 'id="reka-report-illustration"' not in report.html
    assert "Readable body survives image failure" in report.html
    assert run.state == "completed"
