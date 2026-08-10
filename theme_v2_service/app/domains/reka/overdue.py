from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, UserSkill


OVERDUE_TTL = timedelta(hours=72)
_DONE_STATUSES = {"done", "completed", "complete"}


@dataclass(frozen=True)
class OverdueCandidate:
    todo_id: str
    title: str
    due_at: datetime
    expires_at: datetime
    natural_key: str


def _utc(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc)


def _utc_z(value: datetime) -> str:
    utc_value = _utc(value)
    timespec = "microseconds" if utc_value.microsecond else "seconds"
    return utc_value.isoformat(timespec=timespec).replace("+00:00", "Z")


def parse_todo_due(value: Any, timezone_name: str) -> datetime | None:
    """Parse only explicit ISO date-times; bare dates are intentionally untimed."""

    if not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw or "T" not in raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=ZoneInfo(timezone_name))
    return parsed.astimezone(timezone.utc)


def _completed(payload: dict[str, Any]) -> bool:
    if payload.get("done") is True:
        return True
    status = str(payload.get("status") or "").strip().lower()
    return status in _DONE_STATUSES


def _title(payload: dict[str, Any]) -> str:
    for key in ("title", "content", "name"):
        value = str(payload.get(key) or "").strip()
        if value:
            return value[:120]
    return "待办"


def overdue_candidate(
    *,
    todo_id: str,
    payload: dict[str, Any],
    now: datetime,
    timezone_name: str,
) -> OverdueCandidate | None:
    if _completed(payload):
        return None
    due_at = parse_todo_due(payload.get("due_date"), timezone_name)
    if due_at is None:
        return None
    now_utc = _utc(now)
    expires_at = due_at + OVERDUE_TTL
    if now_utc <= due_at or now_utc >= expires_at:
        return None
    return OverdueCandidate(
        todo_id=todo_id,
        title=_title(payload),
        due_at=due_at,
        expires_at=expires_at,
        natural_key=f"overdue:{todo_id}:{_utc_z(due_at)}",
    )


async def collect_overdue_candidates(
    session: AsyncSession,
    *,
    user_id: str,
    now: datetime,
    timezone_name: str,
) -> list[OverdueCandidate]:
    rows = list(
        await session.scalars(
            select(Asset)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .where(
                Asset.user_id == user_id,
                UserSkill.machine_name == "todo",
            )
        )
    )
    candidates = [
        candidate
        for asset in rows
        if (
            candidate := overdue_candidate(
                todo_id=asset.id,
                payload=asset.payload_json or {},
                now=now,
                timezone_name=timezone_name,
            )
        )
        is not None
    ]
    return sorted(candidates, key=lambda candidate: candidate.due_at, reverse=True)
