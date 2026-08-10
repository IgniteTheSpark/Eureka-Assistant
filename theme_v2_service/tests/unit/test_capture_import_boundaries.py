import importlib.util
from pathlib import Path

import app.domains.capture.api as capture_api


def test_removed_capture_providers_are_not_importable():
    assert importlib.util.find_spec("app.domains.capture.providers_litellm") is None
    assert importlib.util.find_spec("app.domains.capture.chat") is None


def test_flash_chat_api_uses_the_unified_session_chat_pipeline():
    source = Path(capture_api.__file__).read_text(encoding="utf-8")

    assert "get_session_chat_provider" in source
    assert "prepare_chat_turn" in source
    assert "app.domains.capture.chat" not in source
