from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Event
from app.domains.triggers.models import TriggerExecution
from app.domains.triggers.notifications import ensure_report_available_notification


def _utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _utc_z(value: datetime) -> str:
    return _utc_naive(value).replace(tzinfo=timezone.utc).isoformat().replace(
        "+00:00",
        "Z",
    )


def is_pre_event_eligible(event: Event, now: datetime) -> bool:
    now = _utc_naive(now)
    return (
        event.status == "scheduled"
        and not event.all_day
        and _utc_naive(event.start_at) > now
    )


def should_fire_pre_event(event: Event, now: datetime) -> bool:
    now = _utc_naive(now)
    return is_pre_event_eligible(event, now) and _utc_naive(
        event.start_at
    ) <= now + timedelta(hours=1)


def pre_event_dedupe_key(event: Event) -> str:
    return f"pre_event_report:{event.id}:{_utc_z(event.start_at)}"


async def evaluate_pre_event(
    session: AsyncSession,
    *,
    event: Event,
    now: datetime,
) -> TriggerExecution | None:
    now = _utc_naive(now)
    if not should_fire_pre_event(event, now):
        return None

    dedupe_key = pre_event_dedupe_key(event)
    existing = await session.scalar(
        select(TriggerExecution).where(
            TriggerExecution.dedupe_key == dedupe_key
        )
    )
    if existing is not None:
        return None

    execution = TriggerExecution(
        user_id=event.user_id,
        trigger_type="pre_event_report",
        workflow_type="report_generation",
        tracker_id=None,
        scope_type="event",
        scope_id=event.id,
        status="available",
        dedupe_key=dedupe_key,
        revision=1,
        payload_json={
            "event_id": event.id,
            "event_start_at": _utc_z(event.start_at),
            "event_title": event.title,
        },
        first_fired_at=now,
        last_fired_at=now,
        expires_at=_utc_naive(event.start_at),
    )
    session.add(execution)
    await session.flush()
    await ensure_report_available_notification(
        session,
        execution=execution,
        title=f"“{event.title}”将在 1 小时后开始",
        body="需要准备一份会前调研吗？",
        now=now,
    )
    return execution


async def scan_pre_event_window(
    session: AsyncSession,
    *,
    now: datetime,
) -> int:
    now = _utc_naive(now)
    events = list(
        await session.scalars(
            select(Event)
            .where(
                Event.status == "scheduled",
                Event.all_day.is_(False),
                Event.start_at > now,
                Event.start_at <= now + timedelta(hours=1),
            )
            .order_by(Event.id)
            .with_for_update(skip_locked=True)
            .limit(100)
        )
    )
    fired = 0
    for event in events:
        if await evaluate_pre_event(session, event=event, now=now) is not None:
            fired += 1
    return fired


async def expire_stale_pre_event_executions(
    session: AsyncSession,
    *,
    now: datetime,
) -> int:
    now = _utc_naive(now)
    executions = list(
        await session.scalars(
            select(TriggerExecution)
            .where(
                TriggerExecution.trigger_type == "pre_event_report",
                TriggerExecution.status == "available",
            )
            .order_by(TriggerExecution.id)
            .with_for_update(skip_locked=True)
            .limit(100)
        )
    )
    expired = 0
    for execution in executions:
        event = await session.scalar(
            select(Event)
            .where(Event.id == execution.scope_id)
            .with_for_update()
        )
        stale = event is None or not is_pre_event_eligible(event, now)
        if event is not None and not stale:
            stale = execution.payload_json.get("event_start_at") != _utc_z(
                event.start_at
            )
        if stale:
            execution.status = "expired"
            expired += 1
    await session.flush()
    return expired
