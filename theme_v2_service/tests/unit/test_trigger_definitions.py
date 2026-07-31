from dataclasses import FrozenInstanceError

import pytest

from app.domains.triggers.definitions import TRIGGER_DEFINITIONS


def test_phase_one_definitions_are_closed():
    assert set(TRIGGER_DEFINITIONS) == {
        "proactive_summary",
        "pre_event_report",
    }
    proactive = TRIGGER_DEFINITIONS["proactive_summary"]
    assert proactive.signal_type == "asset_created"
    assert proactive.workflow_type == "report_generation"
    assert proactive.minimum_days == 7
    assert proactive.minimum_assets == 7
    pre_event = TRIGGER_DEFINITIONS["pre_event_report"]
    assert pre_event.signal_type == "time"
    assert pre_event.workflow_type == "report_generation"
    assert pre_event.minimum_days is None
    assert pre_event.minimum_assets is None


def test_trigger_definitions_are_immutable():
    with pytest.raises(FrozenInstanceError):
        TRIGGER_DEFINITIONS["proactive_summary"].minimum_days = 8
