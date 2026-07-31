from datetime import datetime, timedelta

from sqlalchemy import select

from app.db.models import WorkflowJob
from app.domains.notifications.models import Notification
from app.domains.reports.maintenance import run_report_maintenance
from app.domains.reports.models import Report, ReportGenerationRun, ReportShare


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
