from __future__ import annotations

import logging
import re
from collections.abc import Mapping
from datetime import date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


logger = logging.getLogger(__name__)

DEFAULT_TIMEZONE = "Asia/Shanghai"
PERIOD_END: dict[str, tuple[int, int]] = {
    "凌晨": (5, 0),
    "上午": (11, 0),
    "中午": (12, 30),
    "下午": (17, 0),
    "晚上": (23, 0),
}

_DATE_ONLY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _zone(timezone_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(timezone_name)
    except (ZoneInfoNotFoundError, ValueError):
        logger.warning(
            "todo deadline received unknown timezone; using product default",
            extra={"timezone_name": timezone_name},
        )
        return ZoneInfo(DEFAULT_TIMEZONE)


def _aware(value: datetime, zone: ZoneInfo) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=zone)
    return value.astimezone(zone)


def _datetime_value(value: Any, *, field: str, zone: ZoneInfo) -> datetime | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return _aware(value, zone)
    raw = str(value).strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"invalid todo {field}: {raw}") from exc
    return _aware(parsed, zone)


def _due_value(value: Any, zone: ZoneInfo) -> tuple[datetime | None, date | None]:
    if value is None or value == "":
        return None, None
    if isinstance(value, datetime):
        return _aware(value, zone), None
    if isinstance(value, date):
        return None, value
    raw = str(value).strip()
    if not raw:
        return None, None
    if _DATE_ONLY.fullmatch(raw):
        try:
            return None, date.fromisoformat(raw)
        except ValueError as exc:
            raise ValueError(f"invalid todo due_date: {raw}") from exc
    return _datetime_value(raw, field="due_date", zone=zone), None


def _anchor_date(value: Any, zone: ZoneInfo) -> date | None:
    if value is None or value == "":
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    return _datetime_value(value, field="effective_at", zone=zone).date()


def _at(day: date, hour: int, minute: int, zone: ZoneInfo) -> datetime:
    return datetime.combine(day, time(hour, minute), tzinfo=zone)


def normalize_todo_deadline(
    *,
    due_date: Any,
    period: str | None,
    effective_at: Any,
    occurred_at: Any,
    reference_datetime: datetime,
    timezone_name: str,
) -> datetime:
    """Return the single concrete, timezone-aware deadline for a new Todo."""

    zone = _zone(timezone_name)
    reference = _aware(reference_datetime, zone)
    exact_due, due_day = _due_value(due_date, zone)
    if exact_due is not None:
        return exact_due

    exact_occurrence = _datetime_value(
        occurred_at,
        field="occurred_at",
        zone=zone,
    )
    if exact_occurrence is not None:
        return exact_occurrence

    anchor = due_day or _anchor_date(effective_at, zone)
    if anchor is not None:
        hour, minute = PERIOD_END.get(str(period or ""), (18, 0))
        candidate = _at(anchor, hour, minute, zone)
        if anchor == reference.date() and candidate < reference:
            return candidate + timedelta(days=1)
        return candidate

    period_end = PERIOD_END.get(str(period or ""))
    if period_end is not None:
        candidate = _at(reference.date(), *period_end, zone)
        return candidate if candidate >= reference else candidate + timedelta(days=1)

    cutoff = _at(reference.date(), 18, 0, zone)
    return cutoff if reference <= cutoff else cutoff + timedelta(days=1)


def normalize_new_todo_payload(
    payload: Mapping[str, Any],
    *,
    period: str | None,
    effective_at: Any,
    occurred_at: Any,
    reference_datetime: datetime,
    timezone_name: str,
) -> dict[str, Any]:
    """Apply the deadline invariant and creation-only initial status rule."""

    zone = _zone(timezone_name)
    reference = _aware(reference_datetime, zone)
    result = dict(payload)
    deadline = normalize_todo_deadline(
        due_date=result.get("due_date"),
        period=period,
        effective_at=effective_at,
        occurred_at=occurred_at,
        reference_datetime=reference,
        timezone_name=zone.key,
    )
    result["due_date"] = deadline.isoformat()
    result["status"] = "completed" if deadline < reference else "pending"
    return result
