from datetime import datetime, time

import pytest

from app.domains.reka.periods import (
    PERIOD_ELIGIBLE_AT,
    period_eligible,
    period_for_local,
)


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (datetime(2026, 8, 10, 0, 0), "凌晨"),
        (datetime(2026, 8, 10, 5, 59, 59), "凌晨"),
        (datetime(2026, 8, 10, 6, 0), "上午"),
        (datetime(2026, 8, 10, 11, 59, 59), "上午"),
        (datetime(2026, 8, 10, 12, 0), "中午"),
        (datetime(2026, 8, 10, 12, 59, 59), "中午"),
        (datetime(2026, 8, 10, 13, 0), "下午"),
        (datetime(2026, 8, 10, 17, 59, 59), "下午"),
        (datetime(2026, 8, 10, 18, 0), "晚上"),
        (datetime(2026, 8, 10, 23, 59, 59), "晚上"),
    ],
)
def test_period_for_local_uses_only_the_five_product_periods(value, expected):
    assert period_for_local(value) == expected


def test_period_eligibility_uses_fixed_second_half_boundaries():
    assert PERIOD_ELIGIBLE_AT == {
        "凌晨": time(3, 0),
        "上午": time(9, 0),
        "中午": time(12, 30),
        "下午": time(15, 30),
        "晚上": time(21, 0),
    }
    assert period_eligible("上午", datetime(2026, 8, 10, 8, 59)) is False
    assert period_eligible("上午", datetime(2026, 8, 10, 9, 0)) is True
    assert period_eligible("上午", datetime(2026, 8, 10, 12, 0)) is False


def test_period_none_uses_the_daily_21_clock_boundary():
    assert period_eligible(None, datetime(2026, 8, 10, 20, 59)) is False
    assert period_eligible(None, datetime(2026, 8, 10, 21, 0)) is True
