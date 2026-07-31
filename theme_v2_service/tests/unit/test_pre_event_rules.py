from datetime import datetime, timedelta
from types import SimpleNamespace

import pytest

from app.domains.triggers.pre_event_report import (
    is_pre_event_eligible,
    pre_event_dedupe_key,
    should_fire_pre_event,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


def _event(
    *,
    start_at: datetime,
    status: str = "scheduled",
    all_day: bool = False,
):
    return SimpleNamespace(
        id="event-1",
        start_at=start_at,
        status=status,
        all_day=all_day,
    )


@pytest.mark.parametrize(
    ("event", "eligible", "fires"),
    [
        (_event(start_at=NOW + timedelta(hours=1)), True, True),
        (_event(start_at=NOW + timedelta(minutes=20)), True, True),
        (_event(start_at=NOW + timedelta(hours=2)), True, False),
        (_event(start_at=NOW + timedelta(hours=1), all_day=True), False, False),
        (
            _event(start_at=NOW + timedelta(hours=1), status="cancelled"),
            False,
            False,
        ),
        (_event(start_at=NOW), False, False),
        (_event(start_at=NOW - timedelta(seconds=1)), False, False),
    ],
)
def test_pre_event_time_rule_matrix(event, eligible, fires):
    assert is_pre_event_eligible(event, NOW) is eligible
    assert should_fire_pre_event(event, NOW) is fires


def test_reschedule_changes_utc_dedupe_key():
    original = _event(start_at=NOW + timedelta(minutes=30))
    changed = _event(start_at=NOW + timedelta(minutes=45))

    assert pre_event_dedupe_key(original) == (
        "pre_event_report:event-1:2026-07-31T10:30:00Z"
    )
    assert pre_event_dedupe_key(changed) == (
        "pre_event_report:event-1:2026-07-31T10:45:00Z"
    )
