from datetime import datetime

import pytest
from sqlalchemy import func, select

from app.db.models import WorkflowJob
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.pipeline import (
    PipelineWriteRejected,
    database_pipeline_context,
)
from app.domains.reports.schemas import UserRunCreate
from app.domains.reports.service import (
    create_user_run,
    generation_write_guard,
    planner_write_guard,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def test_user_run_and_planner_job_share_outer_transaction(session):
    run = await create_user_run(
        session,
        user_id="user-1",
        command=UserRunCreate(
            origin="user_initiated",
            intent="Summarize my notes",
            skill_ids=["skill-1"],
            asset_ids=["asset-1"],
        ),
    )

    job = await session.get(WorkflowJob, run.planner_job_id)
    assert run.state == "planning"
    assert run.origin == "user_initiated"
    assert run.evidence_scope == {
        "time_range": None,
        "skill_ids": ["skill-1"],
        "asset_ids": ["asset-1"],
        "counts_by_skill": {},
    }
    assert job.job_type == "report_planner"
    assert job.run_id == run.id

    await session.rollback()
    assert await session.scalar(
        select(func.count()).select_from(ReportGenerationRun)
    ) == 0
    assert await session.scalar(
        select(func.count()).select_from(WorkflowJob)
    ) == 0


async def test_only_current_job_can_write_back(session):
    run = await create_user_run(
        session,
        user_id="user-1",
        command=UserRunCreate(
            origin="user_initiated",
            intent="Summarize",
        ),
    )
    current_planner = run.planner_job_id

    assert await planner_write_guard(
        session,
        run_id=run.id,
        job_id=current_planner,
    ) is run
    assert await planner_write_guard(
        session,
        run_id=run.id,
        job_id="stale-planner",
    ) is None

    run.state = "generating"
    run.generation_job_id = "current-generation"
    assert await generation_write_guard(
        session,
        run_id=run.id,
        job_id="current-generation",
    ) is run
    assert await generation_write_guard(
        session,
        run_id=run.id,
        job_id="stale-generation",
    ) is None


async def test_database_pipeline_checkpoints_require_current_running_job(session):
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
            "resolved_asset_ids": [],
            "field_bindings": {},
            "time_range": None,
            "web_policy": "none",
            "illustration_policy": "none",
            "render_policy": "report_html_v1",
        },
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

    async def unused(_):
        return {}

    context = await database_pipeline_context(
        job,
        handlers={
            stage: unused
            for stage in (
                "load_evidence",
                "web_search",
                "content_generation",
                "chart_validation",
                "illustration",
                "html_render",
                "persist",
            )
        },
    )
    await context.save_checkpoint("load_evidence", {"loaded": 1})

    await session.refresh(run)
    await session.refresh(job)
    assert run.active_stage == "web_search"
    assert job.checkpoint_json["completed_stages"] == ["load_evidence"]

    job.lease_owner = "worker-2"
    await session.commit()
    with pytest.raises(PipelineWriteRejected):
        await context.save_checkpoint("web_search", {"sources": []})

    job.lease_owner = "worker-1"
    run.state = "cancelled"
    await session.commit()
    with pytest.raises(PipelineWriteRejected):
        await context.save_checkpoint("web_search", {"sources": []})
    await session.refresh(job)
    assert "web_search" not in job.checkpoint_json["stage_results"]
