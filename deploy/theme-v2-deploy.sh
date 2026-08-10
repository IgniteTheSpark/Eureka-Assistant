#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.theme-v2.prod.yml"
ENV_FILE=${THEME_V2_ENV_FILE:-"$SCRIPT_DIR/.env.theme-v2.prod"}
STATE_DIR="$SCRIPT_DIR/.theme-v2-state"

usage() {
  echo "Usage: $0 deploy [image-tag] | rollback [image-tag] | status | logs | config" >&2
  exit 2
}

require_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "Missing $ENV_FILE. Copy .env.theme-v2.prod.example and fill every production value." >&2
    exit 1
  fi
}

validate_production_values() {
  if grep -Eq '^[A-Z][A-Z0-9_]*=.*(replace-with|example\.com)' "$ENV_FILE"; then
    echo "Production env still contains example or replace-with placeholder values." >&2
    echo "Replace every placeholder in $ENV_FILE before running deployment commands." >&2
    exit 1
  fi
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

read_env_value() {
  awk -F= -v key="$1" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE" | tr -d '\r'
}

load_saved_tag() {
  if [ -f "$STATE_DIR/current-image-tag" ]; then
    APP_IMAGE_TAG=$(sed -n '1p' "$STATE_DIR/current-image-tag")
    export APP_IMAGE_TAG
  fi
}

wait_until_ready() {
  domain=$(read_env_value DOMAIN)
  if [ -z "$domain" ]; then
    echo "DOMAIN is empty in $ENV_FILE" >&2
    return 1
  fi
  curl --fail --silent --show-error \
    --retry 24 --retry-delay 5 --retry-connrefused --retry-all-errors \
    "https://$domain/ready" >/dev/null
}

record_successful_tag() {
  new_tag=$1
  mkdir -p "$STATE_DIR"
  if [ -f "$STATE_DIR/current-image-tag" ]; then
    cp "$STATE_DIR/current-image-tag" "$STATE_DIR/previous-image-tag"
  fi
  printf '%s\n' "$new_tag" > "$STATE_DIR/current-image-tag"
}

deploy() {
  if [ "${ALLOW_DIRTY_DEPLOY:-0}" != "1" ] && [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    echo "Refusing to deploy a dirty worktree. Commit the release or set ALLOW_DIRTY_DEPLOY=1 explicitly." >&2
    exit 1
  fi

  tag=${1:-$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)}
  APP_IMAGE_TAG=$tag
  export APP_IMAGE_TAG

  compose config --quiet
  compose build api
  compose up -d --wait db migrate
  compose up -d --no-build api worker caddy
  wait_until_ready
  record_successful_tag "$tag"
  compose ps
  echo "Theme V2 deployment is ready at https://$(read_env_value DOMAIN) (image tag: $tag)."
}

rollback() {
  tag=${1:-}
  if [ -z "$tag" ] && [ -f "$STATE_DIR/previous-image-tag" ]; then
    tag=$(sed -n '1p' "$STATE_DIR/previous-image-tag")
  fi
  if [ -z "$tag" ]; then
    echo "No rollback tag supplied and no previous successful tag is recorded." >&2
    exit 1
  fi
  if ! docker image inspect "eureka-theme-v2-service:$tag" >/dev/null 2>&1; then
    echo "Local image eureka-theme-v2-service:$tag does not exist." >&2
    exit 1
  fi

  APP_IMAGE_TAG=$tag
  export APP_IMAGE_TAG
  compose up -d --no-build api worker caddy
  wait_until_ready
  record_successful_tag "$tag"
  compose ps
  echo "Application containers rolled back to image tag $tag. Database migrations were not reversed."
}

require_env_file
validate_production_values
command=${1:-}
case "$command" in
  deploy)
    deploy "${2:-}"
    ;;
  rollback)
    rollback "${2:-}"
    ;;
  status)
    load_saved_tag
    compose ps
    ;;
  logs)
    load_saved_tag
    compose logs --tail=200 -f api worker caddy
    ;;
  config)
    load_saved_tag
    compose config
    ;;
  *)
    usage
    ;;
esac
