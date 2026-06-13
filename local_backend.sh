#!/usr/bin/env bash
#
# 本地后端快速启动/重启脚本。
#
# 默认流程适合“改了后端代码 / 新增 Alembic 表迁移 / 新增接口”后的本地联调：
#   1. 启动 MySQL db
#   2. 执行 alembic upgrade head
#   3. recreate backend，让 .env 和代码变更生效
#
# 常用：
#   ./local_backend.sh
#   ./local_backend.sh restart
#   ./local_backend.sh start --build
#   ./local_backend.sh start --seed
#   ./local_backend.sh logs
#   ./local_backend.sh status
#   ./local_backend.sh stop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ACTION="start"
RUN_MIGRATIONS="1"
RUN_SEED="0"
BUILD_BACKEND="0"
FOLLOW_LOGS="0"
FORCE_RECREATE="0"

usage() {
  cat <<'EOF'
Usage:
  ./local_backend.sh [start|restart|migrate|logs|status|stop] [options]

Actions:
  start      启动 db，执行迁移，recreate backend（默认）
  restart    等同 start；用于改代码/加表/改 .env 后快速重启
  migrate    只启动 db 并执行 alembic upgrade head
  logs       查看 backend 日志
  status     查看 compose 服务状态和 health
  stop       停止 backend（保留 db 和数据卷）

Options:
  --build       启动前重新 build backend 镜像；改 requirements/Dockerfile 后使用
  --seed        迁移后执行 python -m db.seed；首次初始化或技能种子变更后使用
  --no-migrate  start/restart 时跳过 alembic upgrade head
  --force-recreate
                清空本地 MySQL 数据卷并重启；仅支持 start/restart，会二次确认
  --logs        start/restart 后跟随 backend 日志
  -h, --help    显示帮助

Examples:
  ./local_backend.sh
  ./local_backend.sh restart --logs
  ./local_backend.sh restart --build
  ./local_backend.sh restart --force-recreate
  ./local_backend.sh migrate

Android 真机本地包 API_BASE:
  电脑局域网 IP 可用：ipconfig getifaddr en0
  然后在 mobile 下打包：
    flutter build apk --debug --dart-define=API_BASE=http://<你的电脑IP>:8000
EOF
}

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m警告：\033[0m %s\n' "$*" >&2
}

danger() {
  printf '\033[1;31m%s\033[0m\n' "$*" >&2
}

die() {
  printf '\033[1;31m错误：\033[0m %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

compose() {
  docker compose "$@"
}

wait_for_db() {
  log "等待 MySQL healthcheck 通过"
  local cid status
  cid="$(compose ps -q db)"
  [ -n "$cid" ] || die "找不到 db 容器"

  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
    if [ "$status" = "healthy" ] || [ "$status" = "running" ]; then
      if [ "$status" = "running" ]; then
        warn "db 没有 health 状态或尚未返回 healthy；继续尝试迁移"
      fi
      return 0
    fi
    sleep 2
  done

  compose logs --tail=80 db >&2 || true
  die "MySQL 未在预期时间内就绪"
}

start_db() {
  log "启动 MySQL"
  compose up -d db
  wait_for_db
}

confirm_force_recreate() {
  local answer
  danger "危险操作：将清空本地 MySQL 数据卷，并重建后端数据。"
  read -r -p "确认清空本地 MySQL 数据并重启后端？[y/N] " answer || answer=""
  case "$answer" in
    y|Y) ;;
    *)
      warn "已取消清库重启"
      exit 0
      ;;
  esac
}

mysql_data_volume() {
  local cid volume
  cid="$(compose ps -aq db 2>/dev/null || true)"
  if [ -z "$cid" ]; then
    log "创建 db 容器以定位 MySQL 数据卷" >&2
    compose up -d db >&2
    cid="$(compose ps -aq db 2>/dev/null || true)"
  fi
  [ -n "$cid" ] || die "找不到 db 容器，无法定位 MySQL 数据卷"

  volume="$(docker inspect -f '{{range .Mounts}}{{if and (eq .Destination "/var/lib/mysql") (eq .Type "volume")}}{{.Name}}{{end}}{{end}}' "$cid" 2>/dev/null || true)"
  [ -n "$volume" ] || die "找不到 db 的 /var/lib/mysql 数据卷，拒绝继续清理"
  printf '%s\n' "$volume"
}

reset_mysql_data_volume() {
  local volume
  volume="$(mysql_data_volume)"
  log "停止 compose 服务（不使用 down -v）"
  compose down
  log "删除 MySQL 数据卷：$volume"
  docker volume rm "$volume" >/dev/null
}

build_backend_if_needed() {
  if [ "$BUILD_BACKEND" = "1" ]; then
    log "重新 build backend 镜像"
    compose build backend
  fi
}

run_migrations() {
  if [ "$RUN_MIGRATIONS" != "1" ]; then
    warn "已跳过 Alembic 迁移"
    return 0
  fi
  log "执行 Alembic 迁移：alembic upgrade head"
  compose run --rm backend alembic upgrade head
}

run_seed_if_needed() {
  if [ "$RUN_SEED" = "1" ]; then
    log "执行 seed：python -m db.seed"
    compose run --rm backend python -m db.seed
  fi
}

start_backend() {
  log "启动 / recreate backend"
  # 用 up -d 而不是 restart：README 里说明 .env 变更需要 recreate 才会生效。
  compose up -d --force-recreate backend
}

print_urls() {
  local ip
  ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
  fi

  log "后端已启动"
  echo "  本机：      http://localhost:8000"
  echo "  健康检查：  http://localhost:8000/health"
  if [ -n "$ip" ]; then
    echo "  Android：   http://$ip:8000"
    echo
    echo "  Android debug 包示例："
    echo "    cd mobile"
    echo "    flutter build apk --debug --dart-define=API_BASE=http://$ip:8000"
  else
    warn "未自动获取到局域网 IP；请手动执行 ipconfig getifaddr en0"
  fi
}

do_start() {
  if [ "$FORCE_RECREATE" = "1" ]; then
    confirm_force_recreate
    reset_mysql_data_volume
    RUN_SEED="1"
  fi
  start_db
  build_backend_if_needed
  run_migrations
  run_seed_if_needed
  start_backend
  print_urls
  if [ "$FORCE_RECREATE" = "1" ]; then
    danger "数据已重启，app 需要卸载重装。"
  fi
  if [ "$FOLLOW_LOGS" = "1" ]; then
    compose logs -f backend
  fi
}

do_migrate() {
  start_db
  build_backend_if_needed
  run_migrations
}

do_logs() {
  compose logs -f backend
}

do_status() {
  compose ps
  echo
  curl -fsS http://localhost:8000/health || true
  echo
}

do_stop() {
  log "停止 backend（保留 db 和数据卷）"
  compose stop backend
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    start|restart|migrate|logs|status|stop)
      ACTION="$1"
      shift
      ;;
    --build)
      BUILD_BACKEND="1"
      shift
      ;;
    --seed)
      RUN_SEED="1"
      shift
      ;;
    --no-migrate)
      RUN_MIGRATIONS="0"
      shift
      ;;
    --force-recreate)
      FORCE_RECREATE="1"
      shift
      ;;
    --logs)
      FOLLOW_LOGS="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1。使用 ./local_backend.sh --help 查看帮助"
      ;;
  esac
done

if [ "$FORCE_RECREATE" = "1" ]; then
  case "$ACTION" in
    start|restart) ;;
    *) die "--force-recreate 仅支持 start/restart" ;;
  esac
  if [ "$RUN_MIGRATIONS" != "1" ]; then
    die "--force-recreate 不能与 --no-migrate 一起使用"
  fi
fi

need_cmd docker

case "$ACTION" in
  start|restart) do_start ;;
  migrate) do_migrate ;;
  logs) do_logs ;;
  status) do_status ;;
  stop) do_stop ;;
  *) die "未知 action：$ACTION" ;;
esac
