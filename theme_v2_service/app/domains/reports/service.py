from copy import deepcopy
from datetime import datetime, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, ConfigDict, Field

from app.config import get_settings
from app.db.base import new_uuid, utc_now
from app.db.models import UserSkill, WorkflowJob
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.reports.models import Report, ReportGenerationRun
from app.domains.reports.schemas import (
    EvidenceScope,
    ReportSpec,
    ReportExecutionPlan,
    ReportPlanOption,
    RunDecisionRequest,
    TriggerRunCreate,
    UserRunCreate,
    ShareCardSpec,
)
from app.domains.reports.state_machine import (
    InvalidRunTransition,
    transition_run,
)
from app.domains.triggers.service import (
    ExecutionExpired,
    ExecutionNotFound,
    consume_execution,
    owned_execution_for_update,
)
from app.jobs.queue import enqueue_job
from app.jobs.registry import REPORT_PIPELINE_JOB_TYPE, REPORT_PLANNER_JOB_TYPE


ACTIVE_STATES = {"planning", "awaiting_selection", "generating", "failed"}


class RunNotFound(Exception):
    pass


class RunConflict(Exception):
    pass


class PersistRejected(Exception):
    pass


class CompletedReportData(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=255)
    content_md: str = Field(min_length=1)
    html: str | None = None
    spec_json: ReportSpec
    share_card_spec: ShareCardSpec
    tokens_used: int = Field(default=0, ge=0)
    gen_ms: int = Field(default=0, ge=0)


def _planner_key(run_id: str, reason: str) -> str:
    return f"planner:{run_id}:{reason}:{new_uuid()}"


async def _enqueue_planner(
    session: AsyncSession,
    run: ReportGenerationRun,
    *,
    reason: str,
) -> WorkflowJob:
    job = await enqueue_job(
        session,
        run_id=run.id,
        job_type=REPORT_PLANNER_JOB_TYPE,
        dedupe_key=_planner_key(run.id, reason),
        max_attempts=get_settings().report_provider_max_attempts,
    )
    run.planner_job_id = job.id
    run.active_stage = "intake"
    return job


async def create_user_run(
    session: AsyncSession,
    *,
    user_id: str,
    command: UserRunCreate,
) -> ReportGenerationRun:
    scope = command.to_evidence_scope()
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="planning",
        active_stage="intake",
        launch_context={},
        intent=command.intent,
        answers={},
        evidence_scope=scope.model_dump(mode="json", by_alias=True),
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    await _enqueue_planner(session, run, reason="initial")
    await session.flush()
    return run


async def create_trigger_run(
    session: AsyncSession,
    *,
    user_id: str,
    command: TriggerRunCreate,
) -> ReportGenerationRun:
    execution = await owned_execution_for_update(
        session,
        user_id=user_id,
        execution_id=command.trigger_execution_id,
    )
    if execution.status == "consumed" and execution.workflow_run_id is not None:
        existing = await session.scalar(
            select(ReportGenerationRun).where(
                ReportGenerationRun.id == execution.workflow_run_id,
                ReportGenerationRun.user_id == user_id,
            )
        )
        if existing is not None:
            return existing

    launch_context = deepcopy(execution.payload_json)
    scope = EvidenceScope(
        skill_ids=(
            [launch_context["primary_skill_id"]]
            if launch_context.get("primary_skill_id")
            else []
        ),
        asset_ids=list(launch_context.get("asset_ids", [])),
    )
    run = ReportGenerationRun(
        user_id=user_id,
        origin="trigger",
        trigger_execution_id=execution.id,
        state="planning",
        active_stage="intake",
        launch_context=launch_context,
        intent=None,
        answers={},
        evidence_scope=scope.model_dump(mode="json", by_alias=True),
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    await consume_execution(
        session,
        user_id=user_id,
        execution_id=execution.id,
        workflow_run_id=run.id,
        now=utc_now(),
    )
    await _enqueue_planner(session, run, reason="initial")
    await session.flush()
    return run


async def owned_run_for_update(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
) -> ReportGenerationRun:
    run = await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.user_id == user_id,
        )
        .with_for_update()
    )
    if run is None:
        raise RunNotFound()
    return run


async def get_owned_run(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
) -> ReportGenerationRun:
    run = await session.scalar(
        select(ReportGenerationRun).where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.user_id == user_id,
        )
    )
    if run is None:
        raise RunNotFound()
    return run


async def list_owned_runs(
    session: AsyncSession,
    *,
    user_id: str,
    active: bool,
) -> list[ReportGenerationRun]:
    query = select(ReportGenerationRun).where(
        ReportGenerationRun.user_id == user_id
    )
    if active:
        query = query.where(ReportGenerationRun.state.in_(ACTIVE_STATES))
    return list(
        await session.scalars(
            query.order_by(
                ReportGenerationRun.updated_at.desc(),
                ReportGenerationRun.id.desc(),
            )
        )
    )


async def submit_decision(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    command: RunDecisionRequest,
    now: datetime | None = None,
) -> ReportGenerationRun:
    run = await owned_run_for_update(
        session,
        user_id=user_id,
        run_id=run_id,
    )
    if run.state != "awaiting_selection":
        raise RunConflict("run is not awaiting a decision")
    run.answers = {**run.answers, **command.answers}
    if command.evidence_scope is not None:
        run.evidence_scope = command.evidence_scope.model_dump(
            mode="json",
            by_alias=True,
        )
    run.pending_decision = None
    run.plan_options = []
    run.selected_option_id = None
    run.execution_plan = None
    await _enqueue_planner(session, run, reason="decision")
    transition_run(run, "planning", now=now or utc_now())
    await session.flush()
    return run


async def generate_run(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    selected_option_id: str,
    now: datetime | None = None,
) -> tuple[ReportGenerationRun, WorkflowJob]:
    run = await owned_run_for_update(
        session,
        user_id=user_id,
        run_id=run_id,
    )
    if run.state == "generating" and run.generation_job_id is not None:
        current = await session.get(WorkflowJob, run.generation_job_id)
        if current is not None:
            return run, current
    if run.state != "awaiting_selection":
        raise RunConflict("run is not awaiting plan selection")

    raw_option = next(
        (
            option
            for option in run.plan_options
            if option.get("id") == selected_option_id
        ),
        None,
    )
    if raw_option is None:
        raise RunConflict("selected option does not exist")
    option = ReportPlanOption.model_validate(raw_option)
    execution_plan = ReportExecutionPlan(
        template_id=option.template_id,
        template_version=option.template_version,
        base_family=option.base_family,
        report_goal=option.report_goal,
        resolved_asset_ids=option.evidence_scope.asset_ids,
        field_bindings=option.field_bindings,
        time_range=option.evidence_scope.time_range,
        web_policy=option.web_search.policy,
        illustration_policy=option.illustration.policy,
        render_policy=option.render_policy,
    )
    job = await enqueue_job(
        session,
        run_id=run.id,
        job_type=REPORT_PIPELINE_JOB_TYPE,
        dedupe_key=f"pipeline:{run.id}:{selected_option_id}",
        max_attempts=get_settings().report_provider_max_attempts,
    )
    run.selected_option_id = selected_option_id
    run.execution_plan = execution_plan.model_dump(mode="json", by_alias=True)
    run.template_id = execution_plan.template_id
    run.template_version = execution_plan.template_version
    run.resolved_asset_ids = execution_plan.resolved_asset_ids
    run.generation_job_id = job.id
    run.active_stage = "load_evidence"
    transition_run(run, "generating", now=now or utc_now())
    await session.flush()
    return run, job


async def retry_run(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    now: datetime | None = None,
) -> tuple[ReportGenerationRun, WorkflowJob]:
    run = await owned_run_for_update(
        session,
        user_id=user_id,
        run_id=run_id,
    )
    if run.state != "failed" or run.retry_from is None:
        raise RunConflict("run is not retryable")
    retry_token = new_uuid()
    if run.retry_from == "planning":
        job = await _enqueue_planner(session, run, reason=f"retry:{retry_token}")
        transition_run(run, "planning", now=now or utc_now())
    else:
        job = await enqueue_job(
            session,
            run_id=run.id,
            job_type=REPORT_PIPELINE_JOB_TYPE,
            dedupe_key=f"pipeline:{run.id}:retry:{retry_token}",
            max_attempts=get_settings().report_provider_max_attempts,
        )
        run.generation_job_id = job.id
        run.active_stage = run.retry_from
        transition_run(run, "generating", now=now or utc_now())
    run.failure_stage = None
    run.error_code = None
    run.error_message = None
    run.retry_from = None
    await session.flush()
    return run, job


async def cancel_run(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    now: datetime | None = None,
) -> ReportGenerationRun:
    run = await owned_run_for_update(
        session,
        user_id=user_id,
        run_id=run_id,
    )
    if run.state == "cancelled":
        return run
    try:
        transition_run(run, "cancelled", now=now or utc_now())
    except InvalidRunTransition as exc:
        raise RunConflict(str(exc)) from exc
    job_ids = [value for value in (run.planner_job_id, run.generation_job_id) if value]
    if job_ids:
        await session.execute(
            update(WorkflowJob)
            .where(
                WorkflowJob.id.in_(job_ids),
                WorkflowJob.status.in_(("queued", "running")),
            )
            .values(status="cancelled", completed_at=now or utc_now())
        )
    await session.flush()
    return run


async def planner_write_guard(
    session: AsyncSession,
    *,
    run_id: str,
    job_id: str,
) -> ReportGenerationRun | None:
    return await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.state == "planning",
            ReportGenerationRun.planner_job_id == job_id,
        )
        .with_for_update()
    )


async def generation_write_guard(
    session: AsyncSession,
    *,
    run_id: str,
    job_id: str,
) -> ReportGenerationRun | None:
    return await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.state == "generating",
            ReportGenerationRun.generation_job_id == job_id,
        )
        .with_for_update()
    )


async def _ensure_report_notification(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
    notification_type: str,
    title: str,
    body: str,
    link: str,
) -> None:
    existing = await session.scalar(
        select(Notification.id).where(
            Notification.user_id == run.user_id,
            Notification.type == notification_type,
            Notification.link == link,
        )
    )
    if existing is None:
        await create_notification(
            session,
            NotificationCreate(
                user_id=run.user_id,
                type=notification_type,
                title=title,
                body=body,
                link=link,
            ),
        )


async def persist_completed_report(
    session: AsyncSession,
    *,
    run_id: str,
    job_id: str,
    lease_owner: str | None,
    data: CompletedReportData,
    now: datetime | None = None,
) -> Report:
    existing = await session.scalar(
        select(Report).where(Report.generation_run_id == run_id)
    )
    if existing is not None:
        return existing

    run = await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.state == "generating",
            ReportGenerationRun.generation_job_id == job_id,
        )
        .with_for_update()
    )
    job_query = select(WorkflowJob).where(
        WorkflowJob.id == job_id,
        WorkflowJob.run_id == run_id,
        WorkflowJob.status == "running",
    )
    if lease_owner is not None:
        job_query = job_query.where(WorkflowJob.lease_owner == lease_owner)
    job = await session.scalar(job_query.with_for_update())
    if run is None or job is None:
        raise PersistRejected("run is cancelled or Job lease is stale")

    completed_at = now or utc_now()
    report = Report(
        user_id=run.user_id,
        generation_run_id=run.id,
        title=data.title,
        template_id=data.spec_json.template_id,
        template_version=data.spec_json.template_version,
        base_family=data.spec_json.base_family,
        content_md=data.content_md,
        html=data.html,
        spec_json=data.spec_json.model_dump(mode="json", by_alias=True),
        share_card_spec=data.share_card_spec.model_dump(mode="json"),
        tokens_used=data.tokens_used,
        gen_ms=data.gen_ms,
        created_at=completed_at,
    )
    session.add(report)
    await session.flush()
    run.report_id = report.id
    run.completed_at = completed_at
    run.active_stage = None
    transition_run(run, "completed", now=completed_at)
    checkpoint = dict(job.checkpoint_json or {})
    results = dict(checkpoint.get("stage_results", {}))
    results["persist"] = {"report_id": report.id}
    job.checkpoint_json = {
        "completed_stages": [
            "load_evidence",
            "web_search",
            "content_generation",
            "chart_validation",
            "illustration",
            "html_render",
            "persist",
        ],
        "stage_results": results,
    }
    job.status = "succeeded"
    job.lease_owner = None
    job.lease_expires_at = None
    job.error_code = None
    job.error_message = None
    job.completed_at = completed_at
    job.updated_at = completed_at
    await _ensure_report_notification(
        session,
        run=run,
        notification_type="report_done",
        title="报告已生成",
        body=data.title,
        link=f"report:{report.id}",
    )
    await session.flush()
    return report


async def record_report_failure(
    session: AsyncSession,
    *,
    run_id: str,
    job_id: str,
    lease_owner: str | None,
    failure_stage: str,
    error_code: str,
    error_message: str,
    retry_from: str,
    now: datetime | None = None,
) -> bool:
    run = await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.state == "generating",
            ReportGenerationRun.generation_job_id == job_id,
        )
        .with_for_update()
    )
    job_query = select(WorkflowJob).where(
        WorkflowJob.id == job_id,
        WorkflowJob.run_id == run_id,
        WorkflowJob.status == "running",
    )
    if lease_owner is not None:
        job_query = job_query.where(WorkflowJob.lease_owner == lease_owner)
    job = await session.scalar(job_query.with_for_update())
    if run is None or job is None:
        return False

    failed_at = now or utc_now()
    run.failure_stage = failure_stage
    run.error_code = error_code
    run.error_message = error_message
    run.retry_from = retry_from
    run.active_stage = None
    transition_run(run, "failed", now=failed_at)
    job.status = "failed"
    job.lease_owner = None
    job.lease_expires_at = None
    job.error_code = error_code
    job.error_message = error_message
    job.completed_at = failed_at
    job.updated_at = failed_at
    await _ensure_report_notification(
        session,
        run=run,
        notification_type="report_failed",
        title="报告生成失败",
        body="可以从失败阶段重试。",
        link=f"report-run:{run.id}",
    )
    await session.flush()
    return True


async def list_owned_reports(
    session: AsyncSession,
    *,
    user_id: str,
) -> list[Report]:
    return list(
        await session.scalars(
            select(Report)
            .where(Report.user_id == user_id)
            .order_by(Report.created_at.desc(), Report.id.desc())
        )
    )


async def get_owned_report(
    session: AsyncSession,
    *,
    user_id: str,
    report_id: str,
) -> Report | None:
    return await session.scalar(
        select(Report).where(
            Report.id == report_id,
            Report.user_id == user_id,
        )
    )


def _timestamp(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


async def serialize_run(
    session: AsyncSession,
    run: ReportGenerationRun,
) -> dict:
    scope = run.evidence_scope or {}
    skill_ids = list(scope.get("skill_ids", []))
    skills = {}
    if skill_ids:
        rows = await session.scalars(
            select(UserSkill).where(
                UserSkill.user_id == run.user_id,
                UserSkill.id.in_(skill_ids),
            )
        )
        skills = {skill.id: skill.display_name for skill in rows}

    def public_scope(value: dict) -> dict:
        counts = value.get("counts_by_skill", {})
        ids = list(value.get("skill_ids", []))
        return {
            "time_range": value.get("time_range"),
            "skill_ids": ids,
            "asset_ids": list(value.get("asset_ids", [])),
            "skills": [
                {
                    "id": skill_id,
                    "label": skills.get(skill_id, "Unknown skill"),
                    "count": int(counts.get(skill_id, 0)),
                }
                for skill_id in ids
            ],
            "asset_count": len(value.get("asset_ids", [])),
        }

    public_options = []
    for raw in run.plan_options or []:
        option = ReportPlanOption.model_validate(raw)
        public_options.append(
            {
                "id": option.id,
                "recommended": option.recommended,
                "title": option.title,
                "summary": option.summary,
                "report_goal": option.report_goal,
                "evidence": public_scope(
                    option.evidence_scope.model_dump(mode="json", by_alias=True)
                ),
                "web_search": option.web_search.model_dump(),
                "illustration": option.illustration.model_dump(),
            }
        )

    public_plan = None
    if run.execution_plan:
        plan = ReportExecutionPlan.model_validate(run.execution_plan)
        public_plan = {
            "report_goal": plan.report_goal,
            "time_range": (
                plan.time_range.model_dump(mode="json", by_alias=True)
                if plan.time_range
                else None
            ),
            "asset_count": len(plan.resolved_asset_ids),
            "web_policy": plan.web_policy,
            "illustration_policy": plan.illustration_policy,
        }
    return {
        "id": run.id,
        "origin": run.origin,
        "state": run.state,
        "active_stage": run.active_stage,
        "intent": run.intent,
        "answers": run.answers,
        "evidence_scope": public_scope(scope),
        "pending_decision": run.pending_decision,
        "plan_options": public_options,
        "selected_option_id": run.selected_option_id,
        "execution_plan": public_plan,
        "failure": (
            {
                "stage": run.failure_stage,
                "code": run.error_code,
                "message": run.error_message,
                "retry_from": run.retry_from,
            }
            if run.state == "failed"
            else None
        ),
        "report_id": run.report_id,
        "job_id": (
            run.generation_job_id
            if run.state == "generating"
            else run.planner_job_id
        ),
        "created_at": _timestamp(run.created_at),
        "updated_at": _timestamp(run.updated_at),
    }
