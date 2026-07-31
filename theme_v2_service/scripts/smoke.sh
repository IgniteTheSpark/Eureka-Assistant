#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
compose_file="${repo_root}/docker-compose.theme-v2.yml"

curl -fsS http://localhost:8100/health
curl -fsS http://localhost:8100/ready
docker compose -f "${compose_file}" exec -T api alembic current
docker compose -f "${compose_file}" exec -T api \
  python -m pytest tests/integration/test_runtime_isolation.py -q
