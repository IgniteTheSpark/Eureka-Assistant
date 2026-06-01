#!/usr/bin/env bash
# doctor — read-only preflight for the flash-card bridge.
# ───────────────────────────────────────────────────────────────────────────
# Answers "why won't my card connect?" by checking every link in the chain:
#   card → FlashType → eureka-bridge.py (whisper) → /api/flash → Eureka backend
# Prints PASS/WARN/FAIL with a fix hint for each. Exits non-zero if any HARD
# prerequisite fails (whisper bin, model, backend). A missing FlashType log is
# only a WARN — it appears the first time you hold the card button.
#
# Usage:  ./doctor.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_grn() { printf "\033[32m%s\033[0m" "$*"; }
_red() { printf "\033[31m%s\033[0m" "$*"; }
_yel() { printf "\033[33m%s\033[0m" "$*"; }
_dim() { printf "\033[2m%s\033[0m" "$*"; }

fails=0
pass() { printf "  %s %s\n" "$(_grn "✓")" "$1"; }
warn() { printf "  %s %s\n      %s\n" "$(_yel "!")" "$1" "$(_dim "$2")"; }
fail() { printf "  %s %s\n      %s\n" "$(_red "✗")" "$1" "$(_dim "$2")"; fails=$((fails+1)); }

# ── Load config (env file is optional; defaults match the .example) ──────────
ENV_FILE="$HERE/flash-card.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    set -a; . "$ENV_FILE"; set +a
fi
EUREKA_FLASH_URL="${EUREKA_FLASH_URL:-http://localhost:8000/api/flash}"
EUREKA_LISTENING_URL="${EUREKA_LISTENING_URL:-http://localhost:8000/api/flash/listening}"
EUREKA_WHISPER_BIN="${EUREKA_WHISPER_BIN:-/opt/homebrew/bin/whisper-cli}"
EUREKA_WHISPER_MODEL="${EUREKA_WHISPER_MODEL:-$HOME/.flash-type/models/ggml-base.bin}"
FLASH_TYPE_LOG="${FLASH_TYPE_LOG:-$HOME/.flash-type/flash-type.log}"

echo "flash-card doctor"
echo "─────────────────"

# 1. env file
if [ -f "$ENV_FILE" ]; then
    pass "config: flash-card.env"
else
    warn "config: flash-card.env not found (using built-in defaults)" \
         "run ./setup.sh, or: cp flash-card.env.example flash-card.env"
fi

# 2. whisper binary
if [ -x "$EUREKA_WHISPER_BIN" ]; then
    pass "whisper: $EUREKA_WHISPER_BIN"
elif command -v whisper-cli >/dev/null 2>&1; then
    warn "whisper: found on PATH but not at $EUREKA_WHISPER_BIN" \
         "set EUREKA_WHISPER_BIN=$(command -v whisper-cli) in flash-card.env"
else
    fail "whisper: not found at $EUREKA_WHISPER_BIN" \
         "brew install whisper-cpp   (then re-run ./setup.sh)"
fi

# 3. model file
if [ -f "$EUREKA_WHISPER_MODEL" ]; then
    pass "model: $EUREKA_WHISPER_MODEL"
else
    fail "model: missing $EUREKA_WHISPER_MODEL" \
         "run ./setup.sh to download it"
fi

# 4. backend reachable (derive origin from the flash URL → /health)
ORIGIN="${EUREKA_FLASH_URL%%/api/*}"
if curl -fsS --max-time 4 "$ORIGIN/health" >/dev/null 2>&1; then
    pass "backend: $ORIGIN reachable"
else
    fail "backend: $ORIGIN not reachable" \
         "start it: docker compose up -d backend   (from the repo root)"
fi

# 5. FlashType log (WARN only — created on first capture)
if [ -f "$FLASH_TYPE_LOG" ]; then
    pass "FlashType log: $FLASH_TYPE_LOG"
else
    warn "FlashType log: not found at $FLASH_TYPE_LOG" \
         "install + pair the card in FlashType and hold the button once; or set FLASH_TYPE_LOG"
fi

echo "─────────────────"
if [ "$fails" -eq 0 ]; then
    printf "%s\n" "$(_grn "all hard checks passed")"
    exit 0
else
    printf "%s\n" "$(_red "$fails hard check(s) failed — see hints above")"
    exit 1
fi
