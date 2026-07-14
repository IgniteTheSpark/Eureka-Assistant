from ring_desktop.config import (
    load_config,
    resolve_action,
    resolve_vibration,
    save_config,
)
from ring_desktop.vibration import VibrationType


def test_resolve_app_specific():
    cfg = {
        "default": {"triple": {"type": "key", "value": "enter"}},
        "com.x": {"triple": {"type": "key", "value": "cmd+enter"}},
    }
    assert resolve_action(cfg, "com.x", "triple")["value"] == "cmd+enter"


def test_resolve_falls_back_to_default():
    cfg = {
        "default": {"longPress": {"type": "key", "value": "ctrl+u"}},
        "com.x": {"triple": {"type": "key", "value": "enter"}},
    }
    assert resolve_action(cfg, "com.x", "longPress")["value"] == "ctrl+u"


def test_resolve_unknown_app_uses_default():
    cfg = {"default": {"single": {"type": "key", "value": "space"}}}
    assert resolve_action(cfg, "com.unknown", "single")["value"] == "space"


def test_resolve_missing_returns_none():
    assert resolve_action({}, "com.x", "single") is None


def test_save_load_roundtrip(tmp_path):
    p = tmp_path / "config.json"
    cfg = {"default": {"triple": {"type": "key", "value": "enter"}}}
    save_config(str(p), cfg)
    assert load_config(str(p)) == cfg


def test_load_missing_file_returns_empty(tmp_path):
    assert load_config(str(tmp_path / "nope.json")) == {"default": {}}


def test_resolve_app_specific_vibration_event():
    cfg = {
        "default": {"vibration": {"taskComplete": "strong"}},
        "com.openai.codex": {
            "vibration": {"taskComplete": "continuous"}
        },
    }
    assert resolve_vibration(
        cfg, "com.openai.codex", "taskComplete"
    ) == VibrationType.CONTINUOUS


def test_resolve_vibration_falls_back_to_default():
    cfg = {
        "default": {"vibration": {"error": "gradient"}},
        "com.openai.codex": {},
    }
    assert resolve_vibration(
        cfg, "com.openai.codex", "error"
    ) == VibrationType.GRADIENT


def test_explicit_off_does_not_fall_back_to_default():
    cfg = {
        "default": {"vibration": {"taskComplete": "continuous"}},
        "com.openai.codex": {"vibration": {"taskComplete": "off"}},
    }
    assert resolve_vibration(cfg, "com.openai.codex", "taskComplete") is None


def test_missing_vibration_event_returns_none():
    assert resolve_vibration({}, "com.openai.codex", "taskComplete") is None
