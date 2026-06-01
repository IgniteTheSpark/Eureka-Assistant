"""
core/reminder_scheduler — Phase D M7. Time-driven reminders.

A dependency-free asyncio loop (started in main.py's lifespan) that scans every
minute and emits a `reminder` notification — via the M6 pipeline
(core.notifications.create_notification) — when:

  - a scheduled, timed event is about to start (60 / 30 / 15 min before)
  - a not-done todo is about to hit its due_date (60 / 15 min before)

Dedup survives restarts: each (entity, threshold) reminder writes a
deterministic `link` (e.g. "reminder:evt:<id>:15"); before firing we check the
notifications table for that exact link. The firing window is slightly wider
than the scan interval so a single scan never misses a threshold, and the link
dedup guarantees we still only send once.
"""
import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select

from core.notifications import create_notification
from db.database import AsyncSessionLocal
from db.models import Asset, Event, GlobalSkill, Notification, UserSkill

log = logging.getLogger("eureka.reminders")

EVENT_THRESHOLDS = [60, 30, 15]   # minutes before start
TODO_THRESHOLDS = [60, 15]        # minutes before due_date
SCAN_INTERVAL_SEC = 60
WINDOW_MIN = 1.5                   # > scan interval (in min) so no threshold is skipped


def _fmt_threshold(mins: int) -> str:
    return "1 小时后" if mins >= 60 else f"{mins} 分钟后"


def _parse_dt(v) -> Optional[datetime]:
    if not isinstance(v, str) or not v:
        return None
    try:
        dt = datetime.fromisoformat(v.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None


def _event_body(e: Event) -> str:
    t = e.start_at.astimezone().strftime("%H:%M") if e.start_at else ""
    return f"{t} · {e.location}" if e.location else t


async def _existing_links(db, user_id: str, links: set[str]) -> set[str]:
    if not links:
        return set()
    rows = (await db.execute(
        select(Notification.link).where(
            Notification.user_id == user_id,
            Notification.link.in_(list(links)),
        )
    )).scalars().all()
    return set(rows)


async def scan_once() -> int:
    """One pass. Returns the number of reminders fired (handy for testing)."""
    now = datetime.now(timezone.utc)
    # (user_id, link, title, body)
    candidates: list[tuple[str, str, str, str]] = []

    async with AsyncSessionLocal() as db:
        # ── events ──
        events = (await db.execute(
            select(Event).where(Event.status == "scheduled", Event.all_day == 0)
        )).scalars().all()
        for e in events:
            if e.start_at is None:
                continue
            mins = (e.start_at - now).total_seconds() / 60
            for thr in EVENT_THRESHOLDS:
                if thr - WINDOW_MIN < mins <= thr:
                    candidates.append((
                        e.user_id,
                        f"reminder:evt:{e.id}:{thr}",
                        f"{_fmt_threshold(thr)}:{e.title}",
                        _event_body(e),
                    ))

        # ── todos ──
        todos = (await db.execute(
            select(Asset)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(GlobalSkill.name == "todo")
        )).scalars().all()
        for a in todos:
            p = a.payload or {}
            if p.get("status") == "done" or p.get("done") is True:
                continue
            due = _parse_dt(p.get("due_date"))
            if due is None:
                continue
            mins = (due - now).total_seconds() / 60
            label = str(p.get("content") or p.get("title") or "待办")[:80]
            for thr in TODO_THRESHOLDS:
                if thr - WINDOW_MIN < mins <= thr:
                    candidates.append((
                        a.user_id,
                        f"reminder:todo:{a.id}:{thr}",
                        f"{_fmt_threshold(thr)}到期:{label}",
                        "",
                    ))

        # dedup against already-sent reminders (per user)
        by_user: dict[str, set[str]] = {}
        for uid, link, *_ in candidates:
            by_user.setdefault(uid, set()).add(link)
        existing: set[str] = set()
        for uid, links in by_user.items():
            existing |= await _existing_links(db, uid, links)

    fired = 0
    for uid, link, title, body in candidates:
        if link in existing:
            continue
        await create_notification(user_id=uid, type="reminder", title=title, body=body, link=link)
        fired += 1
    if fired:
        log.info("reminder scheduler fired %d reminder(s)", fired)
    return fired


async def reminder_loop() -> None:
    log.info("reminder scheduler started (interval=%ss)", SCAN_INTERVAL_SEC)
    while True:
        try:
            await scan_once()
        except asyncio.CancelledError:
            raise
        except Exception as exc:   # never let the loop die
            log.warning("reminder scan failed: %s", exc)
        await asyncio.sleep(SCAN_INTERVAL_SEC)
