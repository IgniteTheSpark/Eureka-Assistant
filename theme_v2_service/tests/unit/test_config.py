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
    ):
        monkeypatch.delenv(name, raising=False)

    settings = Settings()

    assert settings.api_port == 8000
    assert settings.database_url.endswith("/eureka_theme_v2")
    assert settings.worker_poll_seconds == 0.5
    assert settings.job_lease_seconds == 60
    assert settings.report_planner_available() is False
    assert settings.report_pipeline_available() is False
    assert settings.tencent_asr_service_base_url == "https://pre.card.biz"
    assert settings.capture_asr_poll_interval_seconds == 5
    assert settings.capture_asr_poll_timeout_seconds == 1800
    assert settings.capture_provider_timeout_seconds == 20
    assert settings.capture_agent_enabled is False
    assert settings.capture_agent_model is None


def test_fake_provider_workflows_remain_available_only_in_test_environment():
    settings = Settings(env="test", jwt_secret="test-only-secret")

    assert settings.report_planner_available() is True
    assert settings.report_pipeline_available() is True
