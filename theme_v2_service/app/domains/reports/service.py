from copy import deepcopy
from datetime import datetime, timezone

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.config import get_settings
from app.db.base import new_uuid, utc_now
from app.db.models import Asset, Contact, Event, UserSkill, WorkflowJob
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.reports.models import Report, ReportGenerationRun
from app.domains.reports.schemas import (
    EvidenceReference,
    EvidenceScope,
    IllustrationStatus,
    PendingDecision,
    ReportPlanDraft,
    ReportPlanDraftUpdate,
    ReportScopeDraft,
    ReportScopeDraftUpdate,
    ReportSpec,
    ReportExecutionPlan,
    ReportPlanOption,
    RunDecisionRequest,
    TriggerRunCreate,
    UserRunCreate,
    ShareCardSpec,
)
from app.domains.reports.scope_adapters import (
    ReportScopeCandidateResponse,
    initial_scope,
    list_scope_candidates,
    scope_digest,
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
from app.jobs.registry import REPORT_SCOPE_RESOLUTION_JOB_TYPE
from app.observability import metrics


ACTIVE_STATES = {"planning", "awaiting_selection", "generating", "failed"}


def _utc_naive(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc).replace(tzinfo=None)


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
    illustration_status: IllustrationStatus = "not_required"
    illustration_job_id: str | None = None

    @model_validator(mode="after")
    def reject_internal_citation_markers(self) -> "CompletedReportData":
        visible = f"{self.content_md}\n{self.html or ''}".casefold()
        if "[evidence:" in visible or "[source:" in visible:
            raise ValueError("internal citation marker cannot be persisted")
        return self


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
    now = utc_now()
    settings = get_settings()
    draft = initial_scope(
        command.intent,
        now=now,
        timezone_name=settings.default_user_timezone,
    )
    if draft.adapter_kind == "period_summary" and not (
        command.skill_ids or command.asset_ids
    ):
        candidates = await list_scope_candidates(
            session,
            user_id=user_id,
            adapter_kind=draft.adapter_kind,
            intent=command.intent,
            now=now,
            timezone_name=settings.default_user_timezone,
        )
        draft = candidates.default_scope
    else:
        draft = ReportScopeDraft.model_validate(
            {
                **draft.model_dump(mode="python", by_alias=True),
                "skill_ids": list(command.skill_ids),
                "supporting_references": [
                    {"kind": "asset", "id": asset_id}
                    for asset_id in command.asset_ids
                ],
                "time_range": command.time_range or draft.time_range,
            }
        )
    scope = await _validate_owned_scope(
        session,
        user_id=user_id,
        scope=draft.to_evidence_scope(),
    )
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="awaiting_selection",
        active_stage="scope_confirmation",
        launch_context={},
        intent=command.intent,
        answers={},
        evidence_scope=scope.model_dump(mode="json", by_alias=True),
        pending_decision=PendingDecision(
            type="scope_confirmation",
            adapter_kind=draft.adapter_kind,
        ).model_dump(mode="json", exclude_none=True),
        plan_options=[],
        scope_adapter=draft.adapter_kind,
        scope_draft=draft.model_dump(mode="json", by_alias=True),
        scope_revision=0,
        scope_hash=scope_digest(draft, primary_version=None),
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    metrics.increment("run_created_total", labels={"origin": run.origin})
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
    legacy_scope = EvidenceScope(
        skill_ids=(
            [launch_context["primary_skill_id"]]
            if launch_context.get("primary_skill_id")
            else []
        ),
        asset_ids=list(launch_context.get("asset_ids", [])),
    )
    base_draft = initial_scope(
        "",
        now=utc_now(),
        timezone_name=get_settings().default_user_timezone,
        trigger_event_id=launch_context.get("event_id"),
    )
    draft = ReportScopeDraft.model_validate(
        {
            **base_draft.model_dump(mode="python", by_alias=True),
            "skill_ids": legacy_scope.skill_ids,
            "supporting_references": legacy_scope.references,
        }
    )
    scope = draft.to_evidence_scope()
    run = ReportGenerationRun(
        user_id=user_id,
        origin="trigger",
        trigger_execution_id=execution.id,
        state="awaiting_selection",
        active_stage="scope_confirmation",
        launch_context=launch_context,
        intent=None,
        answers={},
        evidence_scope=scope.model_dump(mode="json", by_alias=True),
        pending_decision=PendingDecision(
            type="scope_confirmation",
            adapter_kind=draft.adapter_kind,
        ).model_dump(mode="json", exclude_none=True),
        plan_options=[],
        scope_adapter=draft.adapter_kind,
        scope_draft=draft.model_dump(mode="json", by_alias=True),
        scope_revision=0,
        scope_hash=scope_digest(draft, primary_version=None),
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
    metrics.increment("run_created_total", labels={"origin": run.origin})
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
    if (run.pending_decision or {}).get("type") == "scope_confirmation":
        raise RunConflict("report scope must be prepared through the scope workflow")
    run.answers = {**run.answers, **command.answers}
    if command.evidence_scope is not None:
        run.evidence_scope = command.evidence_scope.model_dump(
            mode="json",
            by_alias=True,
        )
    run.pending_decision = None
    run.plan_options = []
    run.plan_draft = None
    run.selected_option_id = None
    run.execution_plan = None
    await _enqueue_planner(session, run, reason="decision")
    transition_run(run, "planning", now=now or utc_now())
    await session.flush()
    return run


async def get_scope_candidates(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    now: datetime | None = None,
) -> ReportScopeCandidateResponse:
    run = await get_owned_run(session, user_id=user_id, run_id=run_id)
    if run.scope_adapter is None:
        raise RunConflict("run does not support report scope selection")
    return await list_scope_candidates(
        session,
        user_id=user_id,
        adapter_kind=run.scope_adapter,
        intent=run.intent or "",
        now=now or utc_now(),
        timezone_name=get_settings().default_user_timezone,
    )


async def _scope_primary_event(
    session: AsyncSession,
    *,
    user_id: str,
    draft: ReportScopeDraft,
) -> Event | None:
    reference = draft.primary_reference
    if reference is None:
        return None
    if reference.kind != "event":
        return None
    event = await session.scalar(
        select(Event).where(
            Event.id == reference.id,
            Event.user_id == user_id,
        )
    )
    if event is None:
        raise RunConflict("evidence scope contains unavailable references")
    if event.status in {"cancelled", "deleted", "completed"}:
        raise RunConflict("primary Event is no longer available")
    return event


def _apply_primary_event_context(
    run: ReportGenerationRun,
    event: Event | None,
) -> None:
    context = dict(run.launch_context or {})
    if event is None:
        context.pop("event_id", None)
        context.pop("event_title", None)
    else:
        context["event_id"] = event.id
        context["event_title"] = event.title
    run.launch_context = context


async def update_scope_draft(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    command: ReportScopeDraftUpdate,
) -> ReportGenerationRun:
    run = await owned_run_for_update(session, user_id=user_id, run_id=run_id)
    if run.state != "awaiting_selection":
        raise RunConflict("run is not awaiting scope confirmation")
    if run.scope_adapter is None:
        raise RunConflict("run does not support report scope selection")
    if int(run.scope_revision or 0) != command.expected_revision:
        raise RunConflict("scope revision is stale")
    draft = command.draft
    if draft.adapter_kind != run.scope_adapter:
        raise RunConflict("scope adapter cannot be changed")
    if draft.adapter_kind == "pre_event_briefing" and draft.primary_reference is None:
        raise RunConflict("pre-event report requires a primary Event")
    if draft.adapter_kind == "period_summary":
        draft = await _resolve_period_summary_selection(
            session,
            user_id=user_id,
            draft=draft,
        )
    scope = await _validate_owned_scope(
        session,
        user_id=user_id,
        scope=draft.to_evidence_scope(),
    )
    event = await _scope_primary_event(
        session,
        user_id=user_id,
        draft=draft,
    )
    primary_version = _timestamp(event.updated_at) if event is not None else None
    run.scope_draft = draft.model_dump(mode="json", by_alias=True)
    run.scope_revision = int(run.scope_revision or 0) + 1
    run.scope_hash = scope_digest(draft, primary_version=primary_version)
    run.evidence_scope = scope.model_dump(mode="json", by_alias=True)
    run.pending_decision = PendingDecision(
        type="scope_confirmation",
        adapter_kind=draft.adapter_kind,
    ).model_dump(mode="json", exclude_none=True)
    run.active_stage = "scope_confirmation"
    run.plan_options = []
    run.plan_draft = None
    run.plan_scope_hash = None
    run.selected_option_id = None
    run.execution_plan = None
    run.planner_job_id = None
    _apply_primary_event_context(run, event)
    await session.flush()
    return run


async def _resolve_period_summary_selection(
    session: AsyncSession,
    *,
    user_id: str,
    draft: ReportScopeDraft,
) -> ReportScopeDraft:
    """Make the persisted evidence set authoritative at the save boundary."""
    auto_references: list[EvidenceReference] = []
    if draft.time_range is not None and draft.skill_ids:
        observed_at = func.coalesce(Asset.effective_at, Asset.created_at)
        query = (
            select(Asset.id)
            .join(UserSkill, UserSkill.id == Asset.user_skill_id)
            .where(
                Asset.user_id == user_id,
                Asset.user_skill_id.in_(draft.skill_ids),
                UserSkill.user_id == user_id,
                UserSkill.enabled.is_(True),
            )
            .order_by(observed_at.asc(), Asset.id.asc())
        )
        if draft.time_range.from_at is not None:
            query = query.where(
                observed_at >= _utc_naive(draft.time_range.from_at)
            )
        if draft.time_range.to_at is not None:
            query = query.where(observed_at < _utc_naive(draft.time_range.to_at))
        auto_references = [
            EvidenceReference(kind="asset", id=asset_id)
            for asset_id in await session.scalars(query)
        ]

    selection = draft.selection.model_copy(
        update={"auto_references": auto_references}
    )
    return draft.model_copy(
        update={
            "selection": selection,
            "supporting_references": selection.resolved_references(),
            "missing_dimensions": (
                ["time_range"] if draft.time_range is None else []
            ),
        }
    )


async def prepare_scope_plan(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    expected_revision: int,
    now: datetime | None = None,
) -> tuple[ReportGenerationRun, WorkflowJob]:
    run = await owned_run_for_update(session, user_id=user_id, run_id=run_id)
    if run.state == "planning" and run.planner_job_id is not None:
        job = await session.get(WorkflowJob, run.planner_job_id)
        if job is not None:
            return run, job
    if run.state != "awaiting_selection":
        raise RunConflict("run is not awaiting scope confirmation")
    if int(run.scope_revision or 0) != expected_revision:
        raise RunConflict("scope revision is stale")
    if run.scope_draft is None:
        raise RunConflict("report scope is missing")
    draft = ReportScopeDraft.model_validate(run.scope_draft)
    if draft.adapter_kind == "pre_event_briefing" and draft.primary_reference is None:
        raise RunConflict("pre-event report requires a primary Event")
    scope = await _validate_owned_scope(
        session,
        user_id=user_id,
        scope=draft.to_evidence_scope(),
    )
    if not scope.references and not scope.skill_ids:
        raise RunConflict("report scope requires at least one evidence reference")
    event = await _scope_primary_event(
        session,
        user_id=user_id,
        draft=draft,
    )
    primary_version = _timestamp(event.updated_at) if event is not None else None
    current_hash = scope_digest(draft, primary_version=primary_version)
    run.scope_hash = current_hash
    run.evidence_scope = scope.model_dump(mode="json", by_alias=True)
    run.pending_decision = None
    run.plan_options = []
    run.plan_draft = None
    run.plan_scope_hash = None
    run.selected_option_id = None
    run.execution_plan = None
    _apply_primary_event_context(run, event)
    job = await _enqueue_planner(session, run, reason=f"scope:{current_hash}")
    transition_run(run, "planning", now=now or utc_now())
    await session.flush()
    return run, job


async def _validate_owned_scope(
    session: AsyncSession,
    *,
    user_id: str,
    scope: EvidenceScope,
) -> EvidenceScope:
    skill_ids = list(dict.fromkeys(scope.skill_ids))
    if skill_ids:
        owned_skill_ids = set(
            await session.scalars(
                select(UserSkill.id).where(
                    UserSkill.user_id == user_id,
                    UserSkill.id.in_(skill_ids),
                )
            )
        )
        if owned_skill_ids != set(skill_ids):
            raise RunConflict("evidence scope contains unavailable Skills")

    grouped = {
        "asset": [ref.id for ref in scope.references if ref.kind == "asset"],
        "event": [ref.id for ref in scope.references if ref.kind == "event"],
        "contact": [ref.id for ref in scope.references if ref.kind == "contact"],
    }
    owned: dict[str, set[str]] = {"asset": set(), "event": set(), "contact": set()}
    if grouped["asset"]:
        owned["asset"] = set(
            await session.scalars(
                select(Asset.id).where(
                    Asset.user_id == user_id,
                    Asset.id.in_(grouped["asset"]),
                )
            )
        )
    if grouped["event"]:
        owned["event"] = set(
            await session.scalars(
                select(Event.id).where(
                    Event.user_id == user_id,
                    Event.id.in_(grouped["event"]),
                )
            )
        )
    if grouped["contact"]:
        owned["contact"] = set(
            await session.scalars(
                select(Contact.id).where(
                    Contact.user_id == user_id,
                    Contact.id.in_(grouped["contact"]),
                )
            )
        )
    unavailable = [
        reference
        for reference in scope.references
        if reference.id not in owned[reference.kind]
    ]
    if unavailable:
        raise RunConflict("evidence scope contains unavailable references")
    return scope


def _draft_from_option(option: ReportPlanOption) -> ReportPlanDraft:
    return ReportPlanDraft(
        selected_option_id=option.id,
        attention_questions=option.attention_questions,
        evidence_scope=option.evidence_scope,
        public_research_scope=option.public_research_scope,
        blockers=option.blockers,
    )


async def update_plan_draft(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    command: ReportPlanDraftUpdate,
    now: datetime | None = None,
) -> tuple[ReportGenerationRun, WorkflowJob | None]:
    from app.domains.reports.scope_resolution import blockers_for_scope

    run = await owned_run_for_update(session, user_id=user_id, run_id=run_id)
    if run.state != "awaiting_selection":
        raise RunConflict("run is not awaiting plan adjustment")
    if int(run.plan_revision or 0) != command.expected_revision:
        raise RunConflict("plan revision is stale")
    if not any(
        raw.get("id") == command.selected_option_id
        for raw in (run.plan_options or [])
    ):
        raise RunConflict("selected option does not exist")

    scope = await _validate_owned_scope(
        session,
        user_id=user_id,
        scope=command.evidence_scope,
    )
    previous = (
        ReportPlanDraft.model_validate(run.plan_draft)
        if run.plan_draft is not None
        else None
    )
    draft = ReportPlanDraft(
        selected_option_id=command.selected_option_id,
        attention_questions=command.attention_questions,
        additional_focus=command.additional_focus.strip(),
        evidence_scope=scope,
        public_research_scope=command.public_research_scope,
        blockers=blockers_for_scope(
            command.public_research_scope,
            additional_focus=command.additional_focus,
        ),
    )
    if previous is not None and previous == draft:
        return run, None

    focus_changed = (
        bool(draft.additional_focus)
        if previous is None
        else previous.additional_focus != draft.additional_focus
    )
    previous_references = (
        {
            (reference.kind, reference.id)
            for reference in previous.evidence_scope.references
        }
        if previous is not None
        else set()
    )
    current_references = {
        (reference.kind, reference.id) for reference in draft.evidence_scope.references
    }
    references_changed = previous is not None and (
        previous_references != current_references
    )
    run.plan_draft = draft.model_dump(mode="json", by_alias=True)
    run.evidence_scope = scope.model_dump(mode="json", by_alias=True)
    run.plan_revision = int(run.plan_revision or 0) + 1
    if not (focus_changed or references_changed):
        await session.flush()
        return run, None

    job = await enqueue_job(
        session,
        run_id=run.id,
        job_type=REPORT_SCOPE_RESOLUTION_JOB_TYPE,
        dedupe_key=f"scope-resolution:{run.id}:{run.plan_revision}",
        max_attempts=get_settings().report_provider_max_attempts,
    )
    job.checkpoint_json = {"plan_revision": run.plan_revision}
    run.scope_resolution_job_id = job.id
    run.active_stage = "scope_resolution"
    transition_run(run, "planning", now=now or utc_now())
    await session.flush()
    return run, job


async def generate_run(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    selected_option_id: str,
    expected_plan_revision: int,
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
    if run.scope_hash is not None and run.plan_scope_hash != run.scope_hash:
        raise RunConflict("report plan was built from a stale scope")

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
    if int(run.plan_revision or 0) != expected_plan_revision:
        raise RunConflict("plan revision is stale")
    draft = (
        ReportPlanDraft.model_validate(run.plan_draft)
        if run.plan_draft is not None
        else _draft_from_option(option)
    )
    if draft.selected_option_id != selected_option_id:
        raise RunConflict("selected option does not match the confirmed draft")
    if draft.blockers:
        raise RunConflict("report plan has unresolved blockers")
    if not draft.evidence_scope.references and not run.launch_context.get("event_id"):
        raise RunConflict("report plan requires at least one evidence reference")
    await _validate_owned_scope(
        session,
        user_id=user_id,
        scope=draft.evidence_scope,
    )
    execution_plan = ReportExecutionPlan(
        template_id=option.template_id,
        template_version=option.template_version,
        base_family=option.base_family,
        report_goal=option.report_goal,
        resolved_asset_ids=draft.evidence_scope.asset_ids,
        resolved_references=draft.evidence_scope.references,
        attention_questions=draft.attention_questions,
        public_research_brief=draft.public_research_scope,
        field_bindings=option.field_bindings,
        time_range=draft.evidence_scope.time_range,
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
    run.plan_draft = draft.model_dump(mode="json", by_alias=True)
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
    job_ids = [
        value
        for value in (
            run.planner_job_id,
            run.scope_resolution_job_id,
            run.generation_job_id,
        )
        if value
    ]
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
    metrics.increment("run_cancelled_total")
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
        illustration_status=data.illustration_status,
        illustration_job_id=data.illustration_job_id,
        revision=1,
        created_at=completed_at,
        updated_at=completed_at,
    )
    session.add(report)
    await session.flush()
    run.report_id = report.id
    run.completed_at = completed_at
    run.active_stage = None
    transition_run(
        run,
        "illustration_pending"
        if data.illustration_status == "pending"
        else "completed",
        now=completed_at,
    )
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
    metrics.increment("run_completed_total")
    metrics.observe("tokens_used", float(data.tokens_used))
    await session.flush()
    return report


async def record_planner_failure(
    session: AsyncSession,
    *,
    run_id: str,
    job_id: str,
    lease_owner: str | None,
    error_code: str,
    error_message: str,
    now: datetime | None = None,
) -> bool:
    run = await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == run_id,
            ReportGenerationRun.state == "planning",
            ReportGenerationRun.planner_job_id == job_id,
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
    run.failure_stage = "planning"
    run.error_code = error_code
    run.error_message = error_message
    run.retry_from = "planning"
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
        body="报告方案生成失败，可以重试。",
        link=f"report-run:{run.id}",
    )
    metrics.increment("run_failed_total", labels={"failure_stage": "planning"})
    await session.flush()
    return True


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
    metrics.increment(
        "run_failed_total",
        labels={"failure_stage": failure_stage},
    )
    metrics.observe("failure_stage", 1, labels={"stage": failure_stage})
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
            "references": list(value.get("references", [])),
            "skills": [
                {
                    "id": skill_id,
                    "label": skills.get(skill_id, "Unknown skill"),
                    "count": int(counts.get(skill_id, 0)),
                }
                for skill_id in ids
            ],
            "asset_count": len(value.get("references") or value.get("asset_ids", [])),
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
            "reference_count": len(plan.resolved_references),
            "web_policy": plan.web_policy,
            "illustration_policy": plan.illustration_policy,
        }
    public_draft = None
    if run.plan_draft is not None:
        draft = ReportPlanDraft.model_validate(run.plan_draft)
        public_draft = draft.model_dump(mode="json", by_alias=True)
    public_scope_draft = None
    if run.scope_draft is not None:
        public_scope_draft = ReportScopeDraft.model_validate(
            run.scope_draft
        ).model_dump(mode="json", by_alias=True)
    return {
        "id": run.id,
        "origin": run.origin,
        "state": run.state,
        "active_stage": run.active_stage,
        "intent": run.intent,
        "answers": run.answers,
        "evidence_scope": public_scope(scope),
        "scope_adapter": run.scope_adapter,
        "scope_draft": public_scope_draft,
        "scope_revision": int(run.scope_revision or 0),
        "pending_decision": run.pending_decision,
        "plan_options": public_options,
        "plan_draft": public_draft,
        "plan_revision": int(run.plan_revision or 0),
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
            else (
                run.scope_resolution_job_id
                if run.active_stage == "scope_resolution"
                else run.planner_job_id
            )
        ),
        "created_at": _timestamp(run.created_at),
        "updated_at": _timestamp(run.updated_at),
    }
