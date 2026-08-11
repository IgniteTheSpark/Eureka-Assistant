#!/bin/sh
set -eu

umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.theme-v2.prod.yml"
ENV_FILE=${THEME_V2_ENV_FILE:-"$SCRIPT_DIR/.env.theme-v2.prod"}
STATE_DIR="$SCRIPT_DIR/.theme-v2-state"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

if [ -f "$STATE_DIR/current-image-tag" ]; then
  APP_IMAGE_TAG=$(sed -n '1p' "$STATE_DIR/current-image-tag")
  export APP_IMAGE_TAG
fi

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

configured_backup_dir=$(awk -F= '$1 == "BACKUP_DIR" {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE" | tr -d '\r')
BACKUP_DIR=${BACKUP_DIR:-${configured_backup_dir:-"$SCRIPT_DIR/backups"}}
case "$BACKUP_DIR" in
  /*) ;;
  *) BACKUP_DIR="$SCRIPT_DIR/../$BACKUP_DIR" ;;
esac

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$BACKUP_DIR/$timestamp"
mkdir -p "$target"

mysql_dump="$target/mysql.sql"
if ! compose exec -T db sh -c \
  'exec mysqldump --single-transaction --quick --lock-tables=false --no-tablespaces -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  > "$mysql_dump"; then
  rm -f "$mysql_dump"
  echo "MySQL backup failed; no successful backup was recorded." >&2
  exit 1
fi
gzip -9 "$mysql_dump"

compose run --rm --no-deps -T api python -c \
  'import sys, tarfile; archive = tarfile.open(fileobj=sys.stdout.buffer, mode="w|gz"); archive.add("/data/media", arcname="media"); archive.close()' \
  > "$target/media.tar.gz"

sha256sum "$target/mysql.sql.gz" "$target/media.tar.gz" > "$target/SHA256SUMS"
chmod 600 "$target/mysql.sql.gz" "$target/media.tar.gz" "$target/SHA256SUMS"

echo "Backup created: $target"
echo "Copy this directory to encrypted off-server storage, then test a restore regularly."
