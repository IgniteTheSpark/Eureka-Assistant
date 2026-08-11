from datetime import datetime

import pytest
from sqlalchemy import func, select

from app.db.models import Asset, UserSkill, WorkflowJob
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.pipeline import (
    PipelineWriteRejected,
    database_pipeline_context,
)
from app.domains.reports.schemas import UserRunCreate
from app.domains.reports.scope_resolution import (
    ScopeResolutionResult,
    execute_scope_resolution_job,
)
from app.domains.reports.service import (
    create_user_run,
    generation_write_guard,
    prepare_scope_plan,
    planner_write_guard,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def test_user_run_scope_confirmation_shares_outer_transaction(session):
    skill = UserSkill(
        id="skill-1",
        user_id="user-1",
        machine_name="notes",
        display_name="Notes",
        schema_json={"type": "object", "properties": {"note": {"type": "string"}}},
    )
    session.add(skill)
    await session.flush()
    asset = Asset(
        id="asset-1",
        user_id="user-1",
        user_skill_id=skill.id,
        payload_json={"note": "test"},
    )
    session.add(asset)
    await session.flush()
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

    assert run.state == "awaiting_selection"
    assert run.origin == "user_initiated"
    assert run.evidence_scope == {
        "time_range": None,
        "skill_ids": ["skill-1"],
        "asset_ids": ["asset-1"],
        "references": [{"kind": "asset", "id": "asset-1"}],
        "counts_by_skill": {},
    }
    assert run.planner_job_id is None
    assert run.pending_decision["type"] == "scope_confirmation"

    await session.rollback()
    assert await session.scalar(
        select(func.count()).select_from(ReportGenerationRun)
    ) == 0
    assert await session.scalar(
        select(func.count()).select_from(WorkflowJob)
    ) == 0


async def test_only_current_job_can_write_back(session):
    skill = UserSkill(
        id="skill-1",
        user_id="user-1",
        machine_name="notes",
        display_name="Notes",
        schema_json={"type": "object", "properties": {"note": {"type": "string"}}},
    )
    session.add(skill)
    await session.flush()
    asset = Asset(
        id="asset-1",
        user_id="user-1",
        user_skill_id=skill.id,
        payload_json={"note": "test"},
    )
    session.add(asset)
    await session.flush()
    run = await create_user_run(
        session,
        user_id="user-1",
        command=UserRunCreate(
            origin="user_initiated",
            intent="Summarize",
            skill_ids=[skill.id],
            asset_ids=[asset.id],
        ),
    )
    run, planner_job = await prepare_scope_plan(
        session,
        user_id="user-1",
        run_id=run.id,
        expected_revision=0,
    )
    current_planner = planner_job.id

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


class _ScopeResolver:
    async def resolve(self, request):
        assert "Kevin" in request.additional_focus
        return ScopeResolutionResult.model_validate(
            {
                "public_research_scope": {
                    "entities": [
                        {
                            "id": "kevin",
                            "kind": "person",
                            "name": "Kevin",
                            "qualifier": "Eureka CEO",
                        }
                    ],
                    "questions": ["公开职业背景"],
                    "freshness": "current",
                }
            }
        )


async def test_scope_resolution_writes_only_current_plan_revision(session):
    run = ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state="planning",
        active_stage="scope_resolution",
        launch_context={},
        intent="Kevin briefing",
        answers={},
        evidence_scope={},
        pending_decision={
            "type": "plan_selection",
            "recommended_option_id": "option-1",
        },
        plan_options=[],
        plan_draft={
            "selected_option_id": "option-1",
            "additional_focus": "补充 Kevin（Eureka CEO）的公开职业背景",
            "evidence_scope": {},
            "public_research_scope": {},
        },
        plan_revision=4,
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    current = WorkflowJob(
        run_id=run.id,
        job_type="report_scope_resolution",
        status="running",
        checkpoint_json={"plan_revision": 4},
    )
    session.add(current)
    await session.flush()
    run.scope_resolution_job_id = current.id
    await session.commit()

    assert await execute_scope_resolution_job(current, provider=_ScopeResolver())

    await session.refresh(run)
    assert run.state == "awaiting_selection"
    assert run.plan_revision == 5
    assert run.scope_resolution_job_id is None
    assert run.plan_draft["public_research_scope"]["entities"][0]["qualifier"] == (
        "Eureka CEO"
    )

    stale = WorkflowJob(
        run_id=run.id,
        job_type="report_scope_resolution",
        status="running",
        checkpoint_json={"plan_revision": 4},
    )
    session.add(stale)
    await session.commit()
    assert await execute_scope_resolution_job(stale, provider=_ScopeResolver()) is False
