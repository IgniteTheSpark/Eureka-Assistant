"""Focused regression checks for startup secret validation.

Run inside the backend container:
    python -m scripts.test_config_validation
"""

from config import settings, validate_prod_secrets


def _configure(
    *,
    env: str,
    demo_reset_enabled: bool,
    jwt_secret: str,
    connected_apps_key: str = "",
) -> None:
    settings.env = env
    settings.demo_reset_enabled = demo_reset_enabled
    settings.jwt_secret = jwt_secret
    settings.connected_apps_key = connected_apps_key


def _assert_refuses(fragment: str) -> None:
    try:
        validate_prod_secrets()
    except RuntimeError as exc:
        assert fragment in str(exc), str(exc)
    else:
        raise AssertionError(f"startup validation accepted insecure {fragment}")


def test_reset_disabled_dev_allows_default_secret() -> None:
    _configure(
        env="dev",
        demo_reset_enabled=False,
        jwt_secret="dev-insecure-change-me",
    )
    validate_prod_secrets()


def test_reset_enabled_refuses_default_blank_and_short_secrets() -> None:
    for weak_secret in ("dev-insecure-change-me", "", "too-short"):
        _configure(
            env="dev",
            demo_reset_enabled=True,
            jwt_secret=weak_secret,
        )
        _assert_refuses("JWT_SECRET")


def test_reset_enabled_dev_allows_strong_secret_without_prod_only_key() -> None:
    _configure(
        env="dev",
        demo_reset_enabled=True,
        jwt_secret="a" * 32,
    )
    validate_prod_secrets()


def test_production_still_requires_strong_jwt_and_connected_apps_key() -> None:
    _configure(
        env="prod",
        demo_reset_enabled=False,
        jwt_secret="dev-insecure-change-me",
        connected_apps_key="configured",
    )
    _assert_refuses("JWT_SECRET")

    _configure(
        env="staging",
        demo_reset_enabled=False,
        jwt_secret="b" * 32,
        connected_apps_key="",
    )
    _assert_refuses("CONNECTED_APPS_KEY")

    _configure(
        env="prod",
        demo_reset_enabled=False,
        jwt_secret="c" * 32,
        connected_apps_key="configured",
    )
    validate_prod_secrets()


def main() -> None:
    original = (
        settings.env,
        settings.demo_reset_enabled,
        settings.jwt_secret,
        settings.connected_apps_key,
    )
    try:
        test_reset_disabled_dev_allows_default_secret()
        test_reset_enabled_refuses_default_blank_and_short_secrets()
        test_reset_enabled_dev_allows_strong_secret_without_prod_only_key()
        test_production_still_requires_strong_jwt_and_connected_apps_key()
        print("PASS - startup secret validation protects demo reset and production")
    finally:
        (
            settings.env,
            settings.demo_reset_enabled,
            settings.jwt_secret,
            settings.connected_apps_key,
        ) = original


if __name__ == "__main__":
    main()
