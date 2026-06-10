"""
core/rhythm — §14.2 节律 profile(统计,非 LLM).

Per (user, skill), summarize WHEN the user usually records — from nothing but
the timestamps of their real records:

- cadence        = median gap between consecutive records (minutes; outlier-proof)
- typical_hours  = peak record hours (Beijing), via a ±1h-smoothed 24-bin histogram
- weekdays       = concentrated weekdays (Mon=0); [] = no weekday pattern / all days
- confidence     = sample size × time-of-day concentration; the §14.3 trigger
                   refuses to nudge below threshold (数据不够别瞎猜)

This is deliberately `median()`-grade math, not a model: it's cheaper, more
accurate, auditable, and can't hallucinate a routine that isn't there (§14.2 —
「老人的吃药时间不能交给会编的模型」). Recomputed once a day by the companion
heartbeat (offline pass); the per-tick trigger only READS profiles.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from statistics import median
from typing import Optional

from sqlalchemy import delete, select

from db.database import AsyncSessionLocal
from db.models import Asset, GlobalSkill, RhythmProfile, UserSkill

log = logging.getLogger("eureka.rhythm")

_BEIJING = timezone(timedelta(hours=8))

LOOKBACK_DAYS = 28      # window the profile summarizes
MIN_SAMPLES = 5         # fewer records → no profile (cold start: stay silent)
# Skills that are not "habit recording" — no rhythm profile, never rhythm-nudged.
# (todo/event have their own explicit ahead-of-time reminders, §14.4.)
_EXCLUDED_SKILLS = {"external_ref", "qa", "contact", "todo", "event"}


def compute_profile(timestamps: list[datetime]) -> Optional[dict]:
    """Pure function: record timestamps (any tz-aware) → profile dict, or None
    when the sample is too thin. Separated from IO so it's unit-testable."""
    ts = sorted(t.astimezone(_BEIJING) for t in timestamps if t is not None)
    n = len(ts)
    if n < MIN_SAMPLES:
        return None

    # cadence — median inter-record gap (minutes; ≥1 so bulk imports don't read 0)
    gaps = [(b - a).total_seconds() / 60 for a, b in zip(ts, ts[1:]) if (b - a).total_seconds() > 0]
    cadence = max(1, int(median(gaps))) if gaps else None

    # time-of-day — 24-bin histogram, smoothed ±1h so 7:55/8:10 read as one peak.
    # Selection is on the SMOOTHED curve only: a peak hour is the center of a
    # ±1h window dense with records, even when that exact hour has none (e.g.
    # records split 13:00/15:00 → the true center 14 is a "saddle" with
    # counts[14]==0; requiring counts>0 there yielded an EMPTY typical_hours and
    # the trigger could never fire — found on real data).
    hours = [t.hour for t in ts]
    counts = [0] * 24
    for h in hours:
        counts[h] += 1
    smoothed = [counts[(h - 1) % 24] + counts[h] + counts[(h + 1) % 24] for h in range(24)]
    peak = max(range(24), key=lambda h: smoothed[h])
    concentration = smoothed[peak] / n  # share of records inside the 3h peak window
    typical = sorted(
        h for h in range(24) if smoothed[h] >= 0.85 * smoothed[peak]
    )[:3]

    # weekday — flag a concentrated subset (e.g. 周一三五); scattered → []
    wd_counts = [0] * 7
    for t in ts:
        wd_counts[t.weekday()] += 1
    nonzero = [d for d in range(7) if wd_counts[d] > 0]
    weekdays = nonzero if (n >= 8 and 0 < len(nonzero) <= 5) else []

    # confidence — enough samples AND a real time-of-day pattern
    confidence = round(min(1.0, n / 14) * concentration, 3)

    return {
        "cadence_minutes": cadence,
        "typical_hours": typical,
        "weekdays": weekdays,
        "confidence": confidence,
        "sample_n": n,
    }


async def recompute_all() -> int:
    """Daily offline pass (§14.2): rebuild rhythm_profiles from the last
    LOOKBACK_DAYS of assets. Returns the number of profiles written."""
    since = datetime.now(timezone.utc) - timedelta(days=LOOKBACK_DAYS)
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Asset.user_id, GlobalSkill.name, Asset.created_at)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.created_at >= since)
        )).all()

        series: dict[tuple[str, str], list[datetime]] = {}
        for uid, skill, created in rows:
            if not skill or skill in _EXCLUDED_SKILLS or created is None:
                continue
            t = created if created.tzinfo else created.replace(tzinfo=timezone.utc)
            series.setdefault((uid, skill), []).append(t)

        now = datetime.now(timezone.utc)
        written = 0
        touched_users: set[str] = set()
        kept: set[tuple[str, str]] = set()
        for (uid, skill), ts in series.items():
            prof = compute_profile(ts)
            if prof is None:
                continue
            await db.merge(RhythmProfile(user_id=uid, skill=skill, computed_at=now, **prof))
            kept.add((uid, skill))
            touched_users.add(uid)
            written += 1

        # Drop stale profiles for users we touched (skill went quiet → no profile,
        # so the trigger can't keep nudging a habit the user abandoned).
        for uid in touched_users:
            stale = (await db.execute(
                select(RhythmProfile.skill).where(RhythmProfile.user_id == uid)
            )).scalars().all()
            for skill in stale:
                if (uid, skill) not in kept:
                    await db.execute(delete(RhythmProfile).where(
                        RhythmProfile.user_id == uid, RhythmProfile.skill == skill))
        await db.commit()
    log.info("rhythm profiles recomputed: %d", written)
    return written
