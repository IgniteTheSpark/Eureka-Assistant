from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass, field
import asyncio
import hashlib
import logging
from time import perf_counter
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import get_settings
from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.charts import ChartDirective, render_chart
from app.domains.reports.evidence import InsufficientEvidence, load_latest_evidence
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.illustration_jobs import enqueue_report_illustration
from app.domains.reports.providers import (
    GeneratedSuggestedAction,
    GeneratorRequest,
    IllustrationProvider,
    PermanentProviderError,
    ReportGeneratorProvider,
    RetryableProviderError,
    WebSearchProvider,
)
from app.domains.reports.rendering import render_report_presentation
from app.domains.reports.normalization import normalize_report_content
from app.domains.reports.schemas import ReportExecutionPlan, ReportSpec
from app.domains.reports.security import validate_generator_result
from app.domains.reports.storage import Storage
from app.domains.reports.providers_image import sanitize_illustration_prompt
from app.domains.reports.templates import TemplateRegistry
from app.domains.reports.web_search import build_web_queries, execute_web_search
from app.observability import metrics


logger = logging.getLogger(__name__)


STAGES = (
    "load_evidence",
    "web_search",
    "content_generation",
    "chart_validation",
    "illustration",
    "html_render",
    "persist",
)

StageResult = dict[str, Any]
StageHandler = Callable[["PipelineContext"], Awaitable[StageResult]]
AssertCurrent = Callable[[], Awaitable[None]]
SaveCheckpoint = Callable[[str, StageResult, int], Awaitable[None]]


class PipelineWriteRejected(RuntimeError):
    pass


@dataclass
class PipelineContext:
    run_id: str
    job_id: str
    execution_plan: ReportExecutionPlan | dict
    handlers: Mapping[str, StageHandler]
    checkpoints: dict[str, StageResult] = field(default_factory=dict)
    stage_timings_ms: dict[str, int] = field(default_factory=dict)
    assert_current_callback: AssertCurrent | None = None
    save_checkpoint_callback: SaveCheckpoint | None = None

    def __post_init__(self) -> None:
        self.execution_plan = ReportExecutionPlan.model_validate(self.execution_plan)

    @property
    def resume_index(self) -> int:
        for index, stage in enumerate(STAGES):
            if stage not in self.checkpoints:
                return index
        return len(STAGES)

    async def assert_current_and_not_cancelled(self) -> None:
        if self.assert_current_callback is not None:
            await self.assert_current_callback()

    async def save_checkpoint(
        self,
        stage: str,
        result: StageResult,
        duration_ms: int = 0,
    ) -> None:
        if self.save_checkpoint_callback is not None:
            await self.save_checkpoint_callback(stage, result, duration_ms)
        self.checkpoints[stage] = result
        self.stage_timings_ms[stage] = duration_ms


async def execute_report_job(context: PipelineContext) -> None:
    missing = set(STAGES).difference(context.handlers)
    if missing:
        raise ValueError(f"missing pipeline handlers: {sorted(missing)}")
    for stage in STAGES[context.resume_index :]:
        await context.assert_current_and_not_cancelled()
        started = perf_counter()
        result = await context.handlers[stage](context)
        duration_ms = max(0, round((perf_counter() - started) * 1000))
        context.stage_timings_ms[stage] = duration_ms
        metrics.observe(
            "pipeline_stage_duration_ms",
            duration_ms,
            labels={"stage": stage},
        )
        if stage == "persist":
            # Persist owns the final Report/Run/Job/Notification transaction and
            # writes its own terminal checkpoint.
            context.checkpoints[stage] = result
        else:
            await context.save_checkpoint(stage, result, duration_ms)


async def _assert_database_current(
    session_factory: async_sessionmaker[AsyncSession],
    *,
    run_id: str,
    job_id: str,
    lease_owner: str | None,
) -> None:
    async with session_factory() as session:
        current = await session.scalar(
            select(ReportGenerationRun.id).where(
                ReportGenerationRun.id == run_id,
                ReportGenerationRun.state == "generating",
                ReportGenerationRun.generation_job_id == job_id,
            )
        )
        job_query = select(WorkflowJob.id).where(
            WorkflowJob.id == job_id,
            WorkflowJob.run_id == run_id,
            WorkflowJob.status == "running",
        )
        if lease_owner is not None:
            job_query = job_query.where(WorkflowJob.lease_owner == lease_owner)
        current_job = await session.scalar(job_query)
    if current is None or current_job is None:
        raise PipelineWriteRejected("run is cancelled or generation job is stale")


async def _save_database_checkpoint(
    session_factory: async_sessionmaker[AsyncSession],
    *,
    run_id: str,
    job_id: str,
    lease_owner: str | None,
    stage: str,
    result: StageResult,
    duration_ms: int,
) -> None:
    async with session_factory() as session:
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
            raise PipelineWriteRejected("run is cancelled or generation job is stale")
        checkpoint = dict(job.checkpoint_json or {})
        stage_results = dict(checkpoint.get("stage_results", {}))
        stage_results[stage] = result
        stage_timings_ms = dict(checkpoint.get("stage_timings_ms", {}))
        stage_timings_ms[stage] = duration_ms
        completed = [name for name in STAGES if name in stage_results]
        checkpoint = {
            "completed_stages": completed,
            "stage_results": stage_results,
            "stage_timings_ms": stage_timings_ms,
        }
        job.checkpoint_json = checkpoint
        generation_context = dict(run.generation_context or {})
        generation_context["checkpoints"] = checkpoint
        if stage == "content_generation":
            run.draft_content_md = result.get("content_md")
            usage = dict(run.usage_json or {})
            usage["generator"] = result.get("usage", {})
            run.usage_json = usage
        if stage == "web_search":
            generation_context["web_search"] = result
        if stage == "illustration":
            generation_context["illustration"] = result.get("execution")
        warnings = list(generation_context.get("warnings", []))
        for warning in result.get("warnings", []):
            if warning not in warnings:
                warnings.append(warning)
        generation_context["warnings"] = warnings
        run.generation_context = generation_context
        next_index = STAGES.index(stage) + 1
        run.active_stage = STAGES[next_index] if next_index < len(STAGES) else "persist"
        await session.commit()


async def database_pipeline_context(
    job: WorkflowJob,
    *,
    handlers: Mapping[str, StageHandler],
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> PipelineContext:
    if job.run_id is None:
        raise PipelineWriteRejected("pipeline job has no Run")
    async with session_factory() as session:
        run = await session.scalar(
            select(ReportGenerationRun).where(
                ReportGenerationRun.id == job.run_id,
                ReportGenerationRun.state == "generating",
                ReportGenerationRun.generation_job_id == job.id,
            )
        )
        stored_job = await session.get(WorkflowJob, job.id)
        if run is None or run.execution_plan is None or stored_job is None:
            raise PipelineWriteRejected("run is cancelled or generation job is stale")
        checkpoint = stored_job.checkpoint_json or {}
        checkpoints = dict(checkpoint.get("stage_results", {}))
        stage_timings_ms = {
            str(stage): int(duration)
            for stage, duration in dict(
                checkpoint.get("stage_timings_ms", {})
            ).items()
        }
        execution_plan = ReportExecutionPlan.model_validate(run.execution_plan)
        expected_lease_owner = stored_job.lease_owner

    async def assert_current() -> None:
        await _assert_database_current(
            session_factory,
            run_id=job.run_id,
            job_id=job.id,
            lease_owner=expected_lease_owner,
        )

    async def save(stage: str, result: StageResult, duration_ms: int) -> None:
        await _save_database_checkpoint(
            session_factory,
            run_id=job.run_id,
            job_id=job.id,
            lease_owner=expected_lease_owner,
            stage=stage,
            result=result,
            duration_ms=duration_ms,
        )

    return PipelineContext(
        run_id=job.run_id,
        job_id=job.id,
        execution_plan=execution_plan,
        handlers=handlers,
        checkpoints=checkpoints,
        stage_timings_ms=stage_timings_ms,
        assert_current_callback=assert_current,
        save_checkpoint_callback=save,
    )


def _collect_sensitive_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value] if 2 <= len(value) <= 500 else []
    if isinstance(value, dict):
        return [
            item
            for child in value.values()
            for item in _collect_sensitive_strings(child)
        ]
    if isinstance(value, list):
        return [
            item
            for child in value
            for item in _collect_sensitive_strings(child)
        ]
    return []


def _report_seed(run_id: str) -> int:
    return int(hashlib.sha256(run_id.encode()).hexdigest()[:8], 16)


def _resolved_illustration_prompt(
    *,
    plan: ReportExecutionPlan,
    model_prompt: str | None,
) -> str | None:
    if plan.illustration_policy == "none":
        return None
    if model_prompt and model_prompt.strip():
        return model_prompt.strip()
    family = plan.base_family.replace("_", " ")
    return (
        f"Editorial abstract cover illustration for a {family} report. "
        "Calm layered geometric forms, tactile paper texture, balanced negative "
        "space, refined contemporary editorial art. No typography or identifiable "
        "people."
    )


async def wait_for_illustration_result(
    *,
    job_id: str,
    timeout_seconds: float,
    poll_seconds: float = 0.25,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> dict[str, str]:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + max(0.0, timeout_seconds)
    while True:
        async with session_factory() as session:
            job = await session.get(WorkflowJob, job_id)
            if job is None:
                return {"status": "failed", "job_id": job_id}
            checkpoint = dict(job.checkpoint_json or {})
            file_id = str(checkpoint.get("file_id") or "")
            if file_id:
                return {
                    "status": "ready",
                    "job_id": job_id,
                    "file_id": file_id,
                }
            if job.status in {"failed", "cancelled"}:
                return {"status": "failed", "job_id": job_id}
        remaining = deadline - loop.time()
        if remaining <= 0:
            return {"status": "pending", "job_id": job_id}
        await asyncio.sleep(min(poll_seconds, remaining))


def build_pipeline_handlers(
    *,
    job: WorkflowJob,
    generator: ReportGeneratorProvider,
    web_search: WebSearchProvider,
    illustration: IllustrationProvider,
    registry: TemplateRegistry,
    storage: Storage,
    optional_illustration_timeout_seconds: float = 30.0,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> dict[str, StageHandler]:
    async def load_evidence_stage(context: PipelineContext) -> StageResult:
        async with session_factory() as session:
            run = await session.get(ReportGenerationRun, context.run_id)
            if run is None:
                raise PipelineWriteRejected("Run disappeared")
            bundle = await load_latest_evidence(
                session,
                run=run,
                execution_plan=context.execution_plan,
                registry=registry,
                timezone_name=get_settings().default_user_timezone,
            )
        return bundle.model_dump(mode="json", by_alias=True)

    async def web_search_stage(context: PipelineContext) -> StageResult:
        queries = build_web_queries(
            context.execution_plan.public_research_brief
        )
        execution = await execute_web_search(
            policy=context.execution_plan.web_policy,
            provider=web_search,
            queries=queries,
        )
        if context.execution_plan.web_policy != "none":
            metrics.increment("web_search_count", float(len(queries)))
        if execution.status == "failed_degraded":
            metrics.increment("web_search_degraded_total")
        return execution.model_dump(mode="json")

    async def content_generation_stage(context: PipelineContext) -> StageResult:
        package = registry.get(
            context.execution_plan.template_id,
            context.execution_plan.template_version,
        )
        web_result = context.checkpoints["web_search"]
        request = GeneratorRequest(
            execution_plan=context.execution_plan,
            evidence_bundle=context.checkpoints["load_evidence"],
            template_skill=package.skill_markdown,
            external_sources=web_result.get("sources", []),
        )
        result = validate_generator_result(
            await generator.generate(request),
            request=request,
        )
        return result.model_dump(mode="json")

    async def chart_validation_stage(context: PipelineContext) -> StageResult:
        content = context.checkpoints["content_generation"]
        evidence = context.checkpoints["load_evidence"]
        svgs: dict[str, str] = {}
        warnings = []
        for raw in content.get("chart_directives", []):
            directive = ChartDirective.model_validate(raw)
            rendered = render_chart(directive, evidence=evidence)
            warnings.extend(rendered.warnings)
            if rendered.svg is not None:
                svgs[directive.id] = rendered.svg
        return {"svgs": svgs, "warnings": warnings}

    async def illustration_stage(context: PipelineContext) -> StageResult:
        content = context.checkpoints["content_generation"]
        evidence = context.checkpoints["load_evidence"]
        policy = context.execution_plan.illustration_policy
        if policy == "none":
            return {
                "status": "not_required",
                "execution": {
                    "policy": policy,
                    "status": "not_requested",
                    "sources": [],
                    "file_ids": [],
                },
                "file_id": None,
                "job_id": None,
                "warnings": [],
            }
        prompt = sanitize_illustration_prompt(
            _resolved_illustration_prompt(
                plan=context.execution_plan,
                model_prompt=content.get("illustration_prompt"),
            )
            or "",
            sensitive_values=_collect_sensitive_strings(evidence),
        )
        if not prompt:
            metrics.increment("image_degraded_total")
            return {
                "status": "failed",
                "execution": {
                    "policy": policy,
                    "status": "failed_degraded",
                    "sources": [],
                    "file_ids": [],
                },
                "file_id": None,
                "job_id": None,
                "warnings": ["illustration prompt was removed by safety policy"],
            }
        async with session_factory() as session:
            run = await session.get(ReportGenerationRun, context.run_id)
            if run is None or run.state != "generating":
                raise PipelineWriteRejected("Run is no longer generating")
            child = await enqueue_report_illustration(
                session,
                run=run,
                parent_job_id=context.job_id,
                prompt=prompt,
                policy=policy,
            )
            child_id = child.id
            await session.commit()
        metrics.increment("image_generation_count")
        result = await wait_for_illustration_result(
            job_id=child_id,
            timeout_seconds=optional_illustration_timeout_seconds,
            session_factory=session_factory,
        )
        status = result["status"]
        file_id = result.get("file_id")
        execution_status = {
            "ready": "succeeded",
            "pending": "pending",
            "failed": "failed_degraded",
        }[status]
        warnings = []
        if status == "pending":
            warnings.append("illustration continues in background")
        elif status == "failed":
            metrics.increment("image_degraded_total")
            warnings.append("illustration generation failed")
        return {
            "status": status,
            "execution": {
                "policy": policy,
                "status": execution_status,
                "sources": [],
                "file_ids": [file_id] if file_id else [],
            },
            "file_id": file_id,
            "job_id": child_id,
            "warnings": warnings,
        }

    async def html_render_stage(context: PipelineContext) -> StageResult:
        started = perf_counter()
        content = context.checkpoints["content_generation"]
        charts = context.checkpoints["chart_validation"]
        illustration_result = context.checkpoints["illustration"]
        web_result = context.checkpoints["web_search"]
        normalized = normalize_report_content(
            content_md=content["content_md"],
            allowed_evidence_ids=list(
                dict.fromkeys(
                    [
                        *(
                            reference.id
                            for reference in context.execution_plan.resolved_references
                        ),
                        *context.execution_plan.resolved_asset_ids,
                    ]
                )
            ),
            allowed_asset_ids=context.execution_plan.resolved_asset_ids,
            external_sources=web_result.get("sources", []),
            suggested_actions=[
                GeneratedSuggestedAction.model_validate(item)
                for item in content.get("suggested_actions", [])
            ],
        )
        file_id = illustration_result.get("file_id")
        media_urls = {file_id: f"/api/files/{file_id}"} if file_id else {}
        title = content["share_card_spec"]["headline"]
        presentation = render_report_presentation(
            title=title,
            content_md=normalized.content_md,
            chart_svgs=charts.get("svgs", {}),
            media_urls=media_urls,
            base_family=context.execution_plan.base_family,
            seed=_report_seed(context.run_id),
            external_sources=normalized.used_external_sources,
            suggested_actions=normalized.suggested_actions,
            illustration_file_id=file_id,
            illustration_status=illustration_result.get(
                "status", "not_required"
            ),
        )
        metrics.observe("render_duration_ms", (perf_counter() - started) * 1000)
        return {
            "title": title,
            "content_md": normalized.content_md,
            "citations": [
                item.model_dump(mode="json") for item in normalized.citations
            ],
            "suggested_actions": [
                item.model_dump(mode="json")
                for item in normalized.suggested_actions
            ],
            "external_sources": normalized.used_external_sources,
            "html": presentation.html,
            "surface": presentation.surface,
            "palette": presentation.palette,
            "color_scheme": presentation.color_scheme,
            "warnings": presentation.warnings,
        }

    async def persist_stage(context: PipelineContext) -> StageResult:
        from app.domains.reports.service import (
            CompletedReportData,
            PersistRejected,
            persist_completed_report,
        )

        evidence = context.checkpoints["load_evidence"]
        web_result = context.checkpoints["web_search"]
        content = context.checkpoints["content_generation"]
        illustration_result = context.checkpoints["illustration"]
        rendered = context.checkpoints["html_render"]
        file_id = illustration_result.get("file_id")
        seed = _report_seed(context.run_id)
        spec = ReportSpec(
            template_id=context.execution_plan.template_id,
            template_version=context.execution_plan.template_version,
            base_family=context.execution_plan.base_family,
            source_asset_ids=[
                asset_id
                for item in evidence.get("user_evidence", [])
                if isinstance(item, dict)
                and isinstance((asset_id := item.get("asset_id")), str)
                and asset_id
            ],
            unavailable_asset_ids=evidence.get("unavailable_asset_ids", []),
            field_bindings=context.execution_plan.field_bindings,
            time_range=context.execution_plan.time_range,
            external_sources=rendered.get("external_sources", []),
            web_policy=context.execution_plan.web_policy,
            generated_file_ids=[file_id] if file_id else [],
            surface=rendered["surface"],
            palette=rendered["palette"],
            seed=seed,
            citations=rendered.get("citations", []),
            suggested_actions=rendered.get("suggested_actions", []),
            presentation_version="report_html_v2",
        )
        usage = content.get("usage", {})
        try:
            async with session_factory() as session:
                report = await persist_completed_report(
                    session,
                    run_id=context.run_id,
                    job_id=context.job_id,
                    lease_owner=job.lease_owner,
                    data=CompletedReportData(
                        title=rendered["title"],
                        content_md=rendered["content_md"],
                        html=rendered["html"],
                        spec_json=spec,
                        share_card_spec=content["share_card_spec"],
                        tokens_used=int(usage.get("input_tokens", 0))
                        + int(usage.get("output_tokens", 0)),
                        gen_ms=sum(context.stage_timings_ms.values()),
                        illustration_status=illustration_result.get(
                            "status", "not_required"
                        ),
                        illustration_job_id=illustration_result.get("job_id"),
                    ),
                )
                await session.commit()
        except PersistRejected as exc:
            raise PipelineWriteRejected(str(exc)) from exc
        return {"report_id": report.id}

    return {
        "load_evidence": load_evidence_stage,
        "web_search": web_search_stage,
        "content_generation": content_generation_stage,
        "chart_validation": chart_validation_stage,
        "illustration": illustration_stage,
        "html_render": html_render_stage,
        "persist": persist_stage,
    }


def report_pipeline_handler(
    *,
    generator: ReportGeneratorProvider,
    web_search: WebSearchProvider,
    illustration: IllustrationProvider,
    registry: TemplateRegistry,
    storage: Storage,
    optional_illustration_timeout_seconds: float = 30.0,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> Callable[[WorkflowJob], Awaitable[None]]:
    async def handle(job: WorkflowJob) -> None:
        started = perf_counter()
        outcome: float | None = None
        handlers = build_pipeline_handlers(
            job=job,
            generator=generator,
            web_search=web_search,
            illustration=illustration,
            registry=registry,
            storage=storage,
            optional_illustration_timeout_seconds=(
                optional_illustration_timeout_seconds
            ),
            session_factory=session_factory,
        )
        try:
            context = await database_pipeline_context(
                job,
                handlers=handlers,
                session_factory=session_factory,
            )
            await execute_report_job(context)
            outcome = 1.0
        except PipelineWriteRejected:
            return
        except (InsufficientEvidence, PermanentProviderError, ValueError) as exc:
            from app.domains.reports.service import record_report_failure

            failure_stage = "load_evidence"
            try:
                failure_stage = STAGES[context.resume_index]
            except (UnboundLocalError, IndexError):
                pass
            logger.exception(
                "report pipeline failed run_id=%s job_id=%s stage=%s error_type=%s",
                job.run_id,
                job.id,
                failure_stage,
                type(exc).__name__,
            )
            async with session_factory() as session:
                await record_report_failure(
                    session,
                    run_id=job.run_id or "",
                    job_id=job.id,
                    lease_owner=job.lease_owner,
                    failure_stage=failure_stage,
                    error_code=type(exc).__name__,
                    error_message="报告生成未能继续，请重试。",
                    retry_from=failure_stage,
                )
                await session.commit()
            outcome = 0.0
        except RetryableProviderError:
            outcome = 0.0
            raise
        finally:
            metrics.observe("pipeline_duration_ms", (perf_counter() - started) * 1000)
            if outcome is not None:
                metrics.observe("pipeline_success_rate", outcome)

    return handle
