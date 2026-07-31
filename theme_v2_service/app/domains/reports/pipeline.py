from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import ReportExecutionPlan


STAGES = (
    "load_evidence",
    "web_search",
    "content_generation",
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
