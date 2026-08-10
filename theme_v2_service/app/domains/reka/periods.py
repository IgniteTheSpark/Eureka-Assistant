from __future__ import annotations

from datetime import datetime, time


PERIODS = ("凌晨", "上午", "中午", "下午", "晚上")

PERIOD_ELIGIBLE_AT: dict[str, time] = {
    "凌晨": time(3, 0),
    "上午": time(9, 0),
    "中午": time(12, 30),
    "下午": time(15, 30),
    "晚上": time(21, 0),
}


def period_for_local(value: datetime) -> str:
    """Collapse a local wall-clock timestamp to the product's five Periods."""

    hour = value.hour
    if hour < 6:
        return "凌晨"
    if hour < 12:
        return "上午"
    if hour < 13:
        return "中午"
    if hour < 18:
        return "下午"
    return "晚上"


def period_eligible(period: str | None, local_now: datetime) -> bool:
    """Whether the current expected Period has entered its fixed second half."""

    if period is None:
        return local_now.time().replace(tzinfo=None) >= time(21, 0)
    if period not in PERIOD_ELIGIBLE_AT or period_for_local(local_now) != period:
        return False
    return local_now.time().replace(tzinfo=None) >= PERIOD_ELIGIBLE_AT[period]
