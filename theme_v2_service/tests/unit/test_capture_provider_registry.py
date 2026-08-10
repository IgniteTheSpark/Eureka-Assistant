from types import SimpleNamespace

from app.domains.capture.execution import UnavailableFlashExecutionProvider
from app.domains.capture.providers_legacy_flash import LiteLLMLegacyFlashProvider
from app.jobs.registry import build_capture_execution_provider


def _settings(*, enabled: bool, model: str = "deepseek/deepseek-chat"):
    return SimpleNamespace(
        capture_agent_enabled=enabled,
        capture_agent_model=model,
        capture_agent_api_key="secret",
        capture_agent_timeout_seconds=30,
    )


def test_registry_builds_the_single_production_capture_provider():
    provider = build_capture_execution_provider(_settings(enabled=True))

    assert type(provider) is LiteLLMLegacyFlashProvider


def test_registry_uses_explicit_unavailable_provider_when_disabled():
    provider = build_capture_execution_provider(_settings(enabled=False))

    assert type(provider) is UnavailableFlashExecutionProvider
