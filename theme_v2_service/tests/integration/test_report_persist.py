from pathlib import Path
from datetime import datetime

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select

from app.db.models import Asset, Event, UserSkill, WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.reports.models import Report, ReportGenerationRun
from app.domains.reports.pipeline import report_pipeline_handler
from app.domains.reports.providers import (
    GeneratedImage,
    GeneratedSuggestedAction,
    GeneratorResult,
)
from app.domains.reports.service import (
    CompletedReportData,
    PersistRejected,
    persist_completed_report,
    record_report_failure,
)
from app.domains.reports.storage import LocalStorage
from app.domains.reports.schemas import EvidenceReference
from app.domains.reports.templates import TemplateRegistry
from tests.fakes.report_providers import (
    FakeGeneratorProvider,
    FakeIllustrationProvider,
    FakeWebSearchProvider,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


def _run(*, state: str = "generating") -> ReportGenerationRun:
    return ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state=state,
        active_stage="persist",
        launch_context={},
        intent="Summary",
        answers={},
        evidence_scope={},
        plan_options=[],
        execution_plan={},
        template_id="general_period_review",
        template_version="1.0.0",
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )


async def _current(session, *, state="generating", owner="worker-1"):
    run = _run(state=state)
    session.add(run)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_pipeline",
        status="running",
        lease_owner=owner,
    )
    session.add(job)
    await session.flush()
    run.generation_job_id = job.id
    await session.flush()
    return run, job


def _data() -> CompletedReportData:
    return CompletedReportData(
        title="Period report",
        content_md="# Report\n\nSafe body",
        html="<html><body>Safe body</body></html>",
        spec_json={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "source_asset_ids": [],
            "unavailable_asset_ids": [],
            "field_bindings": {},
            "time_range": None,
            "external_sources": [],
            "web_policy": "none",
            "generated_file_ids": [],
            "surface": "report",
            "palette": "calm",
            "seed": 7,
        },
        share_card_spec={
            "headline": "Period report",
            "summary": "Safe summary",
            "highlights": [],
            "time_range": "2026-07",
            "illustration_file_id": None,
        },
        tokens_used=30,
        gen_ms=120,
    )


def test_completed_report_data_rejects_internal_citation_markers():
    values = _data().model_dump()
    values["content_md"] = "Visible [evidence:asset-private]"

    with pytest.raises(ValidationError, match="citation marker"):
        CompletedReportData.model_validate(values)


async def test_persist_retry_creates_exactly_one_report_and_notification(session):
    run, job = await _current(session)

    first = await persist_completed_report(
        session,
        run_id=run.id,
        job_id=job.id,
        lease_owner="worker-1",
        data=_data(),
        now=NOW,
    )
    await session.commit()
    repeated = await persist_completed_report(
        session,
        run_id=run.id,
        job_id=job.id,
        lease_owner="worker-1",
        data=_data(),
        now=NOW,
    )
    await session.commit()

    assert repeated.id == first.id
    assert await session.scalar(select(func.count()).select_from(Report)) == 1
    assert await session.scalar(select(func.count()).select_from(Notification)) == 1
    assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 1
    await session.refresh(run)
    await session.refresh(job)
    assert run.state == "completed"
    assert run.report_id == first.id
    assert job.status == "succeeded"
    assert job.lease_owner is None


async def test_pending_illustration_publishes_a_readable_report(session):
    run, job = await _current(session)

    report = await persist_completed_report(
        session,
        run_id=run.id,
        job_id=job.id,
        lease_owner="worker-1",
        data=_data().model_copy(
            update={
                "illustration_status": "pending",
                "illustration_job_id": "illustration-job-1",
            }
        ),
        now=NOW,
    )
    await session.commit()

    await session.refresh(run)
    assert run.state == "illustration_pending"
    assert run.report_id == report.id
    assert report.illustration_status == "pending"
    assert report.illustration_job_id == "illustration-job-1"
    assert report.revision == 1
    assert await session.scalar(select(func.count()).select_from(Notification)) == 1


@pytest.mark.parametrize(
    ("state", "expected_owner"),
    [("cancelled", "worker-1"), ("generating", "worker-2")],
)
async def test_cancelled_run_or_stale_lease_cannot_persist(
    session,
    state,
    expected_owner,
):
    run, job = await _current(session, state=state, owner="worker-1")

    with pytest.raises(PersistRejected):
        await persist_completed_report(
            session,
            run_id=run.id,
            job_id=job.id,
            lease_owner=expected_owner,
            data=_data(),
            now=NOW,
        )
    assert await session.scalar(select(func.count()).select_from(Report)) == 0


async def test_fatal_failure_records_retry_metadata_and_deduplicates_notice(session):
    run, job = await _current(session)

    assert await record_report_failure(
        session,
        run_id=run.id,
        job_id=job.id,
        lease_owner="worker-1",
        failure_stage="content_generation",
        error_code="invalid_generator_output",
        error_message="The provider response was invalid",
        retry_from="content_generation",
        now=NOW,
    )
    await session.commit()
    assert not await record_report_failure(
        session,
        run_id=run.id,
        job_id=job.id,
        lease_owner="worker-1",
        failure_stage="content_generation",
        error_code="invalid_generator_output",
        error_message="The provider response was invalid",
        retry_from="content_generation",
        now=NOW,
    )
    await session.commit()

    await session.refresh(run)
    await session.refresh(job)
    assert run.state == "failed"
    assert run.retry_from == "content_generation"
    assert job.status == "failed"
    assert await session.scalar(select(func.count()).select_from(Notification)) == 1
    assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 1


async def test_real_pipeline_stages_close_workflow_with_fake_providers(session, tmp_path):
    skill = UserSkill(
        user_id="user-1",
        machine_name="notes",
        display_name="Notes",
        description=None,
        domain="notes",
        schema_json={"x-data-capabilities": ["free_text"]},
    )
    session.add(skill)
    await session.flush()
    asset = Asset(
        user_id="user-1",
        user_skill_id=skill.id,
        payload_json={"value": 12},
    )
    session.add(asset)
    await session.flush()
    run = ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state="generating",
        active_stage="load_evidence",
        launch_context={},
        intent="Summary",
        answers={},
        evidence_scope={},
        plan_options=[],
        execution_plan={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "report_goal": "Summary",
            "resolved_asset_ids": [asset.id],
            "field_bindings": {"record.value": "payload.value"},
            "time_range": None,
            "web_policy": "none",
            "illustration_policy": "none",
            "render_policy": "report_html_v1",
        },
        template_id="general_period_review",
        template_version="1.0.0",
        resolved_asset_ids=[asset.id],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_pipeline",
        status="running",
        lease_owner="worker-1",
    )
    session.add(job)
    await session.flush()
    run.generation_job_id = job.id
    await session.commit()
    generator = FakeGeneratorProvider(
        GeneratorResult(
            content_md=f"记录值为 12。[evidence:{asset.id}]",
            chart_directives=[],
            illustration_prompt=None,
            suggested_actions=[
                GeneratedSuggestedAction(title="复盘下一次训练")
            ],
            share_card_spec={
                "headline": "Period report",
                "summary": "A safe summary",
                "highlights": [],
                "time_range": "2026-07",
            },
        )
    )
    web = FakeWebSearchProvider()
    illustration = FakeIllustrationProvider(
        GeneratedImage(data=b"unused", mime_type="image/png")
    )
    handler = report_pipeline_handler(
        generator=generator,
        web_search=web,
        illustration=illustration,
        registry=TemplateRegistry.load(
            Path(__file__).parents[2] / "report-templates"
        ),
        storage=LocalStorage(tmp_path / "media"),
        session_factory=AsyncSessionFactory,
    )

    await handler(job)

    await session.refresh(run)
    await session.refresh(job)
    report = await session.scalar(
        select(Report).where(Report.generation_run_id == run.id)
    )
    assert run.state == "completed"
    assert job.status == "succeeded"
    assert report is not None
    assert generator.calls == 1
    assert web.calls == 0
    assert illustration.calls == 0
    assert "Period report" in report.html
    assert "[evidence:" not in report.content_md
    assert "[evidence:" not in report.html
    assert report.spec_json["citations"]
    assert report.spec_json["suggested_actions"][0]["title"] == "复盘下一次训练"
    expected_surface = (
        "surface-editorial" if report.spec_json["seed"] % 2 == 0 else "surface-note"
    )
    assert report.spec_json["surface"] == expected_surface
    assert report.spec_json["palette"] in {"pal-ink", "pal-warm"}
    assert report.spec_json["presentation_version"] == "report_html_v2"


async def test_event_only_report_persists_without_null_source_asset_id(
    session,
    tmp_path,
):
    event = Event(
        user_id="user-1",
        title="球队建设讨论",
        description="比较不同球队的建设方式",
        location="会议室",
        start_at=datetime(2026, 8, 12, 1, 0),
        end_at=datetime(2026, 8, 12, 2, 0),
        all_day=False,
    )
    session.add(event)
    await session.flush()
    plan = {
        "template_id": "pre_event_briefing",
        "template_version": "1.0.0",
        "base_family": "briefing_research",
        "report_goal": "准备会议",
        "resolved_asset_ids": [],
        "resolved_references": [
            EvidenceReference(kind="event", id=event.id).model_dump()
        ],
        "field_bindings": {},
        "time_range": None,
        "web_policy": "optional",
        "illustration_policy": "none",
        "render_policy": "report_html_v1",
    }
    run = ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state="generating",
        active_stage="load_evidence",
        launch_context={"event_id": event.id},
        intent="会前调研",
        answers={},
        evidence_scope={},
        plan_options=[],
        execution_plan=plan,
        template_id="pre_event_briefing",
        template_version="1.0.0",
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_pipeline",
        status="running",
        lease_owner="worker-1",
    )
    session.add(job)
    await session.flush()
    run.generation_job_id = job.id
    await session.commit()
    generator = FakeGeneratorProvider(
        GeneratorResult(
            content_md=f"会议时间为 09:00。[evidence:{event.id}]",
            chart_directives=[],
            illustration_prompt=None,
            suggested_actions=[],
            share_card_spec={
                "headline": "会前调研",
                "summary": "会议信息已整理",
                "highlights": ["09:00 开始"],
                "time_range": "2026-08-12",
            },
        )
    )
    handler = report_pipeline_handler(
        generator=generator,
        web_search=FakeWebSearchProvider(),
        illustration=FakeIllustrationProvider(
            GeneratedImage(data=b"unused", mime_type="image/png")
        ),
        registry=TemplateRegistry.load(
            Path(__file__).parents[2] / "report-templates"
        ),
        storage=LocalStorage(tmp_path / "media"),
        session_factory=AsyncSessionFactory,
    )

    await handler(job)

    await session.refresh(run)
    report = await session.scalar(
        select(Report).where(Report.generation_run_id == run.id)
    )
    assert run.state == "completed"
    assert report is not None
    assert report.spec_json["source_asset_ids"] == []
