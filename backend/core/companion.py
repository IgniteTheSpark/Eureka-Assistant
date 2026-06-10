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
from db.models import Asset, GlobalSkill, Nudge, Report, RhythmProfile, User, UserSkill

log = logging.getLogger("eureka.companion")

_BEIJING = timezone(timedelta(hours=8))

HEARTBEAT_INTERVAL_SEC = 1800   # ~30 min (§14.1)
QUIET_START, QUIET_END = 22, 8  # Beijing quiet hours (静默时段)
DAILY_CAP = 2                   # hard cap, nudges / user / day (§14.8)
CONFIDENCE_GATE = 0.45          # below → 数据不够别瞎猜 (§14.2)
GRACE_HOURS = 1                 # nudge only after peak hour + grace has passed
LATE_HOURS = 3                  # …and not later than peak + this (8am 习惯别在晚上催)
BACKOFF_HOURS = 72              # 2 consecutive un-acted nudges for a habit → 退避

# §14.3 积累 → Type B offer (Phase 4 §14.5): enough recent records of a
# synthesizable kind → 「要我帮你理一理?」→ accept = one-tap report (genre 内置).
# Maps the spec's examples: 聚合想法 → idea-synthesis;消费分析 → data-report.
_ACCUM_RULES = (
    # (matcher(machine_name, display_name), threshold per 7d, genre, 文案标签)
    (lambda m, d: m in ("idea", "ideas") or "灵感" in (d or ""), 5, "idea-synthesis", "灵感"),
    (lambda m, d: m == "expense" or "记账" in (d or "") or "消费" in (d or ""), 8, "data-report", "消费"),
)
OFFER_TTL_HOURS = 72       # an offer stays actionable for 3 days, then expires
OFFER_DEDUPE_DAYS = 7      # at most one offer per habit per week (offers are rare)


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
    """Un-acted nudges past their lifetime → `ignored` (过期未处理, §14.7).
    Lifetime = `expires_at` when set (offers live ~72h); else end of the day it
    was sent (rhythm reminders are day-scoped). Keeps the feed honest and feeds
    the adaptive backoff."""
    now = datetime.now(timezone.utc)
    day_start_utc, _ = _bj_day_bounds(now)
    async with AsyncSessionLocal() as db:
        res = await db.execute(
            update(Nudge)
            .where(Nudge.status.in_(("pending", "delivered", "seen")),
                   ((Nudge.expires_at.is_(None)) & (Nudge.created_at < day_start_utc))
                   | (Nudge.expires_at.is_not(None)) & (Nudge.expires_at < now))
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
        # ── §14.3 积累 → Type B offer (runs first: offers are rarer + richer;
        #    they share the user's DAILY_CAP with rhythm reminders) ────────────
        week_ago = now - timedelta(days=7)

        async def _count_since(uid: str, *, machine: str | None, domain: str | None,
                               since: datetime) -> int:
            q = select(func.count(Asset.id)).where(
                Asset.user_id == uid, Asset.created_at >= since)
            if machine is not None:
                q = (q.join(UserSkill, Asset.user_skill_id == UserSkill.id)
                      .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
                      .where(GlobalSkill.name == machine))
            if domain is not None:
                q = q.where(Asset.domain == domain)
            return int((await db.execute(q)).scalar() or 0)

        async def _try_offer(uid: str, *, ref: str, cnt: int, thr: int,
                             genre: str, label: str,
                             machine: str | None, domain: str | None) -> bool:
            """All §14.8 guardrails for one offer candidate; returns fired?"""
            user = (await db.execute(select(User).where(User.id == uid))).scalar_one_or_none()
            if not _nudges_enabled(user):
                return False
            today_n = (await db.execute(
                select(func.count(Nudge.id)).where(
                    Nudge.user_id == uid, Nudge.created_at >= day_start_utc)
            )).scalar() or 0
            if today_n >= DAILY_CAP:
                return False
            # one offer per habit per week — offers must stay rare to stay welcome
            prior = (await db.execute(
                select(func.count(Nudge.id)).where(
                    Nudge.user_id == uid, Nudge.kind == "offer", Nudge.ref == ref,
                    Nudge.created_at >= now - timedelta(days=OFFER_DEDUPE_DAYS))
            )).scalar() or 0
            if prior:
                return False
            # synthesized recently → only re-offer if enough NEW records piled
            # up SINCE that report (a fresh batch deserves a fresh offer; a
            # blanket 7d mute would go quiet right when they're most active)
            last_report_at = (await db.execute(
                select(func.max(Report.created_at)).where(
                    Report.user_id == uid, Report.genre == genre,
                    Report.created_at >= week_ago)
            )).scalar()
            if last_report_at is not None:
                if last_report_at.tzinfo is None:
                    last_report_at = last_report_at.replace(tzinfo=timezone.utc)
                if await _count_since(uid, machine=machine, domain=domain,
                                      since=last_report_at) < thr:
                    return False
            nudge = Nudge(
                user_id=uid, type="B", kind="offer",
                text=f"✨ 这周记了 {cnt} 条{label},要我帮你理一理?",
                body="点「帮我理一理」,Reka 把它们聚合成一份报告——共性、张力和下一步。不需要就划走,不打扰。",
                ref=ref, cta="synthesize",
                status="delivered", source="rhythm",
                delivered_at=now, expires_at=now + timedelta(hours=OFFER_TTL_HOURS),
            )
            db.add(nudge)
            await db.commit()
            await db.refresh(nudge)
            await create_notification(
                user_id=uid, type="nudge", title=nudge.text,
                body=nudge.body or "", link=f"nudge:{nudge.id}:{ref}",
            )
            return True

        # pass 1 — dedicated skills (a real 灵感/记账 skill)
        acc_rows = (await db.execute(
            select(Asset.user_id, GlobalSkill.name, UserSkill.display_name,
                   func.count(Asset.id))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.created_at >= week_ago)
            .group_by(Asset.user_id, GlobalSkill.name, UserSkill.display_name)
        )).all()
        # a user may carry dup user_skill rows → aggregate by (user, machine)
        acc: dict[tuple[str, str], list] = {}
        offered_idea: set[str] = set()  # users already offered an idea synthesis
        for uid, machine, disp, cnt in acc_rows:
            cur = acc.setdefault((uid, machine), [disp, 0])
            cur[0] = cur[0] or disp
            cur[1] += int(cnt or 0)
        for (uid, machine), (disp, cnt) in acc.items():
            rule = next((r for r in _ACCUM_RULES if r[0](machine, disp) and cnt >= r[1]), None)
            if rule is None:
                continue
            _, thr, genre, label = rule
            if await _try_offer(uid, ref=machine, cnt=cnt, thr=thr, genre=genre,
                                label=label, machine=machine, domain=None):
                fired += 1
                if genre == "idea-synthesis":
                    offered_idea.add(uid)

        # pass 2 — 灵感 DOMAIN (§8): most users record ideas as 随记 tagged 灵感
        # (create_note defaults there), not via a dedicated idea skill.
        dom_rows = (await db.execute(
            select(Asset.user_id, func.count(Asset.id))
            .where(Asset.created_at >= week_ago, Asset.domain == "灵感")
            .group_by(Asset.user_id)
        )).all()
        for uid, cnt in dom_rows:
            cnt = int(cnt or 0)
            if cnt < 5 or uid in offered_idea:
                continue
            if await _try_offer(uid, ref="domain:灵感", cnt=cnt, thr=5,
                                genre="idea-synthesis", label="灵感",
                                machine=None, domain="灵感"):
                fired += 1

        # ── §14.3 缺口 → Type A 提醒 ────────────────────────────────────────
        profiles = (await db.execute(
            select(RhythmProfile).where(RhythmProfile.confidence >= CONFIDENCE_GATE)
        )).scalars().all()

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
