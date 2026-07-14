#!/bin/zsh
set -euo pipefail

REPO_ROOT="${0:A:h:h}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ring-demo-ops.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -F -- "$expected" "$file" >/dev/null || fail "Expected $file to contain: $expected"
}

mkdir -p "$TMP_ROOT/repo/scripts" "$TMP_ROOT/repo/ring-desktop" \
  "$TMP_ROOT/repo/ring-demo" "$TMP_ROOT/fake-bin"
cp "$REPO_ROOT/scripts/setup-ring-demo.sh" "$TMP_ROOT/repo/scripts/"
cp "$REPO_ROOT/scripts/run-ring-demo.sh" "$TMP_ROOT/repo/scripts/"
cp "$REPO_ROOT/.env.example" "$TMP_ROOT/repo/.env.example"
cp "$REPO_ROOT/docker-compose.yml" "$TMP_ROOT/repo/docker-compose.yml"
cp "$REPO_ROOT/ring-desktop/config.example.json" "$TMP_ROOT/repo/ring-desktop/config.example.json"
cp "$REPO_ROOT/ring-desktop/requirements.txt" "$TMP_ROOT/repo/ring-desktop/requirements.txt"
cp "$REPO_ROOT/ring-demo/package.json" "$TMP_ROOT/repo/ring-demo/package.json"
cp "$REPO_ROOT/ring-demo/package-lock.json" "$TMP_ROOT/repo/ring-demo/package-lock.json"

print -r -- '#!/bin/zsh
print Darwin' > "$TMP_ROOT/fake-bin/uname"
print -r -- '#!/bin/zsh
print -- "docker $*" >> "$RING_DEMO_TEST_LOG"' > "$TMP_ROOT/fake-bin/docker"
print -r -- '#!/bin/zsh
if [[ "${1:-}" == "--version" ]]; then print v20.0.0; fi' > "$TMP_ROOT/fake-bin/node"
print -r -- '#!/bin/zsh
print -- "npm $*" >> "$RING_DEMO_TEST_LOG"
if [[ "${RING_DEMO_TEST_NPM_BLOCK:-0}" == "1" ]]; then
  print -- $$ > "$RING_DEMO_TEST_WEB_PID"
  trap "exit 0" TERM INT
  while true; do sleep 1; done
fi' > "$TMP_ROOT/fake-bin/npm"
print -r -- '#!/bin/zsh
print -- "python3 $*" >> "$RING_DEMO_TEST_LOG"
if [[ "${1:-}" == "-m" && "${2:-}" == "venv" ]]; then
  mkdir -p "$3/bin"
  print -r -- "#!/bin/zsh" > "$3/bin/python"
  print -r -- '\''print -- "desktop-python $*" >> "$RING_DEMO_TEST_LOG"'\'' >> "$3/bin/python"
  print -r -- "#!/bin/zsh" > "$3/bin/pip"
  print -r -- '\''print -- "pip $*" >> "$RING_DEMO_TEST_LOG"'\'' >> "$3/bin/pip"
  chmod +x "$3/bin/python" "$3/bin/pip"
fi' > "$TMP_ROOT/fake-bin/python3"
print -r -- '#!/bin/zsh
exit 0' > "$TMP_ROOT/fake-bin/curl"
chmod +x "$TMP_ROOT/fake-bin/"*

export PATH="$TMP_ROOT/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin"
export RING_DEMO_TEST_LOG="$TMP_ROOT/commands.log"
touch "$RING_DEMO_TEST_LOG"
CANON_REPO="${TMP_ROOT:A}/repo"

zsh -n "$TMP_ROOT/repo/scripts/setup-ring-demo.sh" "$TMP_ROOT/repo/scripts/run-ring-demo.sh"

set +e
"$TMP_ROOT/repo/scripts/setup-ring-demo.sh" >"$TMP_ROOT/first.out" 2>"$TMP_ROOT/first.err"
first_status=$?
set -e
[[ "$first_status" == 2 ]] || fail "First setup must exit 2 after creating .env; got $first_status"
[[ -f "$TMP_ROOT/repo/.env" ]] || fail "First setup did not create .env"
[[ ! -s "$RING_DEMO_TEST_LOG" ]] || fail "First setup ran installers before configuration"

print -r -- 'DEEPSEEK_API_KEY=sk-test-only-not-a-real-key
JWT_SECRET=0123456789abcdef0123456789abcdef
CONNECTED_APPS_KEY=
DEMO_RESET_ENABLED=true
ENV=dev' > "$TMP_ROOT/repo/.env"

set +e
"$TMP_ROOT/repo/scripts/setup-ring-demo.sh" >"$TMP_ROOT/setup.out" 2>"$TMP_ROOT/setup.err"
setup_status=$?
set -e
if [[ "$setup_status" != 0 ]]; then
  print -u2 -- "Setup output:"
  sed -n '1,160p' "$TMP_ROOT/setup.out" >&2
  sed -n '1,160p' "$TMP_ROOT/setup.err" >&2
  fail "Configured setup exited $setup_status"
fi
[[ -x "$TMP_ROOT/repo/ring-desktop/.venv/bin/python" ]] || fail "Setup did not create Ring Desktop venv"
[[ -f "$TMP_ROOT/repo/ring-desktop/config.json" ]] || fail "Setup did not create Ring Desktop config"
mkdir -p "$TMP_ROOT/repo/ring-demo/node_modules/.bin"
touch "$TMP_ROOT/repo/ring-demo/node_modules/.bin/vite"
"$TMP_ROOT/repo/scripts/setup-ring-demo.sh" --check >"$TMP_ROOT/check.out" 2>"$TMP_ROOT/check.err"

assert_contains "$RING_DEMO_TEST_LOG" "pip install -r $CANON_REPO/ring-desktop/requirements.txt"
assert_contains "$RING_DEMO_TEST_LOG" "npm --prefix $CANON_REPO/ring-demo ci"
assert_contains "$RING_DEMO_TEST_LOG" "docker compose -f $CANON_REPO/docker-compose.yml up -d --wait db"
assert_contains "$RING_DEMO_TEST_LOG" "docker compose -f $CANON_REPO/docker-compose.yml run --rm backend alembic upgrade head"
assert_contains "$RING_DEMO_TEST_LOG" "docker compose -f $CANON_REPO/docker-compose.yml run --rm backend python -m db.seed"

export RING_DEMO_TEST_NPM_BLOCK=1
export RING_DEMO_TEST_WEB_PID="$TMP_ROOT/web.pid"
"$TMP_ROOT/repo/scripts/run-ring-demo.sh" >"$TMP_ROOT/run.out" 2>"$TMP_ROOT/run.err"
assert_contains "$RING_DEMO_TEST_LOG" "docker compose -f $CANON_REPO/docker-compose.yml up -d --wait db backend"
assert_contains "$RING_DEMO_TEST_LOG" "npm --prefix $CANON_REPO/ring-demo run dev -- --host 127.0.0.1 --strictPort"
assert_contains "$RING_DEMO_TEST_LOG" "desktop-python -m ring_desktop.app"
web_pid="$(<"$RING_DEMO_TEST_WEB_PID")"
sleep 0.1
if kill -0 "$web_pid" 2>/dev/null; then
  fail "Run script left the Vite process running"
fi

print -- "PASS: Ring Demo setup/run operations contract"
