"""
core/companion — §14 主动 REKA: heartbeat + 缺口触发引擎 + 傻瓜护栏 (Phase 2).

A dependency-free asyncio loop (started in main.py's lifespan, sibling of
reminder_loop) that wakes every ~30 minutes and:

1. once a day (Beijing date change): recomputes the §14.2 rhythm profiles
   (offline statistical pass) and marks yesterday's un-acted nudges `ignored`;
2. runs the §14.3 trigger: **缺口 → Type A 提醒** — "you usually record X around
   this hour; today you haven't" → a template nudge (ZERO per-tick LLM, §14.1
   成本铁律), persisted in `nudges` + pushed through the existing notification
   pipeline (feed + SSE; the mobile shell shows it as a REKA peek bubble).

傻瓜护栏 (§14.8) — all server-side, zero configuration:
- master switch: users.prefs.nudges_enabled (absent = ON; 一个总开关给想关的人)
- quiet hours: no nudges 22:00–08:00 Beijing (静默时段自动)
- hard cap: ≤2 nudges / user / day (通知疲劳是卸载头号原因)
- confidence gate: profile confidence below threshold → stay silent (不确定不发)
- adaptive backoff: the last 2 nudges for the same habit went un-acted →
  back off for 72h (忽略 → REKA 退避;采纳 → 继续). Powered by outcome states.
- 温柔铁律: copy is an invitation (「该记早餐了?」), never a reproach.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select, update

from core.notifications import create_notification
from db.database import AsyncSessionLocal
from db.models import Asset, GlobalSkill, Nudge, RhythmProfile, User, UserSkill

log = logging.getLogger("eureka.companion")

_BEIJING = timezone(timedelta(hours=8))

HEARTBEAT_INTERVAL_SEC = 1800   # ~30 min (§14.1)
QUIET_START, QUIET_END = 22, 8  # Beijing quiet hours (静默时段)
DAILY_CAP = 2                   # hard cap, nudges / user / day (§14.8)
CONFIDENCE_GATE = 0.45          # below → 数据不够别瞎猜 (§14.2)
GRACE_HOURS = 1                 # nudge only after peak hour + grace has passed
LATE_HOURS = 3                  # …and not later than peak + this (8am 习惯别在晚上催)
BACKOFF_HOURS = 72              # 2 consecutive un-acted nudges for a habit → 退避


def _bj_day_bounds(now_utc: datetime) -> tuple[datetime, datetime]:
    """(start, end) of the current Beijing day, in UTC (created_at is UTC)."""
    bj = now_utc.astimezone(_BEIJING)
    start_bj = bj.replace(hour=0, minute=0, second=0, microsecond=0)
    return start_bj.astimezone(timezone.utc), (start_bj + timedelta(days=1)).astimezone(timezone.utc)


def _nudges_enabled(user: User | None) -> bool:
    if user is None:
        return True
    prefs = user.prefs or {}
    return prefs.get("nudges_enabled") is not False  # absent = ON (§14.8 默认开)


async def expire_stale() -> int:
    """Yesterday's delivered/seen nudges → `ignored` (过期未处理, §14.7). Keeps
    the feed honest and feeds the adaptive backoff."""
    day_start_utc, _ = _bj_day_bounds(datetime.now(timezone.utc))
    async with AsyncSessionLocal() as db:
        res = await db.execute(
            update(Nudge)
            .where(Nudge.status.in_(("pending", "delivered", "seen")),
                   Nudge.created_at < day_start_utc)
            .values(status="ignored")
        )
        await db.commit()
    n = int(res.rowcount or 0)
    if n:
        log.info("companion: %d stale nudge(s) → ignored", n)
    return n


async def scan_once() -> int:
    """One heartbeat pass of the 缺口 trigger. Deterministic + cheap (a few
    indexed queries; ZERO LLM). Returns nudges fired."""
    now = datetime.now(timezone.utc)
    bj = now.astimezone(_BEIJING)
    if bj.hour >= QUIET_START or bj.hour < QUIET_END:
        return 0  # 静默时段 (§14.8)

    day_start_utc, day_end_utc = _bj_day_bounds(now)
    fired = 0

    async with AsyncSessionLocal() as db:
        profiles = (await db.execute(
            select(RhythmProfile).where(RhythmProfile.confidence >= CONFIDENCE_GATE)
        )).scalars().all()
        if not profiles:
            return 0

        by_user: dict[str, list[RhythmProfile]] = {}
        for p in profiles:
            by_user.setdefault(p.user_id, []).append(p)

        for uid, profs in by_user.items():
            user = (await db.execute(select(User).where(User.id == uid))).scalar_one_or_none()
            if not _nudges_enabled(user):
                continue  # 总开关 OFF

            today_count = (await db.execute(
                select(func.count(Nudge.id)).where(
                    Nudge.user_id == uid,
                    Nudge.created_at >= day_start_utc,
                )
            )).scalar() or 0
            if today_count >= DAILY_CAP:
                continue  # 硬上限 (§14.8)

            # strongest habit first — if the cap allows only one nudge, pick the
            # one REKA is most sure about.
            for p in sorted(profs, key=lambda x: -(x.confidence or 0)):
                if today_count >= DAILY_CAP:
                    break

                # weekday pattern (周一三五型) — only nudge on its days
                wd = p.weekdays or []
                if wd and bj.weekday() not in wd:
                    continue

                # 缺口窗口: some peak hour h has passed by ≥GRACE_HOURS and we're
                # not embarrassingly late (≤ h+LATE_HOURS).
                hours = p.typical_hours or []
                if not any(h + GRACE_HOURS <= bj.hour <= h + LATE_HOURS for h in hours):
                    continue

                # already recorded this skill today → no gap
                recorded = (await db.execute(
                    select(func.count(Asset.id))
                    .join(UserSkill, Asset.user_skill_id == UserSkill.id)
                    .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
                    .where(Asset.user_id == uid,
                           GlobalSkill.name == p.skill,
                           Asset.created_at >= day_start_utc)
                )).scalar() or 0
                if recorded:
                    continue

                # one nudge per habit per day (dedupe) + adaptive backoff
                recent = (await db.execute(
                    select(Nudge).where(
                        Nudge.user_id == uid,
                        Nudge.kind == "rhythm_gap",
                        Nudge.ref == p.skill,
                    ).order_by(Nudge.created_at.desc()).limit(2)
                )).scalars().all()
                if recent and recent[0].created_at and recent[0].created_at >= day_start_utc:
                    continue  # already nudged this habit today
                if len(recent) == 2 and all(r.status in ("ignored", "dismissed", "expired") for r in recent):
                    last_at = recent[0].created_at
                    if last_at and (now - last_at) < timedelta(hours=BACKOFF_HOURS):
                        continue  # 退避: 连续两次没理 → 歇 72h (§14.8 自适应)

                # display name for the copy (fallback to machine name)
                disp = (await db.execute(
                    select(UserSkill.display_name)
                    .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
                    .where(UserSkill.user_id == uid, GlobalSkill.name == p.skill)
                    .limit(1)
                )).scalar_one_or_none() or p.skill

                peak = max((h for h in hours if h + GRACE_HOURS <= bj.hour), default=hours[0] if hours else bj.hour)
                nudge = Nudge(
                    user_id=uid, type="A", kind="rhythm_gap",
                    text=f"🐾 该记{disp}了?",
                    body=f"你一般 {peak} 点前后会记一笔{disp},今天还没有。要记就点一下,不记也没关系。",
                    ref=p.skill, cta="log",
                    status="delivered", source="rhythm",
                    delivered_at=now,
                    expires_at=day_end_utc,
                )
                db.add(nudge)
                await db.commit()
                await db.refresh(nudge)

                # into the existing notification pipeline → feed 回溯 + SSE
                # (the mobile shell surfaces type=nudge as a REKA peek bubble,
                # NOT a regular toast). link carries the nudge id + skill ref.
                await create_notification(
                    user_id=uid, type="nudge", title=nudge.text,
                    body=nudge.body or "", link=f"nudge:{nudge.id}:{p.skill}",
                )
                fired += 1
                today_count += 1

    if fired:
        log.info("companion fired %d nudge(s)", fired)
    return fired


async def companion_loop() -> None:
    """§14.1 heartbeat — sibling of reminder_loop. Daily offline work (profile
    recompute + stale expiry) piggybacks on the first tick of each Beijing day."""
    from core.rhythm import recompute_all
    log.info("companion heartbeat started (interval=%ss)", HEARTBEAT_INTERVAL_SEC)
    last_recompute_day = ""
    while True:
        try:
            today_bj = datetime.now(timezone.utc).astimezone(_BEIJING).strftime("%Y-%m-%d")
            if today_bj != last_recompute_day:
                await recompute_all()
                await expire_stale()
                last_recompute_day = today_bj
            await scan_once()
        except asyncio.CancelledError:
            raise
        except Exception as exc:   # never let the loop die
            log.warning("companion scan failed: %s", exc)
        await asyncio.sleep(HEARTBEAT_INTERVAL_SEC)
