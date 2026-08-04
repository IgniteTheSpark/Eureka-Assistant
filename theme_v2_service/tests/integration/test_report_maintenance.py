from datetime import datetime, timedelta

from sqlalchemy import select

from app.db.models import WorkflowJob
from app.domains.notifications.models import Notification
from app.domains.reports.maintenance import (
    repair_report_presentations,
    run_report_maintenance,
)
from app.domains.reports.models import File, Report, ReportGenerationRun, ReportShare


NOW = datetime(2026, 7, 31, 10, 0, 0)


def _run(state: str, *, age: timedelta, job_id: str | None = None):
    run = ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state=state,
        active_stage=("intake" if state == "planning" else "content_generation"),
        launch_context={},
        intent="Summary",
        answers={},
        evidence_scope={},
        pending_decision=(
            {"type": "plan_selection", "recommended_option_id": "option-1"}
            if state == "awaiting_selection"
            else None
        ),
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
        planner_job_id=job_id if state == "planning" else None,
        generation_job_id=job_id if state == "generating" else None,
        report_id="report-complete" if state == "completed" else None,
        completed_at=NOW - age if state == "completed" else None,
        created_at=NOW - age,
        updated_at=NOW - age,
    )
    return run


async def test_maintenance_expires_only_stale_selection_and_fails_work_timeouts(
    session,
):
    planner_job = WorkflowJob(
        job_type="report_planner",
        status="running",
        available_at=NOW - timedelta(hours=2),
        lease_owner="dead-worker",
        lease_expires_at=NOW + timedelta(hours=1),
    )
    pipeline_job = WorkflowJob(
        job_type="report_pipeline",
        status="queued",
        available_at=NOW - timedelta(hours=2),
    )
    session.add_all([planner_job, pipeline_job])
    await session.flush()
    awaiting = _run("awaiting_selection", age=timedelta(days=8))
    planning = _run("planning", age=timedelta(hours=2), job_id=planner_job.id)
    generating = _run("generating", age=timedelta(hours=2), job_id=pipeline_job.id)
    completed = _run("completed", age=timedelta(days=30))
    fresh = _run("awaiting_selection", age=timedelta(days=1))
    session.add_all([awaiting, planning, generating, completed, fresh])
    await session.commit()

    first = await run_report_maintenance(
        session,
        now=NOW,
        planning_timeout=timedelta(hours=1),
        generation_timeout=timedelta(hours=1),
    )
    await session.commit()
    second = await run_report_maintenance(
        session,
        now=NOW,
        planning_timeout=timedelta(hours=1),
        generation_timeout=timedelta(hours=1),
    )
    await session.commit()

    assert first.expired_runs == 1
    assert first.failed_runs == 2
    assert second.expired_runs == 0
    assert second.failed_runs == 0
    assert awaiting.state == "expired"
    assert planning.state == "failed"
    assert planning.retry_from == "planning"
    assert generating.state == "failed"
    assert generating.retry_from == "content_generation"
    assert completed.state == "completed"
    assert completed.report_id == "report-complete"
    assert fresh.state == "awaiting_selection"
    assert planner_job.status == "failed"
    assert planner_job.lease_owner is None
    assert pipeline_job.status == "failed"
    failures = list(
        await session.scalars(
            select(Notification).where(Notification.type == "report_failed")
        )
    )
    assert len(failures) == 2


async def test_maintenance_marks_expired_shares_idempotently(session):
    run = _run("completed", age=timedelta(days=31))
    session.add(run)
    await session.flush()
    report = Report(
        id="report-1",
        user_id="user-1",
        generation_run_id=run.id,
        title="Report",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        content_md="# Report",
        spec_json={},
        share_card_spec={},
        tokens_used=0,
        gen_ms=0,
        created_at=NOW - timedelta(days=31),
    )
    session.add(report)
    await session.flush()
    share = ReportShare(
        report_id="report-1",
        user_id="user-1",
        token_hash="a" * 64,
        status="active",
        expires_at=NOW - timedelta(seconds=1),
        snapshot_content_md="# Snapshot",
        snapshot_spec_json={},
        media_map_json={},
        created_at=NOW - timedelta(days=31),
    )
    session.add(share)
    await session.commit()

    first = await run_report_maintenance(session, now=NOW)
    await session.commit()
    second = await run_report_maintenance(session, now=NOW)

    assert first.expired_shares == 1
    assert second.expired_shares == 0
    assert share.status == "expired"


async def test_report_presentation_repair_is_bounded_safe_and_idempotent(session):
    source = {
        "title": "训练方法",
        "url": "https://example.com/training",
        "snippet": "可执行的训练建议",
        "accessed_at": "2026-07-31T09:00:00Z",
    }
    run = _run("completed", age=timedelta(days=1))
    run.resolved_asset_ids = ["asset-allowed"]
    session.add(run)
    await session.flush()
    illustration = File(
        user_id=run.user_id,
        purpose="report_illustration",
        mime_type="image/png",
        size_bytes=4,
        sha256="a" * 64,
        storage_key="reports/user-1/illustration.png",
    )
    session.add(illustration)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_pipeline",
        status="succeeded",
        available_at=NOW - timedelta(days=1),
        checkpoint_json={
            "completed_stages": [
                "web_search",
                "content_generation",
                "chart_validation",
                "illustration",
            ],
            "stage_results": {
                "web_search": {"sources": [source]},
                "content_generation": {},
                "chart_validation": {
                    "svgs": {
                        "pace": (
                            '<svg xmlns="http://www.w3.org/2000/svg" '
                            'data-recovered-chart="pace"></svg>'
                        )
                    }
                },
                "illustration": {"file_id": illustration.id},
            },
        },
    )
    session.add(job)
    await session.flush()
    run.generation_job_id = job.id
    legacy = Report(
        id="report-legacy",
        user_id=run.user_id,
        generation_run_id=run.id,
        title="训练复盘",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        content_md=(
            "# 训练复盘\n\n"
            "训练节奏稳定。[evidence:asset-allowed]\n\n"
            "可继续增加间歇训练。"
            "[source:https://example.com/training]\n\n"
            "[[chart:pace]]\n\n"
            ":::actions\n- 准备下次训练计划\n:::"
        ),
        html="<html>legacy [evidence:asset-allowed]</html>",
        spec_json={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "source_asset_ids": ["asset-allowed"],
            "external_sources": [source],
            "web_policy": "optional",
            "generated_file_ids": [illustration.id],
            "surface": "report",
            "palette": "calm",
            "seed": 7,
            "presentation_version": "report_html_v1",
        },
        share_card_spec={"illustration_file_id": illustration.id},
        tokens_used=0,
        gen_ms=0,
        created_at=NOW - timedelta(days=1),
    )
    session.add(legacy)
    await session.flush()
    run.report_id = legacy.id

    unsafe_run = _run("completed", age=timedelta(days=1))
    unsafe_run.resolved_asset_ids = ["asset-allowed"]
    session.add(unsafe_run)
    await session.flush()
    unsafe = Report(
        id="report-unsafe",
        user_id=unsafe_run.user_id,
        generation_run_id=unsafe_run.id,
        title="Unsafe",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="briefing_research",
        content_md="Unknown [evidence:asset-not-allowed]",
        html="<html>unsafe</html>",
        spec_json={
            "source_asset_ids": ["asset-allowed"],
            "external_sources": [],
            "seed": 0,
            "presentation_version": "report_html_v1",
        },
        share_card_spec={},
        tokens_used=0,
        gen_ms=0,
        created_at=NOW - timedelta(days=1),
    )
    session.add(unsafe)
    await session.commit()

    dry_run = await repair_report_presentations(session, dry_run=True)
    await session.refresh(legacy)
    assert dry_run.eligible == 2
    assert dry_run.repaired == 1
    assert dry_run.skipped_unsafe == 1
    assert legacy.spec_json["presentation_version"] == "report_html_v1"
    assert "[evidence:" in legacy.content_md

    applied = await repair_report_presentations(session, dry_run=False)
    await session.commit()
    await session.refresh(legacy)
    assert applied.eligible == 2
    assert applied.repaired == 1
    assert applied.skipped_unsafe == 1
    assert "[evidence:" not in legacy.content_md
    assert "[source:" not in legacy.content_md
    assert ":::actions" not in legacy.content_md
    assert "[evidence:" not in legacy.html
    assert "[source:" not in legacy.html
    assert legacy.spec_json["presentation_version"] == "report_html_v2"
    assert legacy.spec_json["surface"] == "surface-note"
    assert legacy.spec_json["palette"] == "pal-warm"
    assert legacy.spec_json["suggested_actions"][0]["title"] == "准备下次训练计划"
    assert legacy.spec_json["citations"]
    assert legacy.spec_json["external_sources"] == [source]
    assert 'data-recovered-chart="pace"' in legacy.html
    assert f'src="/api/files/{illustration.id}"' in legacy.html

    repeated = await repair_report_presentations(session, dry_run=False)
    assert repeated.repaired == 0
    assert repeated.skipped_unsafe == 1
