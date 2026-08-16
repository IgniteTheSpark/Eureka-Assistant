import pytest

from app.domains.reminders.preferences import normalize_reminder_offsets


def test_missing_reminder_offsets_use_product_default_when_requested():
    assert normalize_reminder_offsets(None, missing_uses_default=True) == [15]


def test_explicit_empty_reminder_offsets_disable_reminders():
    assert normalize_reminder_offsets([], missing_uses_default=True) == []


def test_reminder_offsets_are_sorted_and_deduplicated():
    assert normalize_reminder_offsets([60, 15, 60, 0]) == [0, 15, 60]


@pytest.mark.parametrize("value", [[-1], [15.5], [True], ["15"], "15"])
def test_invalid_reminder_offsets_are_rejected(value):
    with pytest.raises(ValueError, match="reminder offsets"):
        normalize_reminder_offsets(value)
