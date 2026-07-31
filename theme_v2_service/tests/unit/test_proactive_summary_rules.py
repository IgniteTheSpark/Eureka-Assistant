from datetime import date, datetime, timedelta

import pytest

from app.domains.triggers.proactive_summary import (
    ActiveExecutionSnapshot,
    ProactiveSnapshot,
    decide_proactive_summary,
)


NOW = datetime(2026, 7, 31, 16, 30, 0)
LOCAL_DATE = date(2026, 8, 1)


def _snapshot(
    *,
    age_days: int = 7,
    asset_count: int = 7,
    revision: int | None = None,
    last_notified_local_date: date | None = None,
    dismissed_until: datetime | None = None,
    suppressed_until: datetime | None = None,
    new_asset_arrived: bool = True,
) -> ProactiveSnapshot:
    return ProactiveSnapshot(
        cycle_started_at=NOW - timedelta(days=age_days),
        new_asset_count=asset_count,
        active_execution=(
            ActiveExecutionSnapshot(revision=revision)
            if revision is not None
            else None
        ),
        last_notified_local_date=last_notified_local_date,
        dismissed_until=dismissed_until,
        proactive_suppressed_until=suppressed_until,
        new_asset_arrived=new_asset_arrived,
    )


@pytest.mark.parametrize(
    ("snapshot", "creates", "revision", "notifies"),
    [
        (_snapshot(age_days=2, asset_count=7), False, None, False),
        (_snapshot(age_days=7, asset_count=3), False, None, False),
        (_snapshot(age_days=7, asset_count=7), True, 1, True),
        (_snapshot(age_days=20, asset_count=7), True, 1, True),
    ],
)
def test_initial_threshold_requires_age_and_count(
    snapshot,
    creates,
    revision,
    notifies,
):
    decision = decide_proactive_summary(
        snapshot,
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert decision.create_execution is creates
    assert decision.append_asset is True
    assert decision.next_revision == revision
    assert decision.should_notify is notifies
    assert decision.notification_local_date == (
        LOCAL_DATE if notifies else None
    )


def test_available_execution_updates_without_same_day_notification():
    decision = decide_proactive_summary(
        _snapshot(revision=1, last_notified_local_date=LOCAL_DATE),
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert decision.create_execution is False
    assert decision.append_asset is True
    assert decision.next_revision == 2
    assert decision.should_notify is False
    assert decision.notification_local_date is None


def test_available_execution_notifies_on_next_local_day():
    decision = decide_proactive_summary(
        _snapshot(
            revision=4,
            last_notified_local_date=LOCAL_DATE - timedelta(days=1),
        ),
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert decision.next_revision == 5
    assert decision.should_notify is True
    assert decision.notification_local_date == LOCAL_DATE


@pytest.mark.parametrize(
    "blocked_field",
    ["dismissed_until", "suppressed_until"],
)
def test_dismissed_or_suppressed_execution_updates_without_notification(
    blocked_field,
):
    decision = decide_proactive_summary(
        _snapshot(
            revision=2,
            last_notified_local_date=LOCAL_DATE - timedelta(days=1),
            **{blocked_field: NOW + timedelta(seconds=1)},
        ),
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert decision.next_revision == 3
    assert decision.should_notify is False


def test_expired_dismiss_does_nothing_without_new_asset():
    decision = decide_proactive_summary(
        _snapshot(
            revision=2,
            last_notified_local_date=LOCAL_DATE - timedelta(days=7),
            dismissed_until=NOW - timedelta(seconds=1),
            new_asset_arrived=False,
        ),
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert decision.create_execution is False
    assert decision.append_asset is False
    assert decision.next_revision is None
    assert decision.should_notify is False


def test_expired_dismiss_notifies_on_first_new_asset():
    decision = decide_proactive_summary(
        _snapshot(
            revision=2,
            last_notified_local_date=LOCAL_DATE - timedelta(days=7),
            dismissed_until=NOW,
        ),
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert decision.next_revision == 3
    assert decision.should_notify is True
    assert decision.notification_local_date == LOCAL_DATE
