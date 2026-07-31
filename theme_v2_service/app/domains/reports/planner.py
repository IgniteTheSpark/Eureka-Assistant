from collections.abc import Awaitable, Callable
from time import perf_counter
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.planner_tools import (
    PlannerAssetSummary,
    PlannerEvent,
    PlannerLimits,
    PlannerSkill,
    PlannerTools,
)
from app.domains.reports.providers import ReportPlannerProvider
from app.domains.reports.schemas import (
    ClarificationQuestion,
    EvidenceScope,
    PendingDecision,
    ReportPlanOption,
)
from app.domains.reports.state_machine import transition_run
from app.domains.reports.templates import TemplatePackage, TemplateRegistry
from app.observability import metrics


class InvalidPlannerResult(ValueError):
    pass


class PlannerContextTooLarge(ValueError):
    pass


class PlannerModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PlannerTemplate(PlannerModel):
    id: str
    version: str
    base_family: str
    planner_description: str
    data_fit: list[str]
    analysis_method: str
    web_policy: str
    illustration_policy: str
    render_policy: str
    skill_markdown: str


class PlannerRequest(PlannerModel):
    run_id: str
    origin: str
    intent: str | None
    launch_context: dict
    answers: dict
    evidence_scope: EvidenceScope
    primary_skills: list[PlannerSkill]
    related_skills: list[PlannerSkill]
    asset_summaries: list[PlannerAssetSummary]
    event: PlannerEvent | None = None
    templates: list[PlannerTemplate]

    @property
    def primary_skill_ids(self) -> set[str]:
        return {skill.id for skill in self.primary_skills}

    @property
    def primary_asset_ids(self) -> set[str]:
        primary = self.primary_skill_ids
        return {
            summary.id
            for summary in self.asset_summaries
            if summary.user_skill_id in primary
        }


class PlannerUsage(PlannerModel):
    input_tokens: int = Field(default=0, ge=0)
    output_tokens: int = Field(default=0, ge=0)
    model_profile: str = "report_planner"


class PlannerResult(PlannerModel):
    clarification_questions: list[ClarificationQuestion] = Field(default_factory=list)
    options: list[ReportPlanOption] = Field(default_factory=list, max_length=3)
    usage: PlannerUsage = Field(default_factory=PlannerUsage)

    @model_validator(mode="after")
    def require_one_result_shape(self) -> "PlannerResult":
        if bool(self.clarification_questions) == bool(self.options):
            raise ValueError("planner returns clarification questions or options")
        if self.options:
            option_ids = [option.id for option in self.options]
            if len(set(option_ids)) != len(option_ids):
                raise ValueError("planner option IDs must be unique")
            if sum(option.recommended for option in self.options) != 1:
                raise ValueError("planner options require exactly one recommendation")
        return self


def _template_view(package: TemplatePackage) -> PlannerTemplate:
    manifest = package.manifest
    return PlannerTemplate(
        id=manifest.id,
        version=manifest.version,
        base_family=manifest.base_family,
        planner_description=manifest.planner_description,
        data_fit=manifest.data_fit,
        analysis_method=manifest.analysis_method,
        web_policy=manifest.web_policy,
        illustration_policy=manifest.illustration_policy,
        render_policy=manifest.render_policy,
        skill_markdown=package.skill_markdown,
    )


def _related_score(skill: PlannerSkill, primary: list[PlannerSkill]) -> int:
    score = 0
    primary_capabilities = {
        capability for item in primary for capability in item.capabilities
    }
    primary_domains = {item.domain for item in primary if item.domain}
    if primary_capabilities.intersection(skill.capabilities):
        score += 2
    if skill.domain and skill.domain in primary_domains:
        score += 2
    primary_words = {
        word.casefold()
        for item in primary
        for value in (item.display_name, item.description or "")
        for word in value.split()
        if len(word) >= 2
    }
    related_words = {
        word.casefold()
        for value in (skill.display_name, skill.description or "")
        for word in value.split()
        if len(word) >= 2
    }
    if primary_words.intersection(related_words):
        score += 1
    return score


async def build_planner_request(
    *,
    run: ReportGenerationRun,
    tools: PlannerTools,
    registry: TemplateRegistry,
) -> PlannerRequest:
    scope = EvidenceScope.model_validate(run.evidence_scope or {})
    primary_ids = list(scope.skill_ids)
    launch_primary = run.launch_context.get("primary_skill_id")
    if launch_primary and launch_primary not in primary_ids:
        primary_ids.append(launch_primary)

    skills = await tools.list_user_skills(preferred_ids=primary_ids)
    by_id = {skill.id: skill for skill in skills}
    primary = [by_id[skill_id] for skill_id in primary_ids if skill_id in by_id]
    related = [skill for skill in skills if skill.id not in set(primary_ids)]
    related.sort(key=lambda item: (-_related_score(item, primary), item.id))
    if primary:
        related = [item for item in related if _related_score(item, primary) > 0]

    summaries: list[PlannerAssetSummary] = []
    for skill in [*primary, *related]:
        summaries.extend(
            await tools.get_asset_summaries(
                skill.id,
                time_range=scope.time_range,
            )
        )

    event = None
    event_id = run.launch_context.get("event_id")
    if event_id:
        event = await tools.get_event(event_id)

    capabilities = {
        capability
        for skill in [*primary, *related]
        for capability in skill.capabilities
    }
    if event is not None:
        capabilities.add("event")
        if event.location:
            capabilities.add("location")
    candidates = registry.candidates_for(capabilities)
    request = PlannerRequest(
        run_id=run.id,
        origin=run.origin,
        intent=run.intent,
        launch_context=run.launch_context,
        answers=run.answers,
        evidence_scope=scope,
        primary_skills=primary,
        related_skills=related,
        asset_summaries=summaries,
        event=event,
        templates=[_template_view(package) for package in candidates],
    )
    if len(request.model_dump_json().encode("utf-8")) > tools.limits.max_serialized_context_bytes:
        raise PlannerContextTooLarge("planner serialized context exceeds configured limit")
    return request


def validate_planner_result(
    *,
    request: PlannerRequest,
    result: PlannerResult,
    registry: TemplateRegistry,
) -> None:
    if result.clarification_questions:
        return

    available_templates = {
        (template.id, template.version) for template in request.templates
    }
    available_skill_ids = {
        skill.id for skill in [*request.primary_skills, *request.related_skills]
    }
    available_asset_ids = {summary.id for summary in request.asset_summaries}
    for option in result.options:
        key = (option.template_id, option.template_version)
        if key not in available_templates:
            raise InvalidPlannerResult("option uses an unavailable template")
        package = registry.get(option.template_id, option.template_version)
        manifest = package.manifest
        if option.base_family != manifest.base_family:
            raise InvalidPlannerResult("option base family conflicts with template")
        if option.web_search.policy != manifest.web_policy:
            raise InvalidPlannerResult("option web policy conflicts with template")
        if option.illustration.policy != manifest.illustration_policy:
            raise InvalidPlannerResult("option illustration policy conflicts with template")
        if option.render_policy != manifest.render_policy:
            raise InvalidPlannerResult("option render policy conflicts with template")
        if not set(option.evidence_scope.skill_ids).issubset(available_skill_ids):
            raise InvalidPlannerResult("option references an unavailable Skill")
        if not set(option.evidence_scope.asset_ids).issubset(available_asset_ids):
            raise InvalidPlannerResult("option references an unavailable Asset")

    if request.primary_skill_ids and request.primary_asset_ids:
        has_primary_only = any(
            set(option.evidence_scope.skill_ids) == request.primary_skill_ids
            and set(option.evidence_scope.asset_ids).issubset(
                request.primary_asset_ids
            )
            and bool(option.evidence_scope.asset_ids)
            for option in result.options
        )
        if not has_primary_only:
            raise InvalidPlannerResult(
                "sufficient evidence requires a primary-only option"
            )


async def _ensure_plan_notification(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
) -> None:
    link = f"report-run:{run.id}"
    existing = await session.scalar(
        select(Notification.id).where(
            Notification.user_id == run.user_id,
            Notification.type == "report_plan_ready",
            Notification.link == link,
        )
    )
    if existing is None:
        await create_notification(
            session,
            NotificationCreate(
                user_id=run.user_id,
                type="report_plan_ready",
                title="报告方案已准备好",
                body="请选择方案并确认用于生成报告的数据。",
                link=link,
            ),
        )


async def persist_planner_result(
    session: AsyncSession,
    *,
    run_id: str,
    job_id: str,
    result: PlannerResult,
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
    if run is None:
        return False

    if result.clarification_questions:
        run.plan_options = []
        run.pending_decision = PendingDecision(
            type="clarification",
            questions=result.clarification_questions,
        ).model_dump(mode="json")
    else:
        run.plan_options = [
            option.model_dump(mode="json", by_alias=True) for option in result.options
        ]
        recommended = next(option for option in result.options if option.recommended)
        run.pending_decision = PendingDecision(
            type="plan_selection",
            recommended_option_id=recommended.id,
        ).model_dump(mode="json")
    run.active_stage = "awaiting_selection"
    usage = dict(run.usage_json or {})
    usage["planner"] = result.usage.model_dump(mode="json")
    run.usage_json = usage
    transition_run(run, "awaiting_selection")
    metrics.increment("run_awaiting_selection_total")
    await _ensure_plan_notification(session, run=run)
    await session.flush()
    return True


async def execute_report_planner_job(
    job: WorkflowJob,
    *,
    provider: ReportPlannerProvider,
    registry: TemplateRegistry,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
    limits: PlannerLimits | None = None,
) -> bool:
    started = perf_counter()
    if job.run_id is None:
        return False
    try:
        async with session_factory() as read_session:
            run = await read_session.scalar(
                select(ReportGenerationRun).where(
                    ReportGenerationRun.id == job.run_id,
                    ReportGenerationRun.state == "planning",
                    ReportGenerationRun.planner_job_id == job.id,
                )
            )
            if run is None:
                return False
            request = await build_planner_request(
                run=run,
                tools=PlannerTools(
                    read_session,
                    user_id=run.user_id,
                    limits=limits,
                ),
                registry=registry,
            )

        result = PlannerResult.model_validate(await provider.plan(request))
        validate_planner_result(request=request, result=result, registry=registry)

        async with session_factory() as write_session:
            written = await persist_planner_result(
                write_session,
                run_id=job.run_id,
                job_id=job.id,
                result=result,
            )
            await write_session.commit()
        if written:
            tokens = result.usage.input_tokens + result.usage.output_tokens
            metrics.observe("planner_tokens", float(tokens))
            metrics.observe(
                "planner_clarification_rate",
                1.0 if result.clarification_questions else 0.0,
            )
            metrics.observe("planner_option_count", float(len(result.options)))
            metrics.observe(
                "related_skill_discovery_rate",
                1.0 if request.related_skills else 0.0,
            )
        return written
    except Exception:
        metrics.increment("planner_failed_total")
        raise
    finally:
        metrics.observe("planner_duration_ms", (perf_counter() - started) * 1000)


def planner_handler(
    *,
    provider: ReportPlannerProvider,
    registry: TemplateRegistry,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
    limits: PlannerLimits | None = None,
) -> Callable[[WorkflowJob], Awaitable[None]]:
    async def handle(job: WorkflowJob) -> None:
        await execute_report_planner_job(
            job,
            provider=provider,
            registry=registry,
            session_factory=session_factory,
            limits=limits,
        )

    return handle
