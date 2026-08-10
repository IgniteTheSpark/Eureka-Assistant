from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from app.domains.assets.todo_deadline import (
    normalize_new_todo_payload,
    normalize_todo_deadline,
)


SHANGHAI = ZoneInfo("Asia/Shanghai")


@pytest.mark.parametrize(
    ("due_date", "period", "effective_at", "occurred_at", "reference", "expected"),
    [
        (
            "2026-08-09T15:20:00+08:00",
            "下午",
            None,
            None,
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-09T15:20:00+08:00",
        ),
        (
            "2026-08-09",
            "上午",
            None,
            None,
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-09T11:00:00+08:00",
        ),
        (
            "2026-08-09",
            None,
            None,
            None,
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-09T18:00:00+08:00",
        ),
        (
            None,
            "晚上",
            None,
            None,
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-08T23:00:00+08:00",
        ),
        (
            None,
            "下午",
            None,
            None,
            datetime(2026, 8, 8, 17, 1, tzinfo=SHANGHAI),
            "2026-08-09T17:00:00+08:00",
        ),
        (
            None,
            "中午",
            datetime(2026, 8, 10, 0, 0, tzinfo=SHANGHAI),
            None,
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-10T12:30:00+08:00",
        ),
        (
            None,
            None,
            None,
            datetime(2026, 8, 9, 9, 35, tzinfo=SHANGHAI),
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-09T09:35:00+08:00",
        ),
        (
            "2026-08-09",
            "上午",
            None,
            datetime(2026, 8, 9, 9, 35, tzinfo=SHANGHAI),
            datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            "2026-08-09T09:35:00+08:00",
        ),
        (
            None,
            None,
            None,
            None,
            datetime(2026, 8, 8, 18, 0, tzinfo=SHANGHAI),
            "2026-08-08T18:00:00+08:00",
        ),
        (
            None,
            None,
            None,
            None,
            datetime(2026, 8, 8, 18, 0, 1, tzinfo=SHANGHAI),
            "2026-08-09T18:00:00+08:00",
        ),
    ],
)
def test_normalizes_todo_deadline(
    due_date,
    period,
    effective_at,
    occurred_at,
    reference,
    expected,
):
    actual = normalize_todo_deadline(
        due_date=due_date,
        period=period,
        effective_at=effective_at,
        occurred_at=occurred_at,
        reference_datetime=reference,
        timezone_name="Asia/Shanghai",
    )

    assert actual.isoformat() == expected


def test_naive_explicit_clock_is_interpreted_in_user_timezone():
    actual = normalize_todo_deadline(
        due_date="2026-08-09T15:20:00",
        period=None,
        effective_at=None,
        occurred_at=None,
        reference_datetime=datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
        timezone_name="Asia/Shanghai",
    )

    assert actual.isoformat() == "2026-08-09T15:20:00+08:00"


def test_invalid_explicit_due_date_is_rejected_instead_of_defaulted():
    with pytest.raises(ValueError, match="invalid todo due_date"):
        normalize_todo_deadline(
            due_date="明天下班前",
            period=None,
            effective_at=None,
            occurred_at=None,
            reference_datetime=datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
            timezone_name="Asia/Shanghai",
        )


def test_default_deadline_respects_dst_timezone():
    actual = normalize_todo_deadline(
        due_date="2026-03-09",
        period=None,
        effective_at=None,
        occurred_at=None,
        reference_datetime=datetime(
            2026,
            3,
            7,
            17,
            30,
            tzinfo=ZoneInfo("America/Los_Angeles"),
        ),
        timezone_name="America/Los_Angeles",
    )

    assert actual.isoformat() == "2026-03-09T18:00:00-07:00"


def test_unknown_timezone_uses_product_default():
    actual = normalize_todo_deadline(
        due_date="2026-08-09",
        period="凌晨",
        effective_at=None,
        occurred_at=None,
        reference_datetime=datetime(2026, 8, 8, 10, 0, tzinfo=SHANGHAI),
        timezone_name="Mars/Olympus_Mons",
    )

    assert actual.isoformat() == "2026-08-09T05:00:00+08:00"


def test_new_todo_starts_pending_even_when_deadline_has_passed():
    reference = datetime(2026, 8, 8, 18, 0, tzinfo=SHANGHAI)

    past = normalize_new_todo_payload(
        {"title": "补交材料", "due_date": "2026-08-08T17:59:00+08:00", "status": "pending"},
        period=None,
        effective_at=None,
        occurred_at=None,
        reference_datetime=reference,
        timezone_name="Asia/Shanghai",
    )
    boundary = normalize_new_todo_payload(
        {"title": "下班前提交"},
        period=None,
        effective_at=None,
        occurred_at=None,
        reference_datetime=reference,
        timezone_name="Asia/Shanghai",
    )

    assert past["status"] == "pending"
    assert boundary["status"] == "pending"
    assert boundary["due_date"] == "2026-08-08T18:00:00+08:00"


def test_today_date_only_rolls_to_tomorrow_after_default_cutoff():
    actual = normalize_todo_deadline(
        due_date="2026-08-08",
        period=None,
        effective_at=None,
        occurred_at=None,
        reference_datetime=datetime(2026, 8, 8, 18, 1, tzinfo=SHANGHAI),
        timezone_name="Asia/Shanghai",
    )

    assert actual.isoformat() == "2026-08-09T18:00:00+08:00"


def test_historical_date_only_stays_in_the_past_and_is_immediately_overdue():
    reference = datetime(2026, 8, 8, 19, 0, tzinfo=SHANGHAI)

    actual = normalize_todo_deadline(
        due_date="2026-08-07",
        period=None,
        effective_at=None,
        occurred_at=None,
        reference_datetime=reference,
        timezone_name="Asia/Shanghai",
    )

    assert actual.isoformat() == "2026-08-07T18:00:00+08:00"
    assert actual < reference
