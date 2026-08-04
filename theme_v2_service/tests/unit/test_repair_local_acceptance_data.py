from datetime import datetime

from scripts.repair_local_acceptance_data import (
    WATER_REPAIRS,
    repair_payload,
)


def test_repair_payload_removes_only_the_known_acceptance_marker():
    polluted = {
        "distance": 5,
        "notes": "真实备注",
        "acceptance_marker": "theme-v2-acceptance-2026-08-04",
    }

    assert repair_payload(polluted) == {"distance": 5, "notes": "真实备注"}
    assert polluted["acceptance_marker"] == "theme-v2-acceptance-2026-08-04"


def test_repair_payload_is_idempotent_and_preserves_unrelated_marker_values():
    clean = {"distance": 5}
    unrelated = {"acceptance_marker": "user-authored-value"}

    assert repair_payload(repair_payload(clean)) == clean
    assert repair_payload(unrelated) == unrelated


def test_water_repairs_are_bounded_to_the_four_identified_assets():
    assert set(WATER_REPAIRS) == {
        "bad6911c-d87d-4879-b451-c822d8f12e52",
        "52d40b6f-da15-4b1e-bfb3-889c4199d1ad",
        "b441bb44-7ba5-475b-8e89-658612c750de",
        "e7339e76-31d6-40dd-96c4-10fadaac9597",
    }
    assert WATER_REPAIRS["bad6911c-d87d-4879-b451-c822d8f12e52"] == (
        None,
        datetime(2026, 8, 4, 16, 13, 25, 452365),
    )
    assert WATER_REPAIRS["52d40b6f-da15-4b1e-bfb3-889c4199d1ad"] == (
        "晚上",
        datetime(2026, 8, 4, 12, 0),
    )
    assert WATER_REPAIRS["b441bb44-7ba5-475b-8e89-658612c750de"] == (
        "下午",
        None,
    )
    assert WATER_REPAIRS["e7339e76-31d6-40dd-96c4-10fadaac9597"] == (
        "上午",
        None,
    )
