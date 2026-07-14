"""Dependency declarations required by the backend runtime.

Run from the repository root:
    python3 backend/scripts/test_runtime_dependencies.py
"""

from __future__ import annotations

import re
from pathlib import Path


REQUIREMENTS = Path(__file__).resolve().parents[1] / "requirements.txt"


def _declared_packages() -> set[str]:
    packages: set[str] = set()
    for raw_line in REQUIREMENTS.read_text().splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line or line.startswith(("-", "http://", "https://", "git+")):
            continue
        match = re.match(r"[A-Za-z0-9_.-]+", line)
        if match:
            packages.add(match.group(0).lower().replace("_", "-"))
    return packages


def test_deepseek_flash_runtime_dependencies_are_declared() -> None:
    assert "orjson" in _declared_packages(), (
        "backend/requirements.txt must declare orjson for LiteLLM's "
        "DeepSeek runtime path"
    )


def main() -> None:
    test_deepseek_flash_runtime_dependencies_are_declared()
    print("PASS - DeepSeek Flash runtime dependencies are declared")


if __name__ == "__main__":
    main()
