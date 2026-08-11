from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.domains.capture.temporal import (
    extract_temporal_hints,
    temporal_contexts_for_intents,
)


REFERENCE = datetime(2026, 8, 5, 0, 13, tzinfo=ZoneInfo("Asia/Shanghai"))


def test_extracts_just_now_as_precise_reference_time():
    hints = extract_temporal_hints("刚刚喝了200ml", REFERENCE)

    assert hints.occurred_at == REFERENCE
    assert hints.anchor_date == date(2026, 8, 5)
    assert hints.period is None


def test_extracts_relative_day_with_explicit_clock():
    hints = extract_temporal_hints("昨天晚上8点喝了300ml", REFERENCE)

    assert hints.occurred_at == datetime(
        2026,
        8,
        4,
        20,
        0,
        tzinfo=ZoneInfo("Asia/Shanghai"),
    )
    assert hints.anchor_date == date(2026, 8, 4)
    assert hints.period == "晚上"


def test_extracts_future_day_with_explicit_evening_clock():
    hints = extract_temporal_hints("明天晚上9点踢球", REFERENCE)

    assert hints.occurred_at == datetime(
        2026,
        8,
        6,
        21,
        0,
        tzinfo=ZoneInfo("Asia/Shanghai"),
    )
    assert hints.anchor_date == date(2026, 8, 6)
    assert hints.period == "晚上"


def test_keeps_fuzzy_period_without_inventing_a_clock():
    hints = extract_temporal_hints("昨天下午喝了600ml", REFERENCE)

    assert hints.anchor_date == date(2026, 8, 4)
    assert hints.period == "下午"
    assert hints.occurred_at is None


def test_yesterday_morning_keeps_date_and_period_without_fake_clock():
    hints = extract_temporal_hints("昨天早上买早餐花了8块", REFERENCE)

    assert hints.anchor_date == date(2026, 8, 4)
    assert hints.period == "上午"
    assert hints.occurred_at is None


def test_extracts_colon_clock_and_normalizes_midnight():
    hints = extract_temporal_hints("前天凌晨12:30醒了", REFERENCE)

    assert hints.occurred_at == datetime(
        2026,
        8,
        3,
        0,
        30,
        tzinfo=ZoneInfo("Asia/Shanghai"),
    )


def test_without_time_language_has_no_semantic_time_hint():
    hints = extract_temporal_hints("喝了200ml", REFERENCE)

    assert hints.anchor_date is None
    assert hints.period is None
    assert hints.occurred_at is None


def test_chinese_range_uses_inherited_afternoon_context():
    hints = extract_temporal_hints(
        "两点到两点半要见投资人",
        REFERENCE,
        inherited_period="下午",
    )

    assert hints.shape == "range"
    assert hints.start_at == datetime(
        2026, 8, 5, 14, 0, tzinfo=ZoneInfo("Asia/Shanghai")
    )
    assert hints.end_at == datetime(
        2026, 8, 5, 14, 30, tzinfo=ZoneInfo("Asia/Shanghai")
    )


def test_adjacent_clauses_inherit_latest_explicit_day_period():
    contexts = temporal_contexts_for_intents(
        "今天下午1点到1点半复盘，然后两点到两点半见面，然后4点到6点周会",
        [
            "今天下午1点到1点半复盘",
            "两点到两点半见面",
            "4点到6点周会",
        ],
        REFERENCE,
    )

    assert [context.period for context in contexts] == ["下午", "下午", "下午"]
    assert [context.anchor_date for context in contexts] == [
        date(2026, 8, 5),
        date(2026, 8, 5),
        date(2026, 8, 5),
    ]


def test_bare_range_keeps_both_am_pm_candidates():
    hints = extract_temporal_hints("4点到6点周会", REFERENCE)

    assert hints.shape == "range"
    assert hints.start_at is None
    assert [(start.hour, end.hour) for start, end in hints.interval_candidates] == [
        (4, 6),
        (16, 18),
    ]
