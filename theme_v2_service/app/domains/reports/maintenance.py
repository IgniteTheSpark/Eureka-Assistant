import asyncio
import hashlib
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.reports.models import File, Report, ReportGenerationRun, ReportShare
from app.domains.reports.normalization import normalize_report_content
from app.domains.reports.providers import GeneratedSuggestedAction
from app.domains.reports.rendering import render_report_presentation
from app.domains.reports.state_machine import transition_run
from app.observability import metrics, sanitize_log_context


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ReportMaintenanceResult:
    expired_runs: int = 0
    failed_runs: int = 0
    expired_shares: int = 0


@dataclass(frozen=True)
class ReportRepairResult:
    eligible: int = 0
    repaired: int = 0
    skipped_unsafe: int = 0


_SAFE_CHART_ID = re.compile(r"^[A-Za-z0-9_-]+$")


def _stage_results(job: WorkflowJob | None) -> dict:
    if job is None or not isinstance(job.checkpoint_json, dict):
        return {}
    results = job.checkpoint_json.get("stage_results")
    return results if isinstance(results, dict) else {}


def _external_sources(spec: dict, stages: dict) -> list[dict]:
    raw = spec.get("external_sources")
    if not isinstance(raw, list):
        web = stages.get("web_search")
        raw = web.get("sources") if isinstance(web, dict) else []
    return [item for item in raw if isinstance(item, dict)]


def _stored_actions(spec: dict, stages: dict) -> list[GeneratedSuggestedAction]:
    raw = spec.get("suggested_actions")
    if not isinstance(raw, list):
        content = stages.get("content_generation")
        raw = content.get("suggested_actions") if isinstance(content, dict) else []
    actions: list[GeneratedSuggestedAction] = []
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError("invalid stored report action")
        actions.append(
            GeneratedSuggestedAction.model_validate(
                {"title": item.get("title"), "due_at": item.get("due_at")}
            )
        )
    return actions


def _stored_chart_svgs(stages: dict) -> dict[str, str]:
    checkpoint = stages.get("chart_validation")
    raw = checkpoint.get("svgs") if isinstance(checkpoint, dict) else {}
    if not isinstance(raw, dict):
        return {}
    trusted: dict[str, str] = {}
    for raw_id, raw_svg in raw.items():
        chart_id = str(raw_id)
        if not _SAFE_CHART_ID.fullmatch(chart_id) or not isinstance(raw_svg, str):
            continue
        folded = raw_svg.casefold()
        if (
            not folded.lstrip().startswith("<svg ")
            or "<script" in folded
            or "<foreignobject" in folded
            or " onload=" in folded
            or " javascript:" in folded
        ):
            continue
        trusted[chart_id] = raw_svg
    return trusted


def _repair_seed(run_id: str, spec: dict) -> int:
    raw = spec.get("seed")
    if isinstance(raw, int) and not isinstance(raw, bool):
        return raw
    return int(hashlib.sha256(run_id.encode()).hexdigest()[:8], 16)


async def _owned_illustration_file_id(
    session: AsyncSession,
    *,
    report: Report,
    spec: dict,
    stages: dict,
) -> str | None:
    candidates: list[str] = []
    share_card = report.share_card_spec if isinstance(report.share_card_spec, dict) else {}
    illustration = stages.get("illustration")
    raw_candidates = [
        share_card.get("illustration_file_id"),
        illustration.get("file_id") if isinstance(illustration, dict) else None,
        *(spec.get("generated_file_ids") or []),
    ]
    for value in raw_candidates:
        if isinstance(value, str) and value and value not in candidates:
            candidates.append(value)
    if not candidates:
        return None
    return await session.scalar(
        select(File.id)
        .where(
            File.id.in_(candidates),
            File.user_id == report.user_id,
            File.purpose == "report_illustration",
        )
        .order_by(File.id)
        .limit(1)
    )


async def repair_report_presentations(
    session: AsyncSession,
    *,
    dry_run: bool,
    limit: int = 100,
) -> ReportRepairResult:
    if limit < 1:
        return ReportRepairResult()
    version = Report.spec_json["presentation_version"].as_string()
    marker_text = func.lower(func.coalesce(Report.content_md, ""))
    marker_html = func.lower(func.coalesce(Report.html, ""))
    rows = list(
        (
            await session.execute(
                select(Report, ReportGenerationRun)
                .join(
                    ReportGenerationRun,
                    ReportGenerationRun.id == Report.generation_run_id,
                )
                .where(
                    or_(
                        marker_text.like("%[evidence:%"),
                        marker_text.like("%[source:%"),
                        marker_html.like("%[evidence:%"),
                        marker_html.like("%[source:%"),
                        version.is_(None),
                        version != "report_html_v2",
                    )
                )
                .order_by(Report.id)
                .with_for_update(skip_locked=True)
                .limit(limit)
            )
        ).all()
    )
    repaired = 0
    skipped_unsafe = 0
    for report, run in rows:
        job = (
            await session.get(WorkflowJob, run.generation_job_id)
            if run.generation_job_id
            else None
        )
        stages = _stage_results(job)
        spec = dict(report.spec_json or {})
        external_sources = _external_sources(spec, stages)
        allowed_asset_ids = list(
            dict.fromkeys(
                [
                    *(
                        spec.get("source_asset_ids")
                        if isinstance(spec.get("source_asset_ids"), list)
                        else []
                    ),
                    *(run.resolved_asset_ids or []),
                ]
            )
        )
        try:
            normalized = normalize_report_content(
                content_md=report.content_md,
                allowed_asset_ids=allowed_asset_ids,
                external_sources=external_sources,
                suggested_actions=_stored_actions(spec, stages),
            )
            illustration_file_id = await _owned_illustration_file_id(
                session,
                report=report,
                spec=spec,
                stages=stages,
            )
            seed = _repair_seed(run.id, spec)
            presentation = render_report_presentation(
                title=report.title,
                content_md=normalized.content_md,
                chart_svgs=_stored_chart_svgs(stages),
                media_urls=(
                    {illustration_file_id: f"/api/files/{illustration_file_id}"}
                    if illustration_file_id
                    else {}
                ),
                base_family=report.base_family,
                seed=seed,
                external_sources=normalized.used_external_sources,
                suggested_actions=normalized.suggested_actions,
                illustration_file_id=illustration_file_id,
            )
        except (TypeError, ValueError):
            skipped_unsafe += 1
            logger.warning(
                "report presentation repair skipped",
                extra=sanitize_log_context(error_code="unsafe_stored_report"),
            )
            continue
        repaired += 1
        if dry_run:
            continue
        generated_file_ids = [
            item
            for item in spec.get("generated_file_ids", [])
            if isinstance(item, str) and item
        ]
        if illustration_file_id and illustration_file_id not in generated_file_ids:
            generated_file_ids.append(illustration_file_id)
        spec.update(
            {
                "template_id": spec.get("template_id", report.template_id),
                "template_version": spec.get(
                    "template_version", report.template_version
                ),
                "base_family": report.base_family,
                "source_asset_ids": allowed_asset_ids,
                "external_sources": normalized.used_external_sources,
                "generated_file_ids": generated_file_ids,
                "surface": presentation.surface,
                "palette": presentation.palette,
                "seed": seed,
                "citations": [
                    item.model_dump(mode="json") for item in normalized.citations
                ],
                "suggested_actions": [
                    item.model_dump(mode="json")
                    for item in normalized.suggested_actions
                ],
                "presentation_version": "report_html_v2",
            }
        )
        report.content_md = normalized.content_md
        report.html = presentation.html
        report.spec_json = spec
    if not dry_run:
        await session.flush()
    return ReportRepairResult(
        eligible=len(rows),
        repaired=repaired,
        skipped_unsafe=skipped_unsafe,
    )


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
