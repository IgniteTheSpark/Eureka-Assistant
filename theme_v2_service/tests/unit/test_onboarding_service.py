"""Onboarding service unit tests (pure fingerprint/validation helpers)."""
import pytest

from app.domains.onboarding.service import (
    OnboardingError,
    _catalog_fields,
    _confirmation_fingerprint,
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


def test_catalog_fields_rejects_unknown_empty_duplicate_and_unowned_keys():
    with pytest.raises(OnboardingError):
        _catalog_fields("sleep", ["hours"])
    with pytest.raises(OnboardingError):
        _catalog_fields("running", [])
    with pytest.raises(OnboardingError):
        _catalog_fields("running", ["distance_km", "distance_km"])
    with pytest.raises(OnboardingError):
        _catalog_fields("running", ["unknown"])


def test_catalog_fields_use_server_metadata_and_catalog_order():
    entry, fields = _catalog_fields(
        "running", ["duration_min", "distance_km"]
    )

    assert entry["label"] == "跑步"
    assert [field["key"] for field in fields] == [
        "distance_km",
        "duration_min",
    ]
    assert fields[0]["type"] == "number"


def test_confirmation_fingerprint_is_key_order_independent_and_content_bound():
    first = _confirmation_fingerprint(
        "skill-1", {"duration_min": 32, "distance_km": 5}
    )
    reordered = _confirmation_fingerprint(
        "skill-1", {"distance_km": 5, "duration_min": 32}
    )
    changed = _confirmation_fingerprint(
        "skill-1", {"distance_km": 6, "duration_min": 32}
    )

    assert first == reordered
    assert first != changed
