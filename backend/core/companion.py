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
import re
from dataclasses import dataclass, field
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

# §14.5a PULL-only candidate sources (NEVER pushed — they have no rhythm/throttle
# path; they exist so the on-demand comprehensive set is complete).
OVERDUE_MAX = 5            # surface at most the N most-overdue todos (bounded)
OVERDUE_MAX_DAYS = 30      # …and only items overdue within a month (older = noise)
HABIT_REMINDER_MAX = 3     # at most N untimed-habit nudges per pull (bounded)
HABIT_LOOKBACK_DAYS = 14   # "a habit they normally log" = logged on ≥N distinct days…
HABIT_MIN_DAYS = 3         # …within the lookback window
# non-knowledge / action skills never become an untimed-habit "log it" reminder
# (a todo/event/contact isn't a daily journal you'd be nudged to keep up). Mirrors
# scan_once's _non_knowledge set + adds notes-like capture skills back in below.
_HABIT_EXCLUDE_SKILLS = ("todo", "event", "expense", "contact", "external_ref", "qa")


@dataclass
class OfferCandidate:
    """One §14.5a offer candidate — a PURE value (no DB row yet). The PULL
    endpoint UPSERTs each into a Nudge (find-or-create by user_id+natural_key) to
    mint a stable id; scan_once's PUSH path consumes only the `pushable` accumulation
    offers and applies its own §14.8 guardrails. `natural_key` reuses scan_once's
    existing 防重 identity ((kind, ref)) so re-PULL never duplicates."""
    kind: str                       # offer | overdue | habit_reminder
    ref: str                        # skill machine_name / domain:<d> / todo:<id> / habit:<skill>
    text: str                       # peek 一句话 (template, zero LLM)
    body: str = ""                  # expanded copy for the action bubble
    cta: str = ""                   # synthesize | view | log
    type: str = "B"                 # A 提醒 | B offer (Nudge.type)
    domain: str | None = None       # §8 life-domain (for the card's 域色点); None = unknown
    ttl_hours: int | None = None    # offer lifetime → Nudge.expires_at; None = end-of-day
    pushable: bool = False          # may scan_once push it? (only accumulation offers)
    # extra context the PUSH guardrail (_try_offer) needs; ignored by PULL upsert.
    push: dict = field(default_factory=dict)

    @property
    def natural_key(self) -> str:
        """Stable dedupe identity == scan_once's (kind, ref) 防重 key, flattened."""
        return f"{self.kind}:{self.ref}"


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


def _parse_due(v) -> datetime | None:
    """Parse a todo payload `due_date` → aware UTC datetime (mirrors
    morning_briefing._parse_due: bare date = end of that Beijing day; naive
    datetime = Beijing wall-clock)."""
    if not isinstance(v, str) or not v:
        return None
    try:
        s = v.strip()
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
            return datetime.fromisoformat(s + "T23:59:59+08:00")
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=_BEIJING)
    except ValueError:
        return None


async def compute_offer_candidates(db, user_id: str, now: datetime) -> list[OfferCandidate]:
    """§14.5a PULL — the COMPREHENSIVE current-state offer set for ONE user, as
    PURE candidates (no §14.8 throttle, no db.add, no SSE). Deterministic + cheap
    (a few indexed queries; ZERO LLM, §14.1).

    Five sources, each carrying scan_once's existing 防重 key as `natural_key`:
      1+2. 积累 → synthesize offers (dedicated 灵感/记账 skill; §8 domain rules) —
           `pushable=True` so scan_once's heartbeat may also push them (throttled);
      3.   逾期待办 — unfinished todos past due (reuse morning_briefing's overdue
           logic) → kind=overdue, PULL-only;
      4.   无时间习惯 — capture skills the user normally logs but hasn't today AND
           that have NO rhythm push path (no typical-hour nudge) → kind=habit_reminder,
           PULL-only (a timed habit is already covered by scan_once's rhythm_gap push).

    The PULL endpoint UPSERTs each candidate into a Nudge to mint an id; scan_once
    consumes only `pushable` ones. (Rhythm-gap reminders themselves stay PUSH-only:
    they are narrowly time-windowed + backoff-managed inside scan_once.)"""
    day_start_utc, _ = _bj_day_bounds(now)
    week_ago = now - timedelta(days=7)
    bj = now.astimezone(_BEIJING)
    out: list[OfferCandidate] = []

    # ── 1 积累 → synthesize offer · dedicated skills (real 灵感/记账 skill) ────────
    acc_rows = (await db.execute(
        select(GlobalSkill.name, UserSkill.display_name, func.count(Asset.id))
        .join(UserSkill, Asset.user_skill_id == UserSkill.id)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(Asset.user_id == user_id, Asset.created_at >= week_ago)
        .group_by(GlobalSkill.name, UserSkill.display_name)
    )).all()
    acc: dict[str, list] = {}                       # (machine) → [disp, cnt]
    for machine, disp, cnt in acc_rows:
        cur = acc.setdefault(machine, [disp, 0])
        cur[0] = cur[0] or disp
        cur[1] += int(cnt or 0)
    offered_idea = False                            # dedupe idea-synthesis across passes
    for machine, (disp, cnt) in acc.items():
        rule = next((r for r in _ACCUM_RULES if r[0](machine, disp) and cnt >= r[1]), None)
        if rule is None:
            continue
        _, thr, genre, label = rule
        out.append(OfferCandidate(
            kind="offer", ref=machine, type="B", cta="synthesize", domain=None,
            text=f"✨ 这周记了 {cnt} 条{label},要我帮你理一理?",
            body="点「帮我理一理」,Reka 把它们聚合成一份报告——共性、张力和下一步。不需要就划走,不打扰。",
            ttl_hours=OFFER_TTL_HOURS, pushable=True,
            push={"cnt": cnt, "thr": thr, "genre": genre, "label": label,
                  "machine": machine, "domain": None},
        ))
        if genre == "idea-synthesis":
            offered_idea = True

    # ── 2 积累 → synthesize offer · §8 DOMAIN rules (generic 随记 tagged by domain) ─
    domain_rules = (
        ("灵感", 5, "idea-synthesis", "灵感",
         "✨ 这周记了 {n} 条灵感,要我帮你理一理?",
         "点「帮我理一理」,Reka 把它们聚合成一份报告——共性、张力和下一步。不需要就划走,不打扰。"),
        ("学习", 8, "quiz", "学习内容",
         "📝 这周记了 {n} 条学习内容,要不要考考你?",
         "点「考考我」,Reka 用你记过的内容出一份小测——只考你记的,不考没学的。不想考就划走。"),
    )
    for domain, thr, genre, label, text_fmt, body in domain_rules:
        cnt = (await db.execute(
            select(func.count(Asset.id))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id, Asset.created_at >= week_ago,
                   Asset.domain == domain, ~GlobalSkill.name.in_(_HABIT_EXCLUDE_SKILLS))
        )).scalar() or 0
        cnt = int(cnt)
        if cnt < thr:
            continue
        if genre == "idea-synthesis" and offered_idea:
            continue  # already offered idea-synthesis via the dedicated-skill pass
        out.append(OfferCandidate(
            kind="offer", ref=f"domain:{domain}", type="B", cta="synthesize",
            domain=domain,
            text=text_fmt.format(n=cnt), body=body,
            ttl_hours=OFFER_TTL_HOURS, pushable=True,
            push={"cnt": cnt, "thr": thr, "genre": genre, "label": label,
                  "machine": None, "domain": domain},
        ))

    # ── 3 逾期待办 (PULL-only) — unfinished todos past due ────────────────────────
    #     reuse morning_briefing's overdue heuristic: not done, 0 < over ≤ 30d.
    todo_rows = (await db.execute(
        select(Asset)
        .join(UserSkill, Asset.user_skill_id == UserSkill.id)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(Asset.user_id == user_id, GlobalSkill.name == "todo")
        .order_by(Asset.created_at.desc()).limit(200)
    )).scalars().all()
    overdue: list[tuple[int, Asset, str]] = []
    for a in todo_rows:
        p = a.payload or {}
        done = p.get("status") == "done" or p.get("done") is True
        if done:
            continue
        due = _parse_due(p.get("due_date"))
        if due is None:
            continue
        over_days = (bj.date() - due.astimezone(_BEIJING).date()).days
        if 0 < over_days <= OVERDUE_MAX_DAYS:
            label = str(p.get("content") or p.get("title") or "待办")[:60]
            overdue.append((over_days, a, label))
    overdue.sort(key=lambda x: -x[0])               # most-overdue first
    for over_days, a, label in overdue[:OVERDUE_MAX]:
        out.append(OfferCandidate(
            kind="overdue", ref=f"todo:{a.id}", type="A", cta="view",
            domain=a.domain,
            text=f"⏰ 「{label}」拖了 {over_days} 天",
            body="这件事过了截止还没完成——不用愧疚,今天把它轻轻了结,后面都会顺。点一下去看看。",
        ))

    # ── 4 无时间习惯 (PULL-only) — capture skills normally logged, none today,
    #     and WITHOUT a rhythm push path (no typical-hour nudge) ──────────────────
    timed_skills = set((await db.execute(
        select(RhythmProfile.skill).where(
            RhythmProfile.user_id == user_id,
            RhythmProfile.confidence >= CONFIDENCE_GATE)
    )).scalars().all())                             # skills scan_once already pushes
    habit_rows = (await db.execute(
        select(GlobalSkill.name, UserSkill.display_name,
               func.count(func.distinct(func.date(Asset.created_at))).label("days"),
               func.max(Asset.created_at).label("last_at"))
        .join(UserSkill, Asset.user_skill_id == UserSkill.id)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(Asset.user_id == user_id,
               Asset.created_at >= now - timedelta(days=HABIT_LOOKBACK_DAYS),
               ~GlobalSkill.name.in_(_HABIT_EXCLUDE_SKILLS))
        .group_by(GlobalSkill.name, UserSkill.display_name)
    )).all()
    habit_cands: list[OfferCandidate] = []
    for machine, disp, days, last_at in habit_rows:
        if machine in timed_skills:
            continue                                # rhythm_gap push already covers it
        if int(days or 0) < HABIT_MIN_DAYS:
            continue                                # not really a habit yet
        if last_at is not None:
            if last_at.tzinfo is None:
                last_at = last_at.replace(tzinfo=timezone.utc)
            if last_at >= day_start_utc:
                continue                            # already logged today → no gap
        name = (disp or machine)[:8]
        habit_cands.append(OfferCandidate(
            kind="habit_reminder", ref=f"habit:{machine}", type="A", cta="log",
            domain=None,
            text=f"🔥 今天还没记{name}",
            body=f"你最近常记{name},今天还空着。要记就点一下,不记也没关系——别断了节奏就好。",
        ))
    out.extend(habit_cands[:HABIT_REMINDER_MAX])

    return out


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
                             genre: str, label: str, text: str, body: str,
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
                text=text, body=body,
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

        # §14.3 积累 → Type B offer — candidate compute now lives in the shared
        # pure `compute_offer_candidates` (also serving §14.5a PULL). scan_once
        # consumes only its `pushable` accumulation offers + applies the SAME
        # §14.8 guardrails via `_try_offer` (PULL-only kinds — 逾期待办/无时间习惯 —
        # are skipped here: they have no throttle/backoff push path). Candidate
        # order is preserved (dedicated-skill offers, then §8 domain offers), so
        # the push cadence is unchanged.
        cand_uids = (await db.execute(
            select(Asset.user_id).where(Asset.created_at >= week_ago).distinct()
        )).scalars().all()
        for uid in cand_uids:
            for c in await compute_offer_candidates(db, uid, now):
                if not c.pushable:
                    continue  # 逾期待办 / 无时间习惯 are PULL-only (no push throttle)
                p = c.push
                if await _try_offer(
                    uid, ref=c.ref, cnt=p["cnt"], thr=p["thr"], genre=p["genre"],
                    label=p["label"], text=c.text, body=c.body,
                    machine=p["machine"], domain=p["domain"]):
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
        # Daily offline recompute is ISOLATED from the per-tick scan: a failing
        # recompute (e.g. a transient DB hiccup, or rhythm_profiles missing during
        # a mid-deploy window) must NOT skip scan_once. Earlier both shared one try
        # with recompute first, so a recompute exception (a) skipped that tick's
        # scan AND (b) left last_recompute_day unset → it retried+failed every tick
        # → ALL nudges (incl. accumulation offers that don't even need profiles)
        # silently stopped. Two try blocks fix that.
        today_bj = datetime.now(timezone.utc).astimezone(_BEIJING).strftime("%Y-%m-%d")
        if today_bj != last_recompute_day:
            try:
                await recompute_all()
                await expire_stale()
                last_recompute_day = today_bj
            except asyncio.CancelledError:
                raise
            except Exception as exc:   # don't let a recompute failure block the scan
                log.warning("companion daily recompute failed: %s", exc)
        try:
            await scan_once()
        except asyncio.CancelledError:
            raise
        except Exception as exc:   # never let the loop die
            log.warning("companion scan failed: %s", exc)
        await asyncio.sleep(HEARTBEAT_INTERVAL_SEC)
