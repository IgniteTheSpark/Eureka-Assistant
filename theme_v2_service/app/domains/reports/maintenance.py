import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.reports.models import ReportGenerationRun, ReportShare
from app.domains.reports.state_machine import transition_run
from app.observability import metrics, sanitize_log_context


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ReportMaintenanceResult:
    expired_runs: int = 0
    failed_runs: int = 0
    expired_shares: int = 0


async def _fail_timed_out_run(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
    now: datetime,
) -> None:
    previous_state = run.state
    failure_stage = run.active_stage or previous_state
    retry_from = "planning" if previous_state == "planning" else failure_stage
    run.failure_stage = failure_stage
    run.error_code = "report_run_timeout"
    run.error_message = "Report generation timed out"
    run.retry_from = retry_from
    run.active_stage = None
    transition_run(run, "failed", now=now)

    job_id = run.planner_job_id if previous_state == "planning" else run.generation_job_id
    if job_id:
        job = await session.scalar(
            select(WorkflowJob)
            .where(
                WorkflowJob.id == job_id,
                WorkflowJob.status.in_(("queued", "running")),
            )
            .with_for_update()
        )
        if job is not None:
            job.status = "failed"
            job.error_code = "report_run_timeout"
            job.error_message = "Report generation timed out"
            job.lease_owner = None
            job.lease_expires_at = None
            job.completed_at = now
            job.updated_at = now

    link = f"report-run:{run.id}"
    existing = await session.scalar(
        select(Notification.id).where(
            Notification.user_id == run.user_id,
            Notification.type == "report_failed",
            Notification.link == link,
        )
    )
    if existing is None:
        await create_notification(
            session,
            NotificationCreate(
                user_id=run.user_id,
                type="report_failed",
                title="报告生成超时",
                body="可以从失败阶段重试。",
                link=link,
            ),
        )
    metrics.increment(
        "run_failed_total",
        labels={"failure_stage": failure_stage},
    )


async def run_report_maintenance(
    session: AsyncSession,
    *,
    now: datetime,
    selection_ttl: timedelta = timedelta(days=7),
    planning_timeout: timedelta | None = None,
    generation_timeout: timedelta | None = None,
) -> ReportMaintenanceResult:
    settings = get_settings()
    planning_timeout = planning_timeout or timedelta(
        seconds=settings.report_planning_timeout_seconds
    )
    generation_timeout = generation_timeout or timedelta(
        seconds=settings.report_generation_timeout_seconds
    )

    awaiting = list(
        await session.scalars(
            select(ReportGenerationRun)
            .where(
                ReportGenerationRun.state == "awaiting_selection",
                ReportGenerationRun.updated_at < now - selection_ttl,
            )
            .order_by(ReportGenerationRun.id)
            .with_for_update(skip_locked=True)
            .limit(100)
        )
    )
    for run in awaiting:
        run.active_stage = None
        transition_run(run, "expired", now=now)
        metrics.increment("run_expired_total")

    timed_out = []
    for state, timeout in (
        ("planning", planning_timeout),
        ("generating", generation_timeout),
    ):
        timed_out.extend(
            list(
                await session.scalars(
                    select(ReportGenerationRun)
                    .where(
                        ReportGenerationRun.state == state,
                        ReportGenerationRun.updated_at < now - timeout,
                    )
                    .order_by(ReportGenerationRun.id)
                    .with_for_update(skip_locked=True)
                    .limit(100)
                )
            )
        )
    for run in timed_out:
        await _fail_timed_out_run(session, run=run, now=now)

    expired_shares = list(
        await session.scalars(
            select(ReportShare)
            .where(
                ReportShare.status == "active",
                ReportShare.expires_at.is_not(None),
                ReportShare.expires_at <= now,
            )
            .order_by(ReportShare.id)
            .with_for_update(skip_locked=True)
            .limit(100)
        )
    )
    for share in expired_shares:
        share.status = "expired"
        metrics.increment("share_expired_total")

    await session.flush()
    return ReportMaintenanceResult(
        expired_runs=len(awaiting),
        failed_runs=len(timed_out),
        expired_shares=len(expired_shares),
    )


async def run_report_maintenance_scheduler(
    *,
    stop_event: asyncio.Event,
    interval_seconds: float = 60,
) -> None:
    while not stop_event.is_set():
        try:
            async with AsyncSessionFactory() as session:
                await run_report_maintenance(session, now=utc_now())
                await session.commit()
        except Exception as exc:
            logger.error(
                "report maintenance failed",
                extra=sanitize_log_context(error_code=type(exc).__name__),
            )
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval_seconds)
        except TimeoutError:
            pass
