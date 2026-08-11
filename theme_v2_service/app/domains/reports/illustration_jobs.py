from __future__ import annotations

from collections.abc import Awaitable, Callable
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.models import File, Report, ReportGenerationRun
from app.domains.reports.providers import IllustrationProvider
from app.domains.reports.providers_image import sanitize_illustration_prompt
from app.domains.reports.storage import Storage, persist_owned_file
from app.domains.reports.rendering import (
    remove_pending_illustration_slot,
    replace_pending_illustration_slot,
)
from app.domains.reports.state_machine import transition_run
from app.jobs.models import JobDeferred, JobPermanentFailure
from app.jobs.queue import defer_job, enqueue_job


REPORT_ILLUSTRATION_JOB_TYPE = "report_illustration"


def _image_extension(mime_type: str) -> str:
    return {
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/webp": "webp",
        "image/gif": "gif",
    }.get(mime_type, "bin")


async def enqueue_report_illustration(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
    parent_job_id: str,
    prompt: str,
    policy: str,
) -> WorkflowJob:
    job = await enqueue_job(
        session,
        run_id=run.id,
        job_type=REPORT_ILLUSTRATION_JOB_TYPE,
        dedupe_key=f"report-illustration:{run.id}:{parent_job_id}",
        max_attempts=get_settings().report_provider_max_attempts,
    )
    if not job.checkpoint_json:
        job.checkpoint_json = {
            "phase": "queued",
            "prompt": prompt,
            "policy": policy,
            "parent_job_id": parent_job_id,
        }
        await session.flush()
    return job


async def _current_job_and_run(
    session: AsyncSession,
    *,
    job: WorkflowJob,
    lock: bool,
) -> tuple[WorkflowJob, ReportGenerationRun]:
    query = select(WorkflowJob).where(
        WorkflowJob.id == job.id,
        WorkflowJob.run_id == job.run_id,
        WorkflowJob.status == "running",
    )
    if job.lease_owner is not None:
        query = query.where(WorkflowJob.lease_owner == job.lease_owner)
    if lock:
        query = query.with_for_update()
    stored_job = await session.scalar(query)
    run = await session.get(ReportGenerationRun, job.run_id)
    if stored_job is None or run is None:
        raise JobPermanentFailure("stale_illustration_job", "插图任务已失效")
    return stored_job, run


async def attach_ready_illustration(
    session: AsyncSession,
    *,
    job: WorkflowJob,
    file_id: str,
    now: datetime,
) -> bool:
    report = await session.scalar(
        select(Report)
        .where(Report.generation_run_id == job.run_id)
        .with_for_update()
    )
    if report is None:
        return False
    if report.illustration_job_id != job.id:
        raise JobPermanentFailure(
            "illustration_job_mismatch",
            "插图任务与报告不匹配",
        )
    if report.illustration_status == "ready":
        return True
    if report.illustration_status != "pending" or not report.html:
        raise JobPermanentFailure(
            "illustration_report_not_pending",
            "报告不再等待此插图",
        )
    run = await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == job.run_id,
            ReportGenerationRun.report_id == report.id,
            ReportGenerationRun.state == "illustration_pending",
        )
        .with_for_update()
    )
    file = await session.scalar(
        select(File).where(File.id == file_id, File.user_id == report.user_id)
    )
    if run is None or file is None or not file.mime_type.startswith("image/"):
        raise JobPermanentFailure(
            "illustration_attachment_invalid",
            "插图附件无法验证",
        )
    report.html = replace_pending_illustration_slot(
        report.html,
        f"/api/files/{file.id}",
    )
    spec = dict(report.spec_json or {})
    generated_file_ids = [
        value
        for value in spec.get("generated_file_ids", [])
        if isinstance(value, str) and value
    ]
    if file.id not in generated_file_ids:
        generated_file_ids.append(file.id)
    spec["generated_file_ids"] = generated_file_ids
    report.spec_json = spec
    share_card = dict(report.share_card_spec or {})
    share_card["illustration_file_id"] = file.id
    report.share_card_spec = share_card
    report.illustration_status = "ready"
    report.revision = int(report.revision or 1) + 1
    report.updated_at = now
    generation_context = dict(run.generation_context or {})
    generation_context["illustration"] = {
        "policy": str((job.checkpoint_json or {}).get("policy") or "optional"),
        "status": "succeeded",
        "sources": [],
        "file_ids": [file.id],
    }
    run.generation_context = generation_context
    transition_run(run, "completed", now=now)
    return True


async def mark_illustration_failed(
    session: AsyncSession,
    *,
    job: WorkflowJob,
    error_code: str,
    now: datetime,
) -> bool:
    report = await session.scalar(
        select(Report)
        .where(
            Report.generation_run_id == job.run_id,
            Report.illustration_job_id == job.id,
            Report.illustration_status == "pending",
        )
        .with_for_update()
    )
    if report is None:
        return False
    run = await session.scalar(
        select(ReportGenerationRun)
        .where(
            ReportGenerationRun.id == job.run_id,
            ReportGenerationRun.report_id == report.id,
            ReportGenerationRun.state == "illustration_pending",
        )
        .with_for_update()
    )
    if run is None or not report.html:
        return False
    report.html = remove_pending_illustration_slot(report.html)
    report.illustration_status = "failed"
    report.revision = int(report.revision or 1) + 1
    report.updated_at = now
    generation_context = dict(run.generation_context or {})
    generation_context["illustration"] = {
        "policy": str((job.checkpoint_json or {}).get("policy") or "optional"),
        "status": "failed_degraded",
        "sources": [],
        "file_ids": [],
        "error_code": error_code,
    }
    run.generation_context = generation_context
    transition_run(run, "completed", now=now)
    return True


async def execute_report_illustration_job(
    job: WorkflowJob,
    *,
    provider: IllustrationProvider,
    storage: Storage,
    now: datetime | None = None,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> None:
    current_time = now or utc_now()
    async with session_factory() as session:
        stored_job, run = await _current_job_and_run(
            session,
            job=job,
            lock=False,
        )
        checkpoint = dict(stored_job.checkpoint_json or {})
        user_id = run.user_id
        run_id = run.id

    file_id = str(checkpoint.get("file_id") or "")
    if not file_id:
        raw_prompt = str(checkpoint.get("prompt") or "")
        prompt = sanitize_illustration_prompt(raw_prompt)
        if not prompt:
            raise JobPermanentFailure(
                "unsafe_illustration_prompt",
                "插图提示未通过安全检查",
            )
        image = await provider.generate(prompt)
        if not image.mime_type.startswith("image/"):
            raise JobPermanentFailure(
                "invalid_illustration_mime",
                "插图服务返回了无效格式",
            )
        extension = _image_extension(image.mime_type)
        async with session_factory() as session:
            async with session.begin():
                stored_job, _ = await _current_job_and_run(
                    session,
                    job=job,
                    lock=True,
                )
                file = await persist_owned_file(
                    session,
                    storage=storage,
                    user_id=user_id,
                    purpose="report_illustration",
                    key=(
                        f"reports/{user_id}/{run_id}/"
                        f"illustration-{job.id}.{extension}"
                    ),
                    content=image.data,
                    mime_type=image.mime_type,
                )
                file_id = file.id
                checkpoint = {
                    **checkpoint,
                    "phase": "stored",
                    "file_id": file_id,
                    "mime_type": image.mime_type,
                }
                stored_job.checkpoint_json = checkpoint

    deferred = False
    async with session_factory() as session:
        async with session.begin():
            stored_job, _ = await _current_job_and_run(
                session,
                job=job,
                lock=True,
            )
            attached = await attach_ready_illustration(
                session,
                job=stored_job,
                file_id=file_id,
                now=current_time,
            )
            if not attached:
                await defer_job(
                    session,
                    job_id=stored_job.id,
                    owner=stored_job.lease_owner or "",
                    now=current_time,
                    available_at=current_time + timedelta(seconds=1),
                    checkpoint=checkpoint,
                )
                deferred = True
            else:
                stored_job.checkpoint_json = {
                    **checkpoint,
                    "phase": "attached",
                }
    if deferred:
        raise JobDeferred()


def report_illustration_handler(
    *,
    provider: IllustrationProvider,
    storage: Storage,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> Callable[[WorkflowJob], Awaitable[None]]:
    async def handle(job: WorkflowJob) -> None:
        try:
            await execute_report_illustration_job(
                job,
                provider=provider,
                storage=storage,
                session_factory=session_factory,
            )
        except JobDeferred:
            raise
        except Exception as exc:
            terminal = isinstance(exc, JobPermanentFailure) or (
                job.attempt >= job.max_attempts
            )
            if terminal:
                async with session_factory() as session:
                    async with session.begin():
                        await mark_illustration_failed(
                            session,
                            job=job,
                            error_code=(
                                exc.error_code
                                if isinstance(exc, JobPermanentFailure)
                                else type(exc).__name__
                            ),
                            now=utc_now(),
                        )
            raise

    return handle
