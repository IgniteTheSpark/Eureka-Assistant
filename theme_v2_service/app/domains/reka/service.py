from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.reka.models import Nudge
from app.domains.reka.overdue import collect_overdue_candidates
from app.domains.reka.rhythm import collect_rhythm_candidates
from app.db.models import Event
from app.domains.reports.models import Report, ReportGenerationRun
from app.domains.triggers.models import TriggerExecution


logger = logging.getLogger(__name__)


class SignalNotFound(Exception):
    pass


class SignalCannotSnooze(Exception):
    pass


class InvalidSnoozeTime(Exception):
    pass


@dataclass(frozen=True)
class _SignalCandidate:
    natural_key: str
    kind: str
    ref: str
    title: str
    body: str
    target_type: str
    target_id: str
    actions: tuple[str, ...]
    expires_at: datetime | None
    rank: tuple
    phase: str | None = None
    chain_id: str | None = None
    evidence: dict | None = None
    report_run_id: str | None = None
    report_id: str | None = None


def _aware_utc(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc)


def _db_time(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return _aware_utc(value).replace(tzinfo=None)


def _rhythm_expiry(*, now: datetime, timezone_name: str, weekly: bool) -> datetime:
    zone = ZoneInfo(timezone_name)
    local_now = _aware_utc(now).astimezone(zone)
    if weekly:
        days_until_next_monday = 7 - local_now.weekday()
        next_cycle = local_now.date() + timedelta(days=days_until_next_monday)
    else:
        next_cycle = local_now.date() + timedelta(days=1)
    return datetime.combine(next_cycle, time.min, tzinfo=zone).astimezone(timezone.utc)


async def _collect_candidates(
    session: AsyncSession,
    *,
    user_id: str,
    now: datetime,
    timezone_name: str,
) -> tuple[list[_SignalCandidate], list[str], set[str]]:
    candidates: list[_SignalCandidate] = []
    failures: list[str] = []
    report_chains: set[str] = set()
    try:
        report_candidates: dict[str, _SignalCandidate] = {}
        report_rows = (
            await session.execute(
                select(TriggerExecution, Event)
                .join(Event, Event.id == TriggerExecution.scope_id)
                .where(
                    TriggerExecution.user_id == user_id,
                    TriggerExecution.trigger_type == "pre_event_report",
                    TriggerExecution.workflow_type == "report_generation",
                    TriggerExecution.status == "available",
                    or_(
                        TriggerExecution.expires_at.is_(None),
                        TriggerExecution.expires_at > _db_time(now),
                    ),
                    Event.user_id == user_id,
                    Event.start_at > _db_time(now),
                    Event.status.not_in(("cancelled", "deleted", "completed")),
                )
                .order_by(
                    TriggerExecution.first_fired_at.desc(),
                    TriggerExecution.id.asc(),
                )
            )
        ).all()
        for execution, event in report_rows:
            chain_id = execution.id
            report_chains.add(chain_id)
            event_title = (
                (execution.payload_json or {}).get("event_title") or event.title
            )
            report_candidates[chain_id] = _SignalCandidate(
                natural_key=f"report:{chain_id}:opportunity",
                kind="report",
                ref=execution.id,
                title=f"为{event_title}准备会前调研",
                body="会议即将开始，可以先确认调研范围再生成报告。",
                target_type="trigger_execution",
                target_id=execution.id,
                actions=("open", "dismiss"),
                expires_at=execution.expires_at,
                rank=(
                    0,
                    -_aware_utc(execution.first_fired_at).timestamp(),
                    execution.id,
                ),
                phase="opportunity",
                chain_id=chain_id,
                evidence=dict(execution.payload_json or {}),
            )

        runs = list(
            await session.scalars(
                select(ReportGenerationRun)
                .where(
                    ReportGenerationRun.user_id == user_id,
                    ReportGenerationRun.origin == "trigger",
                    ReportGenerationRun.trigger_execution_id.is_not(None),
                )
                .order_by(
                    ReportGenerationRun.updated_at.desc(),
                    ReportGenerationRun.id.desc(),
                )
            )
        )
        for run in runs:
            chain_id = run.trigger_execution_id
            if chain_id is None:
                continue
            report_chains.add(chain_id)
            report_candidates.pop(chain_id, None)
            if (
                run.state == "awaiting_selection"
                and (run.pending_decision or {}).get("type") == "plan_selection"
                and run.plan_draft is not None
            ):
                scope = run.evidence_scope or {}
                asset_ids = scope.get("asset_ids") or run.resolved_asset_ids or []
                report_candidates[chain_id] = _SignalCandidate(
                    natural_key=f"report:{chain_id}:plan_ready",
                    kind="report",
                    ref=run.id,
                    title="报告方案已准备好",
                    body="可以查看方案、确认材料范围并决定是否生成报告。",
                    target_type="report_run",
                    target_id=run.id,
                    actions=("open", "dismiss"),
                    expires_at=run.expires_at,
                    rank=(0, -_aware_utc(run.updated_at).timestamp(), run.id),
                    phase="plan_ready",
                    chain_id=chain_id,
                    evidence={
                        "plan": dict(run.plan_draft or {}),
                        "scope": dict(scope),
                        "asset_count": len(asset_ids),
                    },
                    report_run_id=run.id,
                )
            elif run.state == "completed" and run.report_id:
                report = await session.get(Report, run.report_id)
                if report is None or report.user_id != user_id:
                    continue
                summary = " ".join(
                    line.lstrip("#- ").strip()
                    for line in report.content_md.splitlines()
                    if line.strip()
                )[:240]
                report_candidates[chain_id] = _SignalCandidate(
                    natural_key=f"report:{chain_id}:report_ready",
                    kind="report",
                    ref=report.id,
                    title="报告已生成",
                    body=report.title,
                    target_type="report",
                    target_id=report.id,
                    actions=("open", "dismiss"),
                    expires_at=None,
                    rank=(0, -_aware_utc(run.updated_at).timestamp(), run.id),
                    phase="report_ready",
                    chain_id=chain_id,
                    evidence={"title": report.title, "summary": summary},
                    report_run_id=run.id,
                    report_id=report.id,
                )
        candidates.extend(report_candidates.values())
    except Exception as exc:
        failures.append("report")
        logger.warning("Reka Report source failed: %s", type(exc).__name__)

    try:
        rhythm = await collect_rhythm_candidates(
            session,
            user_id=user_id,
            now=now,
            timezone_name=timezone_name,
        )
        for candidate in rhythm:
            period_label = candidate.period or "今天"
            candidates.append(
                _SignalCandidate(
                    natural_key=candidate.natural_key,
                    kind="rhythm_gap",
                    ref=candidate.ref,
                    title=f"{candidate.display_name}还没有记录",
                    body=f"你通常会在{period_label}记录，可以现在补上一笔。",
                    target_type="skill",
                    target_id=candidate.skill,
                    actions=("open", "dismiss"),
                    expires_at=_rhythm_expiry(
                        now=now,
                        timezone_name=timezone_name,
                        weekly=candidate.pattern_key.startswith("weekly:"),
                    ),
                    rank=(1, -candidate.confidence, candidate.skill, candidate.pattern_key),
                    evidence={
                        "cadence": candidate.cadence,
                        "period": candidate.period,
                        "weekdays": list(candidate.weekdays),
                        "sample_n": candidate.sample_n,
                        "pattern_key": candidate.pattern_key,
                        "cycle_key": candidate.cycle_key,
                    },
                )
            )
    except Exception as exc:
        failures.append("rhythm")
        logger.warning("Reka Rhythm source failed: %s", type(exc).__name__)

    try:
        overdue = await collect_overdue_candidates(
            session,
            user_id=user_id,
            now=now,
            timezone_name=timezone_name,
        )
        for candidate in overdue:
            candidates.append(
                _SignalCandidate(
                    natural_key=candidate.natural_key,
                    kind="overdue",
                    ref=candidate.todo_id,
                    title=f"{candidate.title} 已到截止时间",
                    body="这项待办仍未完成，可以现在处理或调整时间。",
                    target_type="asset",
                    target_id=candidate.todo_id,
                    actions=("open", "snooze", "dismiss"),
                    expires_at=candidate.expires_at,
                    rank=(2, -candidate.due_at.timestamp(), candidate.todo_id),
                )
            )
    except Exception as exc:
        failures.append("overdue")
        logger.warning("Reka Overdue source failed: %s", type(exc).__name__)
    return (
        sorted(candidates, key=lambda candidate: candidate.rank),
        failures,
        report_chains,
    )


async def list_signals(
    session: AsyncSession,
    *,
    user_id: str,
    now: datetime,
    timezone_name: str,
) -> dict:
    now_utc = _aware_utc(now)
    candidates, failures, report_chains = await _collect_candidates(
        session,
        user_id=user_id,
        now=now_utc,
        timezone_name=timezone_name,
    )
    keys = [candidate.natural_key for candidate in candidates]
    existing = {}
    if keys:
        rows = list(
            await session.scalars(
                select(Nudge).where(
                    Nudge.user_id == user_id,
                    Nudge.natural_key.in_(keys),
                )
            )
        )
        existing = {row.natural_key: row for row in rows}

    candidate_by_key = {candidate.natural_key: candidate for candidate in candidates}
    if "overdue" not in failures:
        active_overdue = list(
            await session.scalars(
                select(Nudge).where(
                    Nudge.user_id == user_id,
                    Nudge.kind == "overdue",
                    Nudge.status.in_(("delivered", "seen")),
                )
            )
        )
        for nudge in active_overdue:
            if nudge.natural_key in candidate_by_key:
                continue
            nudge.status = "expired"
            nudge.remind_again_at = None
    if "report" not in failures:
        active_reports = list(
            await session.scalars(
                select(Nudge).where(
                    Nudge.user_id == user_id,
                    Nudge.kind == "report",
                    Nudge.status.in_(("delivered", "seen")),
                )
            )
        )
        current_report_keys = {
            candidate.natural_key
            for candidate in candidates
            if candidate.kind == "report"
        }
        phases = {"opportunity", "plan_ready", "report_ready"}
        for nudge in active_reports:
            raw_identity = nudge.natural_key.removeprefix("report:")
            prefix, separator, suffix = raw_identity.rpartition(":")
            chain_id = prefix if separator and suffix in phases else nudge.ref
            if (
                chain_id in report_chains
                and nudge.natural_key not in current_report_keys
            ):
                nudge.status = "expired"
                nudge.remind_again_at = None
    for candidate in candidates:
        if candidate.natural_key in existing:
            continue
        nudge = Nudge(
            user_id=user_id,
            natural_key=candidate.natural_key,
            kind=candidate.kind,
            ref=candidate.ref,
            status="delivered",
            delivered_at=_db_time(now_utc),
            expires_at=_db_time(candidate.expires_at),
        )
        session.add(nudge)
        existing[candidate.natural_key] = nudge
    if candidates:
        await session.flush()

    signals = []
    for candidate in candidates:
        nudge = existing[candidate.natural_key]
        if nudge.status in {"acted", "dismissed", "expired"}:
            continue
        if (
            nudge.remind_again_at is not None
            and _aware_utc(nudge.remind_again_at) > now_utc
        ):
            continue
        if nudge.remind_again_at is not None:
            nudge.remind_again_at = None
        signals.append(
            {
                "id": nudge.id,
                "natural_key": candidate.natural_key,
                "kind": candidate.kind,
                "title": candidate.title,
                "body": candidate.body,
                "target": {
                    "type": candidate.target_type,
                    "id": candidate.target_id,
                },
                "actions": list(candidate.actions),
                "delivered_at": nudge.delivered_at or _db_time(now_utc),
                "expires_at": nudge.expires_at,
                "phase": candidate.phase,
                "chain_id": candidate.chain_id,
                "evidence": candidate.evidence,
                "report_run_id": candidate.report_run_id,
                "report_id": candidate.report_id,
            }
        )
    return {
        "ok": True,
        "signals": signals,
        "partial_failures": failures,
        "generated_at": now_utc,
    }


async def dismiss_signal(
    session: AsyncSession,
    *,
    user_id: str,
    signal_id: str,
    now: datetime,
) -> Nudge:
    nudge = await session.scalar(
        select(Nudge).where(
            Nudge.id == signal_id,
            Nudge.user_id == user_id,
        )
    )
    if nudge is None:
        raise SignalNotFound(signal_id)
    if nudge.status not in {"acted", "expired"}:
        nudge.status = "dismissed"
        if nudge.dismissed_at is None:
            nudge.dismissed_at = _db_time(now)
        nudge.remind_again_at = None
        await session.flush()
    return nudge


async def snooze_signal(
    session: AsyncSession,
    *,
    user_id: str,
    signal_id: str,
    remind_again_at: datetime,
    now: datetime,
) -> Nudge:
    nudge = await session.scalar(
        select(Nudge).where(
            Nudge.id == signal_id,
            Nudge.user_id == user_id,
        )
    )
    if nudge is None:
        raise SignalNotFound(signal_id)
    if nudge.kind != "overdue" or nudge.status not in {"delivered", "seen"}:
        raise SignalCannotSnooze(signal_id)
    remind_utc = _aware_utc(remind_again_at)
    if remind_utc <= _aware_utc(now):
        raise InvalidSnoozeTime(signal_id)
    nudge.remind_again_at = _db_time(remind_utc)
    await session.flush()
    return nudge
