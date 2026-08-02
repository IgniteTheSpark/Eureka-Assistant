#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
compose_file="${repo_root}/docker-compose.theme-v2.yml"
base_url="${1:-http://localhost:8100}"

for service in mysql api worker; do
  docker compose -f "${compose_file}" ps --status running --services \
    | grep -qx "${service}"
done

curl -fsS "${base_url}/health"
curl -fsS "${base_url}/ready"
docker compose -f "${compose_file}" exec -T api alembic current
docker compose -f "${compose_file}" exec -T api \
  python -m pytest tests/integration/test_runtime_isolation.py -q
docker compose -f "${compose_file}" --profile test run --rm \
  --workdir /app -e PYTHONPATH=/app test \
  python -m pytest tests/e2e/test_hardware_capture_flow.py -q
