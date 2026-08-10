from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.domains.capture.temporal import extract_temporal_hints


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
