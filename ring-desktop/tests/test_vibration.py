import pytest

from ring_desktop.vibration import VibrationType, build_immediate_frame


@pytest.mark.parametrize(
    ("vibration_type", "expected"),
    [
        (VibrationType.STRONG, bytes.fromhex("00 00 83 04 01 00")),
        (VibrationType.CONTINUOUS, bytes.fromhex("00 00 83 04 02 00")),
        (VibrationType.GRADIENT, bytes.fromhex("00 00 83 04 03 00")),
    ],
)
def test_build_immediate_frame(vibration_type, expected):
    assert build_immediate_frame(vibration_type) == expected


def test_build_immediate_frame_accepts_string():
    assert build_immediate_frame("continuous") == bytes.fromhex(
        "00 00 83 04 02 00"
    )


def test_build_immediate_frame_rejects_unknown_type():
    with pytest.raises(ValueError, match="Unknown vibration type"):
        build_immediate_frame("unknown")
