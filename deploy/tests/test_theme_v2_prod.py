from __future__ import annotations

import json
import subprocess
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


if __name__ == "__main__":
    unittest.main()
