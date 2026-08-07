from types import SimpleNamespace

import pytest

from app.domains.capture.service import (
    _capture_display_phase,
    _capture_display_source,
)


@pytest.mark.parametrize(
    ("status", "expected"),
    [
        ("accepted", "receiving"),
        ("asr_processing", "transcribing"),
        ("asr_done", "understanding"),
        ("agent_processing", "understanding"),
        ("done", "done"),
        ("empty", "empty"),
        ("failed", "failed"),
    ],
)
def test_capture_status_has_one_normalized_display_phase(status, expected):
    assert _capture_display_phase(status) == expected


@pytest.mark.parametrize(
    ("source", "card_sn", "expected"),
    [
        ("voice", "ring", "ring"),
        ("realtime", "SN-W2", "card"),
        ("offline", "SN-W1", "card"),
        ("imported", "text", "audio_upload"),
    ],
)
def test_capture_source_is_projected_to_product_source(source, card_sn, expected):
    recording = SimpleNamespace(source=source, card_sn=card_sn)

    assert _capture_display_source(recording) == expected
