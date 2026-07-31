from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass, field
import hashlib
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.charts import ChartDirective, render_chart
from app.domains.reports.evidence import InsufficientEvidence, load_latest_evidence
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.providers import (
    GeneratorRequest,
    IllustrationProvider,
    PermanentProviderError,
    ReportGeneratorProvider,
    RetryableProviderError,
    WebSearchProvider,
)
from app.domains.reports.rendering import (
    generate_optional_illustration,
    render_report_html,
)
from app.domains.reports.schemas import ReportExecutionPlan, ReportSpec
from app.domains.reports.security import validate_generator_result
from app.domains.reports.storage import Storage, persist_owned_file
from app.domains.reports.templates import TemplateRegistry
from app.domains.reports.web_search import build_web_queries, execute_web_search


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
SaveCheckpoint = Callable[[str, StageResult], Awaitable[None]]


class PipelineWriteRejected(RuntimeError):
    pass


@dataclass
class PipelineContext:
    run_id: str
    job_id: str
    execution_plan: ReportExecutionPlan | dict
    handlers: Mapping[str, StageHandler]
    checkpoints: dict[str, StageResult] = field(default_factory=dict)
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

    async def save_checkpoint(self, stage: str, result: StageResult) -> None:
        if self.save_checkpoint_callback is not None:
            await self.save_checkpoint_callback(stage, result)
        self.checkpoints[stage] = result


async def execute_report_job(context: PipelineContext) -> None:
    missing = set(STAGES).difference(context.handlers)
    if missing:
        raise ValueError(f"missing pipeline handlers: {sorted(missing)}")
    for stage in STAGES[context.resume_index :]:
        await context.assert_current_and_not_cancelled()
        result = await context.handlers[stage](context)
        if stage == "persist":
            # Persist owns the final Report/Run/Job/Notification transaction and
            # writes its own terminal checkpoint.
            context.checkpoints[stage] = result
        else:
            await context.save_checkpoint(stage, result)


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
        completed = [name for name in STAGES if name in stage_results]
        checkpoint = {
            "completed_stages": completed,
            "stage_results": stage_results,
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
        execution_plan = ReportExecutionPlan.model_validate(run.execution_plan)
        expected_lease_owner = stored_job.lease_owner

    async def assert_current() -> None:
        await _assert_database_current(
            session_factory,
            run_id=job.run_id,
            job_id=job.id,
            lease_owner=expected_lease_owner,
        )

    async def save(stage: str, result: StageResult) -> None:
        await _save_database_checkpoint(
            session_factory,
            run_id=job.run_id,
            job_id=job.id,
            lease_owner=expected_lease_owner,
            stage=stage,
            result=result,
        )

    return PipelineContext(
        run_id=job.run_id,
        job_id=job.id,
        execution_plan=execution_plan,
        handlers=handlers,
        checkpoints=checkpoints,
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


def _image_extension(mime_type: str) -> str:
    return {
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/webp": "webp",
        "image/gif": "gif",
    }.get(mime_type, "bin")


def build_pipeline_handlers(
    *,
    job: WorkflowJob,
    generator: ReportGeneratorProvider,
    web_search: WebSearchProvider,
    illustration: IllustrationProvider,
    registry: TemplateRegistry,
    storage: Storage,
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
            )
        return bundle.model_dump(mode="json", by_alias=True)

    async def web_search_stage(context: PipelineContext) -> StageResult:
        package = registry.get(
            context.execution_plan.template_id,
            context.execution_plan.template_version,
        )
        evidence = context.checkpoints["load_evidence"]
        queries = build_web_queries(
            report_goal=context.execution_plan.report_goal,
            capabilities=set(package.manifest.data_fit),
            time_range=context.execution_plan.time_range,
            aggregate_terms=[],
            sensitive_values=_collect_sensitive_strings(evidence),
        )
        execution = await execute_web_search(
            policy=context.execution_plan.web_policy,
            provider=web_search,
            queries=queries,
        )
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

        async def store_image(image) -> str:
            async with session_factory() as session:
                run = await session.get(ReportGenerationRun, context.run_id)
                if run is None or run.state != "generating":
                    raise PipelineWriteRejected("Run is no longer generating")
                extension = _image_extension(image.mime_type)
                file = await persist_owned_file(
                    session,
                    storage=storage,
                    user_id=run.user_id,
                    purpose="report_illustration",
                    key=(
                        f"reports/{run.user_id}/{run.id}/"
                        f"illustration-{context.job_id}.{extension}"
                    ),
                    content=image.data,
                    mime_type=image.mime_type,
                )
                await session.commit()
                return file.id

        outcome = await generate_optional_illustration(
            policy=context.execution_plan.illustration_policy,
            prompt=content.get("illustration_prompt"),
            provider=illustration,
            store_image=store_image,
            sensitive_values=_collect_sensitive_strings(evidence),
        )
        return {
            "execution": outcome.execution.model_dump(mode="json"),
            "file_id": outcome.file_id,
            "warnings": outcome.warnings,
        }

    async def html_render_stage(context: PipelineContext) -> StageResult:
        content = context.checkpoints["content_generation"]
        charts = context.checkpoints["chart_validation"]
        illustration_result = context.checkpoints["illustration"]
        file_id = illustration_result.get("file_id")
        media_urls = {file_id: f"/api/files/{file_id}"} if file_id else {}
        title = content["share_card_spec"]["headline"]
        html = render_report_html(
            title=title,
            content_md=content["content_md"],
            chart_svgs=charts.get("svgs", {}),
            media_urls=media_urls,
        )
        return {"title": title, "html": html}

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
        seed = int(hashlib.sha256(context.run_id.encode()).hexdigest()[:8], 16)
        spec = ReportSpec(
            template_id=context.execution_plan.template_id,
            template_version=context.execution_plan.template_version,
            base_family=context.execution_plan.base_family,
            source_asset_ids=[
                item["asset_id"] for item in evidence.get("user_evidence", [])
            ],
            unavailable_asset_ids=evidence.get("unavailable_asset_ids", []),
            field_bindings=context.execution_plan.field_bindings,
            time_range=context.execution_plan.time_range,
            external_sources=web_result.get("sources", []),
            web_policy=context.execution_plan.web_policy,
            generated_file_ids=[file_id] if file_id else [],
            seed=seed,
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
                        content_md=content["content_md"],
                        html=rendered["html"],
                        spec_json=spec,
                        share_card_spec=content["share_card_spec"],
                        tokens_used=int(usage.get("input_tokens", 0))
                        + int(usage.get("output_tokens", 0)),
                        gen_ms=0,
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
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> Callable[[WorkflowJob], Awaitable[None]]:
    async def handle(job: WorkflowJob) -> None:
        handlers = build_pipeline_handlers(
            job=job,
            generator=generator,
            web_search=web_search,
            illustration=illustration,
            registry=registry,
            storage=storage,
            session_factory=session_factory,
        )
        try:
            context = await database_pipeline_context(
                job,
                handlers=handlers,
                session_factory=session_factory,
            )
            await execute_report_job(context)
        except PipelineWriteRejected:
            return
        except (InsufficientEvidence, PermanentProviderError, ValueError) as exc:
            from app.domains.reports.service import record_report_failure

            failure_stage = "load_evidence"
            try:
                failure_stage = STAGES[context.resume_index]
            except (UnboundLocalError, IndexError):
                pass
            async with session_factory() as session:
                await record_report_failure(
                    session,
                    run_id=job.run_id or "",
                    job_id=job.id,
                    lease_owner=job.lease_owner,
                    failure_stage=failure_stage,
                    error_code=type(exc).__name__,
                    error_message="Report generation could not continue",
                    retry_from=failure_stage,
                )
                await session.commit()
        except RetryableProviderError:
            raise

    return handle
