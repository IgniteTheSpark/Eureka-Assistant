from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPLOY_DIR = ROOT / "deploy"
COMPOSE_FILE = DEPLOY_DIR / "docker-compose.theme-v2.prod.yml"
ENV_FILE = DEPLOY_DIR / ".env.theme-v2.prod.example"
CADDYFILE = DEPLOY_DIR / "Caddyfile.theme-v2"
DOCKERFILE = ROOT / "theme_v2_service" / "Dockerfile.prod"
DEPLOY_SCRIPT = DEPLOY_DIR / "theme-v2-deploy.sh"
BACKUP_SCRIPT = DEPLOY_DIR / "theme-v2-backup.sh"
DOCKERIGNORE = ROOT / "theme_v2_service" / ".dockerignore"
ANDROID_PACKAGE_SCRIPT = ROOT / "mobile" / "package_android.sh"
IOS_PACKAGE_SCRIPT = ROOT / "mobile" / "package_ios.sh"
MOBILE_CONFIG = ROOT / "mobile" / "lib" / "config.dart"
IOS_INFO_PLIST = ROOT / "mobile" / "ios" / "Runner" / "Info.plist"
LEGACY_DEPLOY_README = DEPLOY_DIR / "README.md"
LEGACY_CADDYFILE = DEPLOY_DIR / "Caddyfile.cn-8443"
PRODUCTION_API_BASE = "https://api.ureka.chat"
RETIRED_API_HOST = ".".join(("39", "96", "55", "118"))


def _write_temp_env(values: dict[str, str]) -> Path:
    handle = tempfile.NamedTemporaryFile(
        "w", suffix=".env", delete=False, encoding="utf-8"
    )
    with handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")
    return Path(handle.name)


PLACEHOLDER_ENV: dict[str, str] = {
    "DOMAIN": "api.example.com",
    "ACME_EMAIL": "ops@example.com",
    "APP_IMAGE_TAG": "replace-with-git-sha",
    "DEBIAN_MIRROR": "mirrors.aliyun.com",
    "PIP_INDEX_URL": "https://mirrors.aliyun.com/pypi/simple/",
    "THEME_V2_DATABASE_URL": (
        "mysql://theme_v2:replace-with-password@db:3306/eureka_theme_v2"
    ),
    "THEME_V2_DB_PASSWORD": "replace-with-db-password",
    "THEME_V2_DB_ROOT_PASSWORD": "replace-with-root-password",
    "THEME_V2_JWT_SECRET": "replace-with-jwt-secret",
    "EMAIL_PROVIDER": "aliyun_directmail",
    "EMAIL_FROM_ADDRESS": "verify@mail.ureka.chat",
    "EMAIL_FROM_NAME": "UReka",
    "DIRECTMAIL_ACCOUNT_NAME": "verify@mail.ureka.chat",
    "DIRECTMAIL_ACCESS_KEY_ID": "replace-with-directmail-access-key-id",
    "DIRECTMAIL_ACCESS_KEY_SECRET": "replace-with-directmail-access-key-secret",
    "TERMS_URL": "https://example.com/terms",
    "PRIVACY_URL": "https://example.com/privacy",
    "TERMS_VERSION_CURRENT": "prelaunch-v0",
    "DASHSCOPE_API_KEY": "replace-with-dashscope-api-key",
    "DASHSCOPE_ASR_WS_URL": (
        "wss://replace-with-workspace-id.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    ),
    "TENCENT_ASR_SERVICE_BASE_URL": "https://pre.card.biz",
    "REPORT_PUBLIC_BASE_URL": "https://api.example.com",
}


class ThemeV2ProductionDeploymentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        required_files = (
            COMPOSE_FILE,
            ENV_FILE,
            CADDYFILE,
            DOCKERFILE,
            DEPLOY_SCRIPT,
            BACKUP_SCRIPT,
        )
        missing = [str(path.relative_to(ROOT)) for path in required_files if not path.is_file()]
        if missing:
            raise AssertionError(f"missing Theme V2 production files: {', '.join(missing)}")

        result = subprocess.run(
            [
                "docker",
                "compose",
                "--env-file",
                str(ENV_FILE),
                "-f",
                str(COMPOSE_FILE),
                "config",
                "--format",
                "json",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.config = json.loads(result.stdout)

    def test_production_stack_contains_runtime_and_edge_services(self) -> None:
        self.assertEqual(
            {"db", "migrate", "api", "worker", "caddy"},
            set(self.config["services"]),
        )

    def test_only_caddy_publishes_network_ports(self) -> None:
        services = self.config["services"]
        for name in ("db", "migrate", "api", "worker"):
            self.assertFalse(services[name].get("ports"), f"{name} must not publish a host port")

        published_targets = {port["target"] for port in services["caddy"]["ports"]}
        self.assertEqual({80, 443}, published_targets)

    def test_long_running_services_restart_and_do_not_mount_source_code(self) -> None:
        services = self.config["services"]
        for name in ("db", "api", "worker", "caddy"):
            self.assertEqual("unless-stopped", services[name].get("restart"))

        for name in ("api", "worker"):
            mounts = services[name].get("volumes", [])
            self.assertTrue(mounts, f"{name} must mount persistent media storage")
            self.assertTrue(all(mount["type"] == "volume" for mount in mounts))

    def test_api_uses_production_secrets_and_readiness(self) -> None:
        api = self.config["services"]["api"]
        environment = api["environment"]
        self.assertEqual("production", environment["ENV"])
        self.assertNotEqual("dev-insecure-change-me", environment["JWT_SECRET"])
        self.assertIn("mysql", environment["DATABASE_URL"])
        self.assertIn("/ready", " ".join(api["healthcheck"]["test"]))
        self.assertEqual(
            "qwen-audio-3.0-asr-flash-streaming",
            environment["ALI_ASR_MODEL"],
        )
        self.assertTrue(environment["DASHSCOPE_API_KEY"])
        self.assertTrue(environment["DASHSCOPE_ASR_WS_URL"])

    def test_runtime_image_excludes_test_dependencies_and_runs_non_root(self) -> None:
        dockerfile = DOCKERFILE.read_text()
        self.assertIn("requirements.txt", dockerfile)
        self.assertNotIn("requirements-dev.txt", dockerfile)
        self.assertIn("ARG DEBIAN_MIRROR", dockerfile)
        self.assertRegex(dockerfile, r"(?m)^USER\s+(?!root\b)\S+")

    def test_dockerignore_keeps_the_existing_development_build_valid(self) -> None:
        ignored_paths = {
            line.strip()
            for line in DOCKERIGNORE.read_text().splitlines()
            if line.strip() and not line.startswith("#")
        }
        self.assertNotIn("requirements-dev.txt", ignored_paths)

    def test_dockerignore_excludes_macos_appledouble_metadata(self) -> None:
        ignored_paths = {
            line.strip()
            for line in DOCKERIGNORE.read_text().splitlines()
            if line.strip() and not line.startswith("#")
        }
        self.assertIn("**/._*", ignored_paths)

    def test_caddy_preserves_streaming_and_hides_metrics(self) -> None:
        caddyfile = CADDYFILE.read_text()
        self.assertIn("flush_interval -1", caddyfile)
        self.assertIn("/metrics", caddyfile)
        self.assertRegex(caddyfile, r"(?s)@metrics.*respond.*404")

    def test_environment_template_covers_required_production_inputs(self) -> None:
        keys = {
            line.split("=", 1)[0]
            for line in ENV_FILE.read_text().splitlines()
            if line and not line.startswith("#") and "=" in line
        }
        self.assertTrue(
            {
                "DOMAIN",
                "ACME_EMAIL",
                "APP_IMAGE_TAG",
                "DEBIAN_MIRROR",
                "PIP_INDEX_URL",
                "THEME_V2_DATABASE_URL",
                "THEME_V2_DB_PASSWORD",
                "THEME_V2_DB_ROOT_PASSWORD",
                "THEME_V2_JWT_SECRET",
                "EMAIL_PROVIDER",
                "EMAIL_FROM_ADDRESS",
                "EMAIL_FROM_NAME",
                "DIRECTMAIL_ACCOUNT_NAME",
                "DIRECTMAIL_ACCESS_KEY_ID",
                "DIRECTMAIL_ACCESS_KEY_SECRET",
                "TERMS_URL",
                "PRIVACY_URL",
                "TERMS_VERSION_CURRENT",
                "DASHSCOPE_API_KEY",
                "DASHSCOPE_ASR_WS_URL",
                "ALI_ASR_MODEL",
                "CAPTURE_AGENT_ENABLED",
                "CHAT_AGENT_ENABLED",
                "REPORT_PIPELINE_ENABLED",
                "REPORT_ILLUSTRATION_ENABLED",
                "REPORT_ILLUSTRATION_MODEL",
                "REPORT_ILLUSTRATION_API_URL",
                "REPORT_ILLUSTRATION_API_KEY",
                "REPORT_PUBLIC_BASE_URL",
            }.issubset(keys)
        )

    def test_environment_template_uses_placeholder_only_values(self) -> None:
        text = ENV_FILE.read_text()
        for secret_like_key in (
            "DIRECTMAIL_ACCESS_KEY_ID",
            "DIRECTMAIL_ACCESS_KEY_SECRET",
            "THEME_V2_DB_PASSWORD",
            "THEME_V2_DB_ROOT_PASSWORD",
            "THEME_V2_JWT_SECRET",
        ):
            value = next(
                (
                    line.split("=", 1)[1].strip()
                    for line in text.splitlines()
                    if line.startswith(f"{secret_like_key}=")
                ),
                "",
            )
            self.assertIn("replace-with", value, secret_like_key)
        self.assertIn("TERMS_VERSION_CURRENT=prelaunch-v0", text)
        self.assertIn("TERMS_URL=https://example.com/terms", text)
        self.assertIn("PRIVACY_URL=https://example.com/privacy", text)

    def test_production_compose_parses_temporary_placeholder_env(self) -> None:
        temp_env = _write_temp_env(PLACEHOLDER_ENV)
        try:
            result = subprocess.run(
                [
                    "docker",
                    "compose",
                    "--env-file",
                    str(temp_env),
                    "-f",
                    str(COMPOSE_FILE),
                    "config",
                    "--format",
                    "json",
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        finally:
            temp_env.unlink()
        rendered = json.loads(result.stdout)
        api_environment = rendered["services"]["api"]["environment"]
        self.assertEqual("aliyun_directmail", api_environment["EMAIL_PROVIDER"])
        self.assertEqual("verify@mail.ureka.chat", api_environment["EMAIL_FROM_ADDRESS"])
        self.assertEqual("https://example.com/terms", api_environment["TERMS_URL"])
        self.assertEqual("prelaunch-v0", api_environment["TERMS_VERSION_CURRENT"])

    def test_production_compose_requires_directmail_terms_and_version(self) -> None:
        required_vars = (
            "EMAIL_FROM_ADDRESS",
            "DIRECTMAIL_ACCOUNT_NAME",
            "DIRECTMAIL_ACCESS_KEY_ID",
            "DIRECTMAIL_ACCESS_KEY_SECRET",
            "TERMS_URL",
            "PRIVACY_URL",
            "TERMS_VERSION_CURRENT",
        )
        for missing in required_vars:
            values = {key: value for key, value in PLACEHOLDER_ENV.items() if key != missing}
            temp_env = _write_temp_env(values)
            try:
                result = subprocess.run(
                    [
                        "docker",
                        "compose",
                        "--env-file",
                        str(temp_env),
                        "-f",
                        str(COMPOSE_FILE),
                        "config",
                    ],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                )
            finally:
                temp_env.unlink()
            self.assertNotEqual(0, result.returncode, missing)
            self.assertIn(missing, result.stderr, missing)

    def test_operational_scripts_fail_fast_and_support_rollback(self) -> None:
        deploy_script = DEPLOY_SCRIPT.read_text()
        backup_script = BACKUP_SCRIPT.read_text()
        self.assertIn("set -eu", deploy_script)
        self.assertIn("rollback", deploy_script)
        self.assertIn("/ready", deploy_script)
        self.assertIn("--retry-all-errors", deploy_script)
        self.assertIn("set -eu", backup_script)
        self.assertIn("mysqldump", backup_script)
        self.assertIn("--no-tablespaces", backup_script)
        self.assertIn("if ! compose exec -T db", backup_script)
        self.assertIn("/data/media", backup_script)

    def test_deploy_script_rejects_example_placeholder_secrets(self) -> None:
        result = subprocess.run(
            [str(DEPLOY_SCRIPT), "config"],
            cwd=ROOT,
            env={"PATH": "/usr/local/bin:/usr/bin:/bin", "THEME_V2_ENV_FILE": str(ENV_FILE)},
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("placeholder", result.stderr.lower())

    def test_mobile_builds_default_to_the_current_theme_v2_api(self) -> None:
        for path in (ANDROID_PACKAGE_SCRIPT, IOS_PACKAGE_SCRIPT, MOBILE_CONFIG):
            content = path.read_text()
            self.assertIn(PRODUCTION_API_BASE, content, str(path.relative_to(ROOT)))
            self.assertNotIn(
                "defaultValue: 'http://localhost:8000'",
                content,
                str(path.relative_to(ROOT)),
            )
        for path in (ANDROID_PACKAGE_SCRIPT, IOS_PACKAGE_SCRIPT):
            self.assertIn(
                "--dart-define=THEME_V2=true",
                path.read_text(),
                str(path.relative_to(ROOT)),
            )

    def test_retired_api_host_is_absent_from_build_and_deploy_sources(self) -> None:
        for path in (
            ANDROID_PACKAGE_SCRIPT,
            IOS_PACKAGE_SCRIPT,
            MOBILE_CONFIG,
            IOS_INFO_PLIST,
            LEGACY_DEPLOY_README,
            LEGACY_CADDYFILE,
        ):
            self.assertNotIn(
                RETIRED_API_HOST,
                path.read_text(),
                str(path.relative_to(ROOT)),
            )


if __name__ == "__main__":
    unittest.main()
