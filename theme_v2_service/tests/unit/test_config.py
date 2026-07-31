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
    ):
        monkeypatch.delenv(name, raising=False)

    settings = Settings()

    assert settings.api_port == 8000
    assert settings.database_url.endswith("/eureka_theme_v2")
    assert settings.worker_poll_seconds == 0.5
    assert settings.job_lease_seconds == 60
    assert settings.report_planner_available() is False
    assert settings.report_pipeline_available() is False


def test_fake_provider_workflows_remain_available_only_in_test_environment():
    settings = Settings(env="test", jwt_secret="test-only-secret")

    assert settings.report_planner_available() is True
    assert settings.report_pipeline_available() is True
