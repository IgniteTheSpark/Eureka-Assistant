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
from app.domains.triggers.models import TriggerExecution


logger = logging.getLogger(__name__)


class SignalNotFound(Exception):
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
) -> tuple[list[_SignalCandidate], list[str]]:
    candidates: list[_SignalCandidate] = []
    failures: list[str] = []
    try:
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
            event_title = (
                (execution.payload_json or {}).get("event_title") or event.title
            )
            candidates.append(
                _SignalCandidate(
                    natural_key=f"report:{execution.id}",
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
                )
            )
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
                    actions=("open", "complete", "reschedule", "dismiss"),
                    expires_at=candidate.expires_at,
                    rank=(2, -candidate.due_at.timestamp(), candidate.todo_id),
                )
            )
    except Exception as exc:
        failures.append("overdue")
        logger.warning("Reka Overdue source failed: %s", type(exc).__name__)
    return sorted(candidates, key=lambda candidate: candidate.rank), failures


async def list_signals(
    session: AsyncSession,
    *,
    user_id: str,
    now: datetime,
    timezone_name: str,
) -> dict:
    now_utc = _aware_utc(now)
    candidates, failures = await _collect_candidates(
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
        await session.flush()
    return nudge
