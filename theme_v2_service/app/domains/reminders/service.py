from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Event, UserSkill
from app.domains.notifications.models import ReminderDelivery
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.reminders.preferences import normalize_reminder_offsets


@dataclass(frozen=True)
class _DueReminder:
    natural_key: str
    user_id: str
    record_kind: str
    record_id: str
    title: str
    anchor_at: datetime
    offset_minutes: int


def _aware_utc(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc)


def _db_time(value: datetime) -> datetime:
    return _aware_utc(value).replace(tzinfo=None)


def _parse_todo_due_at(value: object, *, timezone_name: str) -> datetime | None:
    if not isinstance(value, str) or "T" not in value:
        return None
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=ZoneInfo(timezone_name))
    return parsed.astimezone(timezone.utc)


def _event_anchor(event: Event, *, timezone_name: str) -> datetime:
    start = _aware_utc(event.start_at)
    if not event.all_day:
        return start
    zone = ZoneInfo(timezone_name)
    local_day = start.astimezone(zone).date()
    return datetime.combine(local_day, time(9, 0), tzinfo=zone).astimezone(
        timezone.utc
    )


def _natural_key(
    *,
    kind: str,
    record_id: str,
    anchor_at: datetime,
    offset_minutes: int,
) -> str:
    anchor = _aware_utc(anchor_at).isoformat().replace("+00:00", "Z")
    return f"reminder:{kind}:{record_id}:{anchor}:{offset_minutes}"


def _is_due(
    *,
    anchor_at: datetime,
    offset_minutes: int,
    now: datetime,
    lookback: timedelta,
) -> bool:
    fire_at = _aware_utc(anchor_at) - timedelta(minutes=offset_minutes)
    now_utc = _aware_utc(now)
    return now_utc - lookback < fire_at <= now_utc


async def _collect_due_reminders(
    session: AsyncSession,
    *,
    now: datetime,
    timezone_name: str,
    lookback: timedelta,
) -> list[_DueReminder]:
    due: list[_DueReminder] = []
    event_rows = list(
        await session.scalars(
            select(Event)
            .where(Event.status.not_in(("cancelled", "done", "completed", "deleted")))
            .order_by(Event.start_at, Event.id)
        )
    )
    for event in event_rows:
        anchor = _event_anchor(event, timezone_name=timezone_name)
        offsets = normalize_reminder_offsets(
            event.reminder_offsets_json,
            missing_uses_default=True,
        )
        for offset in offsets:
            if not _is_due(
                anchor_at=anchor,
                offset_minutes=offset,
                now=now,
                lookback=lookback,
            ):
                continue
            due.append(
                _DueReminder(
                    natural_key=_natural_key(
                        kind="event",
                        record_id=event.id,
                        anchor_at=anchor,
                        offset_minutes=offset,
                    ),
                    user_id=event.user_id,
                    record_kind="event",
                    record_id=event.id,
                    title=event.title,
                    anchor_at=anchor,
                    offset_minutes=offset,
                )
            )

    todo_rows = (
        await session.execute(
            select(Asset, UserSkill)
            .join(UserSkill, UserSkill.id == Asset.user_skill_id)
            .where(UserSkill.machine_name == "todo")
            .order_by(Asset.created_at, Asset.id)
        )
    ).all()
    for asset, _skill in todo_rows:
        payload = asset.payload_json or {}
        status = str(payload.get("status") or "pending").strip().lower()
        if status in {"done", "completed", "cancelled", "deleted"}:
            continue
        anchor = _parse_todo_due_at(
            payload.get("due_date"),
            timezone_name=timezone_name,
        )
        if anchor is None:
            continue
        offsets = normalize_reminder_offsets(
            payload.get("reminder_offsets_minutes"),
            missing_uses_default=True,
        )
        for offset in offsets:
            if not _is_due(
                anchor_at=anchor,
                offset_minutes=offset,
                now=now,
                lookback=lookback,
            ):
                continue
            due.append(
                _DueReminder(
                    natural_key=_natural_key(
                        kind="todo",
                        record_id=asset.id,
                        anchor_at=anchor,
                        offset_minutes=offset,
                    ),
                    user_id=asset.user_id,
                    record_kind="todo",
                    record_id=asset.id,
                    title=str(payload.get("title") or "待办"),
                    anchor_at=anchor,
                    offset_minutes=offset,
                )
            )
    return due


async def dispatch_due_reminders(
    session: AsyncSession,
    *,
    now: datetime,
    timezone_name: str,
    lookback: timedelta = timedelta(minutes=5),
) -> int:
    due = await _collect_due_reminders(
        session,
        now=now,
        timezone_name=timezone_name,
        lookback=lookback,
    )
    if not due:
        return 0
    existing_keys = set(
        await session.scalars(
            select(ReminderDelivery.natural_key).where(
                ReminderDelivery.natural_key.in_(
                    [candidate.natural_key for candidate in due]
                )
            )
        )
    )
    dispatched = 0
    for candidate in due:
        if candidate.natural_key in existing_keys:
            continue
        notification = await create_notification(
            session,
            NotificationCreate(
                user_id=candidate.user_id,
                type=f"{candidate.record_kind}_reminder",
                title=candidate.title,
                body=(
                    "现在开始"
                    if candidate.offset_minutes == 0
                    else f"将在 {candidate.offset_minutes} 分钟后开始"
                ),
                link=f"/{'events' if candidate.record_kind == 'event' else 'assets'}/{candidate.record_id}",
            ),
        )
        session.add(
            ReminderDelivery(
                user_id=candidate.user_id,
                natural_key=candidate.natural_key,
                record_kind=candidate.record_kind,
                record_id=candidate.record_id,
                anchor_at=_db_time(candidate.anchor_at),
                offset_minutes=candidate.offset_minutes,
                notification_id=notification.id,
                delivered_at=_db_time(now),
            )
        )
        existing_keys.add(candidate.natural_key)
        dispatched += 1
    await session.flush()
    return dispatched
