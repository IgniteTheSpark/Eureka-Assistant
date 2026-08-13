from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = ROOT / "docker-compose.theme-v2.yml"
ENV_FILE = ROOT / ".env.theme-v2.example"
ARK_IMAGES_ENDPOINT = (
    "https://ark.cn-beijing.volces.com/api/v3/images/generations"
)


class ThemeV2LocalDeploymentTest(unittest.TestCase):
    def test_environment_template_covers_report_illustration_inputs(self) -> None:
        keys = {
            line.split("=", 1)[0]
            for line in ENV_FILE.read_text().splitlines()
            if line and not line.startswith("#") and "=" in line
        }

        self.assertTrue(
            {
                "REPORT_ILLUSTRATION_ENABLED",
                "REPORT_ILLUSTRATION_MODEL",
                "REPORT_ILLUSTRATION_API_URL",
                "REPORT_ILLUSTRATION_API_KEY",
                "REPORT_ILLUSTRATION_TIMEOUT_SECONDS",
            }.issubset(keys)
        )

    def test_existing_image_configuration_can_enable_report_illustrations(self) -> None:
        with tempfile.NamedTemporaryFile() as empty_env:
            result = subprocess.run(
                [
                    "docker",
                    "compose",
                    "--env-file",
                    empty_env.name,
                    "-f",
                    str(COMPOSE_FILE),
                    "config",
                    "--format",
                    "json",
                ],
                cwd=ROOT,
                env={
                    "PATH": os.environ["PATH"],
                    "IMAGE_API_KEY": "ark-existing-key",
                    "IMAGE_MODEL": "doubao-seedream-4-5-251128",
                    "REPORT_ILLUSTRATION_ENABLED": "true",
                },
                check=True,
                capture_output=True,
                text=True,
            )

        config = json.loads(result.stdout)
        for service_name in ("api", "worker"):
            environment = config["services"][service_name]["environment"]
            self.assertEqual("true", environment["REPORT_ILLUSTRATION_ENABLED"])
            self.assertEqual(
                "doubao-seedream-4-5-251128",
                environment["REPORT_ILLUSTRATION_MODEL"],
            )
            self.assertEqual(
                "ark-existing-key",
                environment["REPORT_ILLUSTRATION_API_KEY"],
            )
            self.assertEqual(
                ARK_IMAGES_ENDPOINT,
                environment["REPORT_ILLUSTRATION_API_URL"],
            )


if __name__ == "__main__":
    unittest.main()
