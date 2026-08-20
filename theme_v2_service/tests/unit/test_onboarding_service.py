"""Onboarding service unit tests (pure fingerprint/validation helpers)."""
import pytest

from app.domains.onboarding.service import (
    OnboardingError,
    _validate_custom_fields,
    machine_name_for,
)


def test_machine_name_for_includes_type_and_label():
    duration = {"key": "duration_min", "label": "时长", "type": "duration"}
    assert machine_name_for("跑步", [duration]) == machine_name_for(
        "跑步", [dict(duration)]
    )

    number = dict(duration, type="number")
    assert machine_name_for("跑步", [duration]) != machine_name_for(
        "跑步", [number]
    )

    relabeled = dict(duration, label="时长(分钟)")
    assert machine_name_for("跑步", [duration]) != machine_name_for(
        "跑步", [relabeled]
    )


def test_machine_name_for_is_case_and_order_insensitive():
    fields_a = [
        {"key": "Distance_KM", "label": "距离", "type": "number"},
        {"key": "location", "label": "地点", "type": "text"},
    ]
    fields_b = [
        {"key": "location", "label": "地点", "type": "text"},
        {"key": "distance_km", "label": "距离", "type": "number"},
    ]
    assert machine_name_for("跑步", fields_a) == machine_name_for("跑步", fields_b)


def test_machine_name_for_differs_by_category():
    fields = [{"key": "note", "label": "备注", "type": "text"}]
    assert machine_name_for("睡眠", fields) != machine_name_for("喝水", fields)


def test_validate_custom_fields_rejects_blank_names():
    with pytest.raises(OnboardingError):
        _validate_custom_fields([{"key": "", "label": "备注", "type": "text"}])
    with pytest.raises(OnboardingError):
        _validate_custom_fields([{"key": "note", "label": "  ", "type": "text"}])
    _validate_custom_fields([{"key": "note", "label": "备注", "type": "text"}])
