from pydantic import ValidationError

from app.config import Settings


def test_prod_rejects_dev_secret():
    try:
        Settings(
            env="prod",
            database_url="mysql://u:p@mysql/db",
            jwt_secret="dev-insecure-change-me",
        )
    except ValidationError:
        return
    raise AssertionError("prod must reject the development JWT secret")


def test_theme_v2_defaults_are_isolated(monkeypatch):
    for name in (
        "ENV",
        "API_PORT",
        "DATABASE_URL",
        "JWT_SECRET",
        "WORKER_POLL_SECONDS",
        "JOB_LEASE_SECONDS",
        "MEDIA_ROOT",
        "DEFAULT_USER_TIMEZONE",
        "TENCENT_ASR_SERVICE_BASE_URL",
        "CAPTURE_ASR_POLL_INTERVAL_SECONDS",
        "CAPTURE_ASR_POLL_TIMEOUT_SECONDS",
        "CAPTURE_PROVIDER_TIMEOUT_SECONDS",
        "CAPTURE_AGENT_ENABLED",
        "CAPTURE_AGENT_MODEL",
        "CAPTURE_AGENT_API_KEY",
        "CAPTURE_AGENT_TIMEOUT_SECONDS",
        "CAPTURE_FLASH_WAIT_SECONDS",
        "CAPTURE_FLASH_POLL_INTERVAL_SECONDS",
        "REPORT_PLANNER_ENABLED",
        "REPORT_PIPELINE_ENABLED",
        "REPORT_PLANNER_MODEL",
        "REPORT_GENERATOR_MODEL",
        "REPORT_PROVIDER_API_KEY",
        "REPORT_WEB_ENABLED",
        "REPORT_WEB_MODEL",
        "REPORT_WEB_API_URL",
        "REPORT_WEB_API_KEY",
        "REPORT_WEB_TIMEOUT_SECONDS",
        "REPORT_ILLUSTRATION_ENABLED",
        "REPORT_ILLUSTRATION_MODEL",
        "REPORT_ILLUSTRATION_API_URL",
        "REPORT_ILLUSTRATION_API_KEY",
        "REPORT_ILLUSTRATION_TIMEOUT_SECONDS",
    ):
        monkeypatch.delenv(name, raising=False)

    settings = Settings()

    assert settings.api_port == 8000
    assert settings.database_url.endswith("/eureka_theme_v2")
    assert settings.worker_poll_seconds == 0.5
    assert settings.job_lease_seconds == 60
    assert settings.report_planner_available() is False
    assert settings.report_pipeline_available() is False
    assert settings.report_web_enabled is False
    assert settings.report_web_model == "deepseek-v4-flash"
    assert settings.report_web_api_url == "https://api.deepseek.com"
    assert settings.report_web_api_key_value() is None
    assert settings.report_web_available() is False
    assert settings.tencent_asr_service_base_url == "https://pre.card.biz"
    assert settings.capture_asr_poll_interval_seconds == 5
    assert settings.capture_asr_poll_timeout_seconds == 1800
    assert settings.capture_provider_timeout_seconds == 20
    assert settings.capture_agent_enabled is False
    assert settings.capture_agent_model is None
    assert settings.capture_flash_wait_seconds == 20
    assert settings.capture_flash_poll_interval_seconds == 0.05
    assert settings.report_illustration_available() is False


def test_fake_provider_workflows_remain_available_only_in_test_environment():
    settings = Settings(env="test", jwt_secret="test-only-secret")

    assert settings.report_planner_available() is True
    assert settings.report_pipeline_available() is True


def test_enabled_report_text_providers_require_shared_key():
    settings = Settings(
        jwt_secret="test-secret",
        report_planner_enabled=True,
        report_pipeline_enabled=True,
        report_planner_model="deepseek/deepseek-chat",
        report_generator_model="deepseek/deepseek-chat",
        report_provider_api_key="",
        report_web_enabled=False,
    )

    assert settings.provider_readiness_errors() == [
        "REPORT_PROVIDER_API_KEY is required",
    ]


def test_report_web_key_falls_back_to_shared_report_key():
    settings = Settings(
        jwt_secret="test-secret",
        report_web_enabled=True,
        report_provider_api_key="shared-secret",
    )

    assert settings.report_web_api_key_value() == "shared-secret"
    assert settings.report_web_available() is True
    assert settings.provider_readiness_errors() == []


def test_enabled_report_web_search_requires_key_and_http_url():
    missing_key = Settings(
        jwt_secret="test-secret",
        report_planner_enabled=False,
        report_pipeline_enabled=False,
        report_web_enabled=True,
        report_provider_api_key="",
        report_web_api_key="",
    )
    invalid_url = Settings(
        jwt_secret="test-secret",
        report_planner_enabled=False,
        report_pipeline_enabled=False,
        report_web_enabled=True,
        report_web_api_key="secret",
        report_web_api_url="file:///tmp/search",
    )

    assert missing_key.provider_readiness_errors() == [
        "REPORT_WEB_API_KEY or REPORT_PROVIDER_API_KEY is required",
    ]
    assert invalid_url.provider_readiness_errors() == [
        "REPORT_WEB_API_URL must be an absolute HTTP(S) URL",
    ]


def test_enabled_report_illustration_requires_dedicated_ark_configuration():
    missing = Settings(
        jwt_secret="test-secret",
        report_illustration_enabled=True,
        report_illustration_model="",
        report_illustration_api_url="",
        report_illustration_api_key="",
    )
    invalid_url = Settings(
        jwt_secret="test-secret",
        report_illustration_enabled=True,
        report_illustration_model="doubao-seedream-4-5-251128",
        report_illustration_api_url="file:///tmp/images",
        report_illustration_api_key="ark-secret",
    )

    assert missing.provider_readiness_errors() == [
        "REPORT_ILLUSTRATION_MODEL is required",
        "REPORT_ILLUSTRATION_API_URL is required",
        "REPORT_ILLUSTRATION_API_KEY is required",
    ]
    assert invalid_url.provider_readiness_errors() == [
        "REPORT_ILLUSTRATION_API_URL must be an absolute HTTP(S) URL",
    ]


def test_report_illustration_availability_uses_dedicated_key():
    settings = Settings(
        jwt_secret="test-secret",
        report_illustration_enabled=True,
        report_illustration_model="doubao-seedream-4-5-251128",
        report_illustration_api_url=(
            "https://ark.cn-beijing.volces.com/api/v3/images/generations"
        ),
        report_illustration_api_key="ark-secret",
        report_provider_api_key="deepseek-secret",
    )

    assert settings.report_illustration_available() is True
    assert settings.report_illustration_api_key == "ark-secret"
