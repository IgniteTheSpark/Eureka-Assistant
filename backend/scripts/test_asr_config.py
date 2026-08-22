"""Focused checks for the server-only Qwen streaming ASR configuration.

Run from backend/:
    python -m scripts.test_asr_config
"""

from config import settings, validate_asr_settings


def _assert_refuses(fragment: str) -> None:
    try:
        validate_asr_settings()
    except RuntimeError as exc:
        assert fragment in str(exc), str(exc)
    else:
        raise AssertionError(f"ASR settings accepted invalid {fragment}")


def test_requires_api_key() -> None:
    settings.dashscope_api_key = ""
    settings.dashscope_asr_ws_url = (
        "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    )
    settings.ali_asr_model = "qwen-audio-3.0-asr-flash-streaming"
    _assert_refuses("DASHSCOPE_API_KEY")


def test_requires_secure_workspace_websocket() -> None:
    settings.dashscope_api_key = "sk-test-only"
    for invalid_url in (
        "",
        "https://workspace.cn-beijing.maas.aliyuncs.com/api/v1",
        "ws://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
        "wss://example.com/not-the-inference-path",
    ):
        settings.dashscope_asr_ws_url = invalid_url
        _assert_refuses("DASHSCOPE_ASR_WS_URL")


def test_requires_selected_model() -> None:
    settings.dashscope_api_key = "sk-test-only"
    settings.dashscope_asr_ws_url = (
        "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    )
    settings.ali_asr_model = "fun-asr-realtime"
    _assert_refuses("ALI_ASR_MODEL")


def test_accepts_selected_qwen_configuration() -> None:
    settings.dashscope_api_key = "sk-test-only"
    settings.dashscope_asr_ws_url = (
        "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    )
    settings.ali_asr_model = "qwen-audio-3.0-asr-flash-streaming"
    settings.asr_rate_limit_per_minute = 10
    validate_asr_settings()


def test_requires_positive_lifecycle_deadlines() -> None:
    settings.dashscope_api_key = "sk-test-only"
    settings.dashscope_asr_ws_url = (
        "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    )
    settings.ali_asr_model = "qwen-audio-3.0-asr-flash-streaming"
    settings.asr_rate_limit_per_minute = 10
    deadline_fields = (
        "asr_provider_start_timeout_seconds",
        "asr_provider_finalize_timeout_seconds",
        "asr_provider_cleanup_timeout_seconds",
    )
    originals = {name: getattr(settings, name) for name in deadline_fields}
    try:
        for name in deadline_fields:
            for field, value in originals.items():
                setattr(settings, field, value)
            setattr(settings, name, 0)
            _assert_refuses(name.upper())
    finally:
        for name, value in originals.items():
            setattr(settings, name, value)


def test_client_ready_deadline_exceeds_provider_start_margin() -> None:
    settings.dashscope_api_key = "sk-test-only"
    settings.dashscope_asr_ws_url = (
        "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    )
    settings.ali_asr_model = "qwen-audio-3.0-asr-flash-streaming"
    settings.asr_rate_limit_per_minute = 10
    original_start = settings.asr_provider_start_timeout_seconds
    original_client = settings.asr_client_ready_timeout_seconds
    try:
        settings.asr_provider_start_timeout_seconds = 9
        settings.asr_client_ready_timeout_seconds = 10
        _assert_refuses("ASR_CLIENT_READY_TIMEOUT_SECONDS")
    finally:
        settings.asr_provider_start_timeout_seconds = original_start
        settings.asr_client_ready_timeout_seconds = original_client


def main() -> None:
    original = (
        settings.dashscope_api_key,
        settings.dashscope_asr_ws_url,
        settings.ali_asr_model,
        settings.asr_rate_limit_per_minute,
        settings.asr_provider_start_timeout_seconds,
        settings.asr_provider_finalize_timeout_seconds,
        settings.asr_provider_cleanup_timeout_seconds,
        settings.asr_client_ready_timeout_seconds,
    )
    try:
        test_requires_api_key()
        test_requires_secure_workspace_websocket()
        test_requires_selected_model()
        test_requires_positive_lifecycle_deadlines()
        test_client_ready_deadline_exceeds_provider_start_margin()
        test_accepts_selected_qwen_configuration()
        print("PASS - Qwen streaming ASR configuration is fail-closed")
    finally:
        (
            settings.dashscope_api_key,
            settings.dashscope_asr_ws_url,
            settings.ali_asr_model,
            settings.asr_rate_limit_per_minute,
            settings.asr_provider_start_timeout_seconds,
            settings.asr_provider_finalize_timeout_seconds,
            settings.asr_provider_cleanup_timeout_seconds,
            settings.asr_client_ready_timeout_seconds,
        ) = original


if __name__ == "__main__":
    main()
