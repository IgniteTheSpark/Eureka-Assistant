#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
WEB_PID=""

cleanup() {
  if [[ -n "$WEB_PID" ]] && kill -0 "$WEB_PID" 2>/dev/null; then
    kill "$WEB_PID" 2>/dev/null || true
    wait "$WEB_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

"$ROOT/scripts/setup-ring-demo.sh" --check

print -- "Starting MySQL and Eureka Backend..."
docker compose -f "$ROOT/docker-compose.yml" up -d --wait db backend

backend_ready=false
for _ in {1..30}; do
  if curl --fail --silent --show-error http://127.0.0.1:8000/health >/dev/null 2>&1; then
    backend_ready=true
    break
  fi
  sleep 1
done
[[ "$backend_ready" == true ]] || {
  print -u2 -- "Ring Demo run: Backend did not become healthy at http://127.0.0.1:8000/health"
  print -u2 -- "Inspect it with: docker compose logs backend"
  exit 1
}

print -- "Starting Demo Web at http://127.0.0.1:5173 ..."
npm --prefix "$ROOT/ring-demo" run dev -- --host 127.0.0.1 --strictPort &
WEB_PID=$!

web_ready=false
for _ in {1..30}; do
  if ! kill -0 "$WEB_PID" 2>/dev/null; then
    wait "$WEB_PID" || true
    print -u2 -- "Ring Demo run: Demo Web stopped before it became ready. Is port 5173 already in use?"
    exit 1
  fi
  if curl --fail --silent --show-error http://127.0.0.1:5173/ >/dev/null 2>&1; then
    web_ready=true
    break
  fi
  sleep 1
done
[[ "$web_ready" == true ]] || {
  print -u2 -- "Ring Demo run: Demo Web did not become ready at http://127.0.0.1:5173"
  exit 1
}

print -- "Demo Web is ready. Starting Ring Desktop in the foreground."
print -- "Keep this terminal open. Press Control-C to stop Ring Desktop and Demo Web."
cd "$ROOT/ring-desktop"
.venv/bin/python -m ring_desktop.app
