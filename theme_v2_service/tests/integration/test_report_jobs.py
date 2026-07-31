from datetime import datetime

from sqlalchemy import func, select

from app.db.models import WorkflowJob
from app.domains.reports.models import ReportGenerationRun
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
