from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from statistics import median
from zoneinfo import ZoneInfo

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, UserSkill
from app.domains.reka.models import Nudge, RhythmProfile
from app.domains.reka.periods import PERIODS, period_eligible, period_for_local


MIN_SAMPLES = 5
CONFIDENCE_GATE = 0.45


@dataclass(frozen=True)
class RhythmPattern:
    pattern_key: str
    cadence: str
    period: str | None
    weekdays: tuple[int, ...]
    confidence: float
    sample_n: int


@dataclass(frozen=True)
class RhythmGap:
    pattern_key: str
    cycle_key: str
    period: str | None


@dataclass(frozen=True)
class RhythmCandidate:
    skill: str
    display_name: str
    pattern_key: str
    cadence: str
    period: str | None
    weekdays: tuple[int, ...]
    confidence: float
    sample_n: int
    cycle_key: str
    natural_key: str
    ref: str


def _local(value: datetime, zone: ZoneInfo) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(zone)


def _median_gap_days(values: list[datetime]) -> tuple[float, list[int]] | None:
    dates = sorted({value.date() for value in values})
    gaps = [(right - left).days for left, right in zip(dates, dates[1:])]
    positive = [gap for gap in gaps if gap > 0]
    if not positive:
        return None
    return float(median(positive)), positive


def _gap_regularity(gaps: list[int], target: float) -> float:
    deviations = [abs(gap - target) for gap in gaps]
    if not deviations or target <= 0:
        return 0.0
    return max(0.0, 1.0 - float(median(deviations)) / target)


def _pattern_for(values: list[datetime], period: str | None) -> RhythmPattern | None:
    if len(values) < MIN_SAMPLES:
        return None
    gap_result = _median_gap_days(values)
    if gap_result is None:
        return None
    median_gap, gaps = gap_result
    cadence: str
    weekdays: tuple[int, ...]
    weekday_score = 1.0
    if median_gap <= 2:
        cadence = "daily"
        weekdays = ()
        target_gap = 1.0
    elif 5 <= median_gap <= 9:
        cadence = "weekly"
        counts = Counter(value.weekday() for value in values)
        weekday, count = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0]
        weekday_score = count / len(values)
        if weekday_score < 0.6:
            return None
        weekdays = (weekday,)
        target_gap = 7.0
    else:
        return None

    sample_score = min(1.0, len(values) / 10)
    confidence = round(
        sample_score * _gap_regularity(gaps, target_gap) * weekday_score,
        3,
    )
    if confidence < CONFIDENCE_GATE:
        return None
    suffix = period or "any"
    if cadence == "weekly":
        suffix = f"{weekdays[0]}:{suffix}"
    return RhythmPattern(
        pattern_key=f"{cadence}:{suffix}",
        cadence=cadence,
        period=period,
        weekdays=weekdays,
        confidence=confidence,
        sample_n=len(values),
    )


def compute_patterns(
    timestamps: list[datetime],
    timezone_name: str,
) -> list[RhythmPattern]:
    """Learn deterministic Period-only daily/weekly patterns from captures."""

    zone = ZoneInfo(timezone_name)
    local_values = sorted(_local(value, zone) for value in timestamps if value is not None)
    by_period: dict[str, list[datetime]] = {period: [] for period in PERIODS}
    for value in local_values:
        by_period[period_for_local(value)].append(value)

    patterns = [
        pattern
        for period in PERIODS
        if (pattern := _pattern_for(by_period[period], period)) is not None
    ]
    if patterns:
        return patterns
    any_period = _pattern_for(local_values, None)
    return [any_period] if any_period is not None else []


def _cycle_key(pattern: RhythmPattern, local_now: datetime) -> str:
    if pattern.cadence == "weekly":
        iso_year, iso_week, _ = local_now.isocalendar()
        return f"{iso_year}-W{iso_week:02d}"
    return local_now.date().isoformat()


def _record_matches_cycle(
    pattern: RhythmPattern,
    local_record: datetime,
    *,
    cycle_start: date,
    cycle_end: date,
) -> bool:
    if not cycle_start <= local_record.date() < cycle_end:
        return False
    if pattern.weekdays and local_record.weekday() not in pattern.weekdays:
        return False
    return pattern.period is None or period_for_local(local_record) == pattern.period


def _current_cycle_bounds(pattern: RhythmPattern, local_now: datetime) -> tuple[date, date]:
    if pattern.cadence == "weekly":
        start = local_now.date() - timedelta(days=local_now.weekday())
        return start, start + timedelta(days=7)
    start = local_now.date()
    return start, start + timedelta(days=1)


def _eligible_now(pattern: RhythmPattern, local_now: datetime) -> bool:
    if pattern.weekdays and local_now.weekday() not in pattern.weekdays:
        return False
    return period_eligible(pattern.period, local_now)


def _past_expected_cycles(
    pattern: RhythmPattern,
    *,
    dismissed_local: datetime,
    current_local: datetime,
) -> list[tuple[date, date]]:
    current_start, _ = _current_cycle_bounds(pattern, current_local)
    if pattern.cadence == "weekly":
        dismissed_week = dismissed_local.date() - timedelta(days=dismissed_local.weekday())
        cursor = dismissed_week + timedelta(days=7)
        step = timedelta(days=7)
    else:
        cursor = dismissed_local.date() + timedelta(days=1)
        step = timedelta(days=1)
    cycles: list[tuple[date, date]] = []
    while cursor < current_start:
        if pattern.cadence != "daily" or not pattern.weekdays or cursor.weekday() in pattern.weekdays:
            cycles.append((cursor, cursor + step))
        cursor += step
    return cycles


def _reactivated(
    pattern: RhythmPattern,
    local_records: list[datetime],
    *,
    dismissed_local: datetime,
    current_local: datetime,
) -> bool:
    cycles = _past_expected_cycles(
        pattern,
        dismissed_local=dismissed_local,
        current_local=current_local,
    )
    if len(cycles) < 3:
        return False
    streak = 0
    for start, end in cycles:
        completed = any(
            _record_matches_cycle(
                pattern,
                record,
                cycle_start=start,
                cycle_end=end,
            )
            for record in local_records
        )
        streak = streak + 1 if completed else 0
        if streak >= 3:
            return True
    return False


def rhythm_gap_candidate(
    pattern: RhythmPattern,
    timestamps: list[datetime],
    *,
    now: datetime,
    timezone_name: str,
    dismissed_at: datetime | None = None,
) -> RhythmGap | None:
    """Return the current pattern-scoped gap, respecting indefinite suppression."""

    zone = ZoneInfo(timezone_name)
    local_now = _local(now, zone)
    if not _eligible_now(pattern, local_now):
        return None
    local_records = [_local(value, zone) for value in timestamps if value is not None]
    cycle_start, cycle_end = _current_cycle_bounds(pattern, local_now)
    if any(
        _record_matches_cycle(
            pattern,
            record,
            cycle_start=cycle_start,
            cycle_end=cycle_end,
        )
        for record in local_records
    ):
        return None
    if dismissed_at is not None:
        dismissed_local = _local(dismissed_at, zone)
        if not _reactivated(
            pattern,
            local_records,
            dismissed_local=dismissed_local,
            current_local=local_now,
        ):
            return None
    return RhythmGap(
        pattern_key=pattern.pattern_key,
        cycle_key=_cycle_key(pattern, local_now),
        period=pattern.period,
    )


def _utc_naive(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc).replace(tzinfo=None)


def _pattern_json(pattern: RhythmPattern) -> dict:
    return {
        "pattern_key": pattern.pattern_key,
        "cadence": pattern.cadence,
        "period": pattern.period,
        "weekdays": list(pattern.weekdays),
        "confidence": pattern.confidence,
        "sample_n": pattern.sample_n,
    }


def _pattern_from_json(value: object) -> RhythmPattern | None:
    if not isinstance(value, dict):
        return None
    try:
        pattern = RhythmPattern(
            pattern_key=str(value["pattern_key"]),
            cadence=str(value["cadence"]),
            period=(str(value["period"]) if value.get("period") is not None else None),
            weekdays=tuple(int(day) for day in (value.get("weekdays") or [])),
            confidence=float(value["confidence"]),
            sample_n=int(value["sample_n"]),
        )
    except (KeyError, TypeError, ValueError):
        return None
    if pattern.cadence not in {"daily", "weekly"}:
        return None
    if pattern.period is not None and pattern.period not in PERIODS:
        return None
    return pattern


async def recompute_rhythm_profiles(
    session: AsyncSession,
    *,
    now: datetime,
    timezone_name: str,
) -> int:
    """Replace all stored profiles from the last 28 days of capture times."""

    cutoff = _utc_naive(now - timedelta(days=28))
    rows = (
        await session.execute(
            select(Asset.user_id, UserSkill.machine_name, Asset.created_at)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .where(
                Asset.created_at >= cutoff,
                ~UserSkill.machine_name.in_(("todo", "event")),
            )
        )
    ).all()
    series: dict[tuple[str, str], list[datetime]] = {}
    for user_id, skill, created_at in rows:
        if not skill or created_at is None:
            continue
        series.setdefault((user_id, skill), []).append(created_at)

    existing = {
        (profile.user_id, profile.skill): profile
        for profile in await session.scalars(select(RhythmProfile))
    }
    kept: set[tuple[str, str]] = set()
    computed_at = _utc_naive(now)
    for key, timestamps in sorted(series.items()):
        patterns = compute_patterns(timestamps, timezone_name)
        if not patterns:
            continue
        profile = existing.get(key)
        if profile is None:
            profile = RhythmProfile(
                user_id=key[0],
                skill=key[1],
                timezone_name=timezone_name,
                patterns_json=[],
                computed_at=computed_at,
            )
            session.add(profile)
        profile.timezone_name = timezone_name
        profile.patterns_json = [_pattern_json(pattern) for pattern in patterns]
        profile.computed_at = computed_at
        kept.add(key)

    stale = set(existing) - kept
    if stale:
        for user_id, skill in stale:
            await session.execute(
                delete(RhythmProfile).where(
                    RhythmProfile.user_id == user_id,
                    RhythmProfile.skill == skill,
                )
            )
    await session.flush()
    return len(kept)


async def collect_rhythm_candidates(
    session: AsyncSession,
    *,
    user_id: str,
    now: datetime,
    timezone_name: str,
) -> list[RhythmCandidate]:
    profiles = list(
        await session.scalars(
            select(RhythmProfile).where(
                RhythmProfile.user_id == user_id,
                RhythmProfile.timezone_name == timezone_name,
            )
        )
    )
    if not profiles:
        return []

    skills = {profile.skill for profile in profiles}
    rows = (
        await session.execute(
            select(UserSkill.machine_name, UserSkill.display_name, Asset.created_at)
            .join(Asset, Asset.user_skill_id == UserSkill.id)
            .where(
                Asset.user_id == user_id,
                UserSkill.machine_name.in_(skills),
                Asset.created_at >= _utc_naive(now - timedelta(days=28)),
            )
        )
    ).all()
    timestamps_by_skill: dict[str, list[datetime]] = {skill: [] for skill in skills}
    display_names: dict[str, str] = {}
    for skill, display_name, created_at in rows:
        timestamps_by_skill.setdefault(skill, []).append(created_at)
        display_names.setdefault(skill, display_name or skill)
    missing_display = skills - set(display_names)
    if missing_display:
        display_rows = (
            await session.execute(
                select(UserSkill.machine_name, UserSkill.display_name).where(
                    UserSkill.user_id == user_id,
                    UserSkill.machine_name.in_(missing_display),
                )
            )
        ).all()
        display_names.update(
            {skill: display_name or skill for skill, display_name in display_rows}
        )

    refs = {
        f"{profile.skill}:{pattern.pattern_key}"
        for profile in profiles
        for raw in (profile.patterns_json or [])
        if (pattern := _pattern_from_json(raw)) is not None
    }
    dismissals: dict[str, datetime] = {}
    if refs:
        dismissed = list(
            await session.scalars(
                select(Nudge)
                .where(
                    Nudge.user_id == user_id,
                    Nudge.kind == "rhythm_gap",
                    Nudge.status == "dismissed",
                    Nudge.ref.in_(refs),
                    Nudge.dismissed_at.is_not(None),
                )
                .order_by(Nudge.dismissed_at.desc())
            )
        )
        for nudge in dismissed:
            if nudge.dismissed_at is not None:
                dismissals.setdefault(nudge.ref, nudge.dismissed_at)

    candidates: list[RhythmCandidate] = []
    for profile in profiles:
        for raw in profile.patterns_json or []:
            pattern = _pattern_from_json(raw)
            if pattern is None or pattern.confidence < CONFIDENCE_GATE:
                continue
            ref = f"{profile.skill}:{pattern.pattern_key}"
            gap = rhythm_gap_candidate(
                pattern,
                timestamps_by_skill.get(profile.skill, []),
                now=now,
                timezone_name=timezone_name,
                dismissed_at=dismissals.get(ref),
            )
            if gap is None:
                continue
            candidates.append(
                RhythmCandidate(
                    skill=profile.skill,
                    display_name=display_names.get(profile.skill, profile.skill),
                    pattern_key=pattern.pattern_key,
                    cadence=pattern.cadence,
                    period=pattern.period,
                    weekdays=pattern.weekdays,
                    confidence=pattern.confidence,
                    sample_n=pattern.sample_n,
                    cycle_key=gap.cycle_key,
                    natural_key=(
                        f"rhythm:{profile.skill}:{pattern.pattern_key}:{gap.cycle_key}"
                    ),
                    ref=ref,
                )
            )
    return sorted(
        candidates,
        key=lambda candidate: (-candidate.confidence, candidate.skill, candidate.pattern_key),
    )
