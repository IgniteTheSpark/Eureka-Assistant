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


def main() -> None:
    original = (
        settings.dashscope_api_key,
        settings.dashscope_asr_ws_url,
        settings.ali_asr_model,
        settings.asr_rate_limit_per_minute,
    )
    try:
        test_requires_api_key()
        test_requires_secure_workspace_websocket()
        test_requires_selected_model()
        test_accepts_selected_qwen_configuration()
        print("PASS - Qwen streaming ASR configuration is fail-closed")
    finally:
        (
            settings.dashscope_api_key,
            settings.dashscope_asr_ws_url,
            settings.ali_asr_model,
            settings.asr_rate_limit_per_minute,
        ) = original


if __name__ == "__main__":
    main()
