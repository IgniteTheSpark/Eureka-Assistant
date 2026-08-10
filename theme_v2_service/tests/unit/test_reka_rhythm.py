from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from app.domains.reka.rhythm import (
    RhythmPattern,
    compute_patterns,
    rhythm_gap_candidate,
)


UTC = timezone.utc
SHANGHAI = "Asia/Shanghai"
SHANGHAI_ZONE = ZoneInfo(SHANGHAI)


def _utc(local_day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(
        2026,
        8,
        local_day,
        hour,
        minute,
        tzinfo=SHANGHAI_ZONE,
    ).astimezone(UTC)


def _daily_pattern(period: str | None = "上午") -> RhythmPattern:
    suffix = period or "any"
    return RhythmPattern(
        pattern_key=f"daily:{suffix}",
        cadence="daily",
        period=period,
        weekdays=(),
        confidence=0.8,
        sample_n=8,
    )


def test_compute_patterns_stays_silent_below_five_samples():
    timestamps = [_utc(day, 8, 13) for day in range(1, 5)]

    assert compute_patterns(timestamps, SHANGHAI) == []


def test_one_skill_can_learn_independent_period_patterns_without_exact_hours():
    timestamps = [
        *[_utc(day, 8, 13) for day in range(1, 6)],
        *[_utc(day, 16, 47) for day in range(1, 6)],
    ]

    patterns = compute_patterns(timestamps, SHANGHAI)

    assert [(p.pattern_key, p.cadence, p.period) for p in patterns] == [
        ("daily:上午", "daily", "上午"),
        ("daily:下午", "daily", "下午"),
    ]
    assert all(not hasattr(pattern, "hour") for pattern in patterns)


def test_scattered_periods_can_learn_one_daily_any_period_pattern():
    timestamps = [
        _utc(1, 4),
        _utc(2, 8),
        _utc(3, 12),
        _utc(4, 16),
        _utc(5, 20),
    ]

    assert compute_patterns(timestamps, SHANGHAI) == [
        RhythmPattern(
            pattern_key="daily:any",
            cadence="daily",
            period=None,
            weekdays=(),
            confidence=0.5,
            sample_n=5,
        )
    ]


def test_stable_weekday_records_learn_a_weekly_period_pattern():
    first = datetime(2026, 7, 8, 11, 0, tzinfo=UTC)
    timestamps = [first + timedelta(days=7 * index) for index in range(5)]

    patterns = compute_patterns(timestamps, SHANGHAI)

    assert patterns == [
        RhythmPattern(
            pattern_key="weekly:2:晚上",
            cadence="weekly",
            period="晚上",
            weekdays=(2,),
            confidence=0.5,
            sample_n=5,
        )
    ]


def test_weekly_gap_uses_expected_weekday_and_period_boundary():
    pattern = RhythmPattern(
        pattern_key="weekly:2:晚上",
        cadence="weekly",
        period="晚上",
        weekdays=(2,),
        confidence=0.8,
        sample_n=6,
    )
    history = [
        datetime(2026, 7, 8 + 7 * index, 19, tzinfo=SHANGHAI_ZONE).astimezone(UTC)
        for index in range(4)
    ]
    early = datetime(2026, 8, 5, 20, 59, tzinfo=SHANGHAI_ZONE).astimezone(UTC)
    eligible = datetime(2026, 8, 5, 21, 0, tzinfo=SHANGHAI_ZONE).astimezone(UTC)

    assert rhythm_gap_candidate(
        pattern,
        history,
        now=early,
        timezone_name=SHANGHAI,
    ) is None
    candidate = rhythm_gap_candidate(
        pattern,
        history,
        now=eligible,
        timezone_name=SHANGHAI,
    )

    assert candidate is not None
    assert candidate.cycle_key == "2026-W32"


def test_three_completed_weekly_cycles_restore_a_dismissed_pattern():
    pattern = RhythmPattern(
        pattern_key="weekly:2:晚上",
        cadence="weekly",
        period="晚上",
        weekdays=(2,),
        confidence=0.8,
        sample_n=6,
    )
    dismissed_at = datetime(2026, 8, 5, 21, 5, tzinfo=SHANGHAI_ZONE).astimezone(UTC)
    records = [
        datetime(2026, 8, day, 19, tzinfo=SHANGHAI_ZONE).astimezone(UTC)
        for day in (12, 19, 26)
    ]
    now = datetime(2026, 9, 2, 21, tzinfo=SHANGHAI_ZONE).astimezone(UTC)

    candidate = rhythm_gap_candidate(
        pattern,
        records,
        now=now,
        timezone_name=SHANGHAI,
        dismissed_at=dismissed_at,
    )

    assert candidate is not None
    assert candidate.cycle_key == "2026-W36"


def test_daily_period_gap_waits_for_second_half_and_is_pattern_scoped():
    pattern = _daily_pattern("上午")
    history = [_utc(day, 8, 20) for day in range(1, 10)]

    assert (
        rhythm_gap_candidate(
            pattern,
            history,
            now=_utc(10, 8, 59),
            timezone_name=SHANGHAI,
        )
        is None
    )
    candidate = rhythm_gap_candidate(
        pattern,
        history,
        now=_utc(10, 9, 0),
        timezone_name=SHANGHAI,
    )
    assert candidate is not None
    assert candidate.cycle_key == "2026-08-10"

    afternoon_only = [*history, _utc(10, 16, 0)]
    assert (
        rhythm_gap_candidate(
            pattern,
            afternoon_only,
            now=_utc(10, 10, 0),
            timezone_name=SHANGHAI,
        )
        is not None
    )
    morning_completed = [*history, _utc(10, 8, 30)]
    assert (
        rhythm_gap_candidate(
            pattern,
            morning_completed,
            now=_utc(10, 10, 0),
            timezone_name=SHANGHAI,
        )
        is None
    )


def test_three_consecutive_completed_cycles_reactivate_a_dismissed_pattern():
    pattern = _daily_pattern("上午")
    dismissed_at = _utc(1, 9, 5)
    records = [_utc(day, 8, 0) for day in (2, 3, 4)]

    candidate = rhythm_gap_candidate(
        pattern,
        records,
        now=_utc(5, 10, 0),
        timezone_name=SHANGHAI,
        dismissed_at=dismissed_at,
    )

    assert candidate is not None
    assert candidate.cycle_key == "2026-08-05"


def test_missed_cycle_resets_rhythm_reactivation_streak():
    pattern = _daily_pattern("上午")
    dismissed_at = _utc(1, 9, 5)
    records = [_utc(day, 8, 0) for day in (2, 4, 5)]

    assert (
        rhythm_gap_candidate(
            pattern,
            records,
            now=_utc(6, 10, 0),
            timezone_name=SHANGHAI,
            dismissed_at=dismissed_at,
        )
        is None
    )


def test_old_dismissal_cannot_suppress_again_after_reactivation_succeeds():
    pattern = _daily_pattern("上午")
    dismissed_at = _utc(1, 9, 5)
    records = [_utc(day, 8, 0) for day in (2, 3, 4)]

    candidate = rhythm_gap_candidate(
        pattern,
        records,
        now=_utc(6, 10, 0),
        timezone_name=SHANGHAI,
        dismissed_at=dismissed_at,
    )

    assert candidate is not None
    assert candidate.cycle_key == "2026-08-06"
