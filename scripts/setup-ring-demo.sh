#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
ENV_FILE="$ROOT/.env"

usage() {
  print -- "Usage: ${0:t} [--check]"
  print -- "  no arguments  Install and bootstrap the local Ring Demo"
  print -- "  --check       Run the non-destructive launch preflight only"
}

die() {
  print -u2 -- "Ring Demo setup: $*"
  exit 1
}

check_host_tools() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS is required."
  local command_name
  for command_name in docker node npm python3 curl; do
    command -v "$command_name" >/dev/null || die "Missing prerequisite: $command_name"
  done
}

env_value() {
  local key="$1"
  awk -v key="$key" '
    index($0, key "=") == 1 {
      value = substr($0, length(key) + 2)
      sub(/\r$/, "", value)
      print value
      exit
    }
  ' "$ENV_FILE"
}

check_environment() {
  [[ -f "$ENV_FILE" ]] || die "Missing .env. Run scripts/setup-ring-demo.sh first."

  local deepseek_key jwt_secret reset_enabled
  deepseek_key="$(env_value DEEPSEEK_API_KEY)"
  jwt_secret="$(env_value JWT_SECRET)"
  reset_enabled="${$(env_value DEMO_RESET_ENABLED):l}"

  [[ -n "$deepseek_key" && "$deepseek_key" != *xxxxxxxx* ]] || \
    die "Set a real DEEPSEEK_API_KEY in .env."
  [[ ${#jwt_secret} -ge 32 && "$jwt_secret" != "dev-insecure-change-me" ]] || \
    die "JWT_SECRET in .env must be at least 32 characters and not the dev default."
  [[ "$reset_enabled" == "true" ]] || \
    die "Set DEMO_RESET_ENABLED=true in .env for the exhibition reset control."
}

check_docker() {
  docker info >/dev/null 2>&1 || die "Docker Desktop is not running."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required."
}

check_installed_runtime() {
  [[ -x "$ROOT/ring-desktop/.venv/bin/python" ]] || \
    die "Ring Desktop virtualenv is missing. Run scripts/setup-ring-demo.sh."
  [[ -f "$ROOT/ring-desktop/config.json" ]] || \
    die "ring-desktop/config.json is missing. Run scripts/setup-ring-demo.sh."
  [[ -x "$ROOT/ring-demo/node_modules/.bin/vite" || -f "$ROOT/ring-demo/node_modules/.bin/vite" ]] || \
    die "Ring Demo web dependencies are missing. Run scripts/setup-ring-demo.sh."
}

check_host_tools

case "${1:-}" in
  "") ;;
  --check)
    check_environment
    check_docker
    check_installed_runtime
    print -- "Ring Demo preflight passed."
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
  print -- "Created $ENV_FILE"
  print -- "Add DEEPSEEK_API_KEY, generate JWT_SECRET, and set DEMO_RESET_ENABLED=true; then rerun this script."
  exit 2
fi

check_environment
check_docker

print -- "Installing Ring Desktop dependencies..."
python3 -m venv "$ROOT/ring-desktop/.venv"
"$ROOT/ring-desktop/.venv/bin/pip" install -r "$ROOT/ring-desktop/requirements.txt"

if [[ ! -f "$ROOT/ring-desktop/config.json" ]]; then
  cp "$ROOT/ring-desktop/config.example.json" "$ROOT/ring-desktop/config.json"
  print -- "Created ring-desktop/config.json from the exhibition defaults."
fi

print -- "Installing Ring Demo web dependencies..."
npm --prefix "$ROOT/ring-demo" ci

print -- "Building and bootstrapping the local Backend..."
docker compose -f "$ROOT/docker-compose.yml" build backend
docker compose -f "$ROOT/docker-compose.yml" up -d --wait db
docker compose -f "$ROOT/docker-compose.yml" run --rm backend alembic upgrade head
docker compose -f "$ROOT/docker-compose.yml" run --rm backend python -m db.seed

print -- "Setup complete. Run scripts/run-ring-demo.sh to start the demo."
