#!/usr/bin/env bash
# setup — one-time, idempotent setup for the flash-card bridge.
# ───────────────────────────────────────────────────────────────────────────
# Gets the host side of the card→Eureka link ready:
#   1. create flash-card.env from the example (if missing)
#   2. ensure whisper-cli is installed (offers `brew install whisper-cpp`)
#   3. ensure the whisper model is downloaded
#   4. print the exact FlashType config to paste (GUI app — can't auto-set)
#   5. run ./doctor.sh
#
# Nothing is installed or downloaded without asking first. Safe to re-run.
#
# Usage:  ./setup.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_bold() { printf "\033[1m%s\033[0m\n" "$*"; }
_grn()  { printf "\033[32m%s\033[0m\n" "$*"; }
_yel()  { printf "\033[33m%s\033[0m\n" "$*"; }
_dim()  { printf "\033[2m%s\033[0m\n" "$*"; }

ask() {  # ask "question" → returns 0 for yes
    local ans
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"

_bold "flash-card setup"
echo "════════════════"

# ── 1. env file ──────────────────────────────────────────────────────────────
ENV_FILE="$HERE/flash-card.env"
if [ -f "$ENV_FILE" ]; then
    _grn "✓ flash-card.env already exists"
else
    cp "$HERE/flash-card.env.example" "$ENV_FILE"
    _grn "✓ created flash-card.env (from example)"
fi
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
WHISPER_BIN="${EUREKA_WHISPER_BIN:-/opt/homebrew/bin/whisper-cli}"
WHISPER_MODEL="${EUREKA_WHISPER_MODEL:-$HOME/.flash-type/models/ggml-base.bin}"

# ── 2. whisper-cli ─────────────────────────────────────────────────────────────
echo
if [ -x "$WHISPER_BIN" ] || command -v whisper-cli >/dev/null 2>&1; then
    _grn "✓ whisper-cli present"
else
    _yel "whisper-cli not found (needed for offline transcription)"
    if command -v brew >/dev/null 2>&1; then
        if ask "  install it now with 'brew install whisper-cpp'?"; then
            brew install whisper-cpp || _yel "  brew install failed — install whisper-cpp manually"
        else
            _dim "  skipped — install later with: brew install whisper-cpp"
        fi
    else
        _yel "  Homebrew not found. Install brew (https://brew.sh) then: brew install whisper-cpp"
    fi
fi

# ── 3. model ───────────────────────────────────────────────────────────────────
echo
if [ -f "$WHISPER_MODEL" ]; then
    _grn "✓ whisper model present ($WHISPER_MODEL)"
else
    _yel "whisper model missing: $WHISPER_MODEL"
    if ask "  download ggml-base.bin (~142MB) now?"; then
        mkdir -p "$(dirname "$WHISPER_MODEL")"
        if curl -fL --progress-bar -o "$WHISPER_MODEL" "$MODEL_URL"; then
            _grn "✓ model downloaded"
        else
            rm -f "$WHISPER_MODEL"
            _yel "  download failed — fetch manually from: $MODEL_URL"
        fi
    else
        _dim "  skipped — download later from: $MODEL_URL"
    fi
fi

# ── 4. FlashType config (print to paste — GUI app, can't auto-set) ──────────────
echo
_bold "FlashType configuration"
echo "Point FlashType's external ASR at the bridge. In the shell FlashType"
echo "launches from (e.g. its scripts/env.local.sh), export:"
echo
echo "    export FLASH_TYPE_ASR=\"external\""
echo "    export FLASH_TYPE_ASR_COMMAND='python3 $HERE/eureka-bridge.py {wav} {language}'"
echo
_dim "FlashType captures over BLE and calls that command with the decoded WAV;"
_dim "the bridge transcribes locally and POSTs the text to Eureka."

# ── 5. doctor ──────────────────────────────────────────────────────────────────
echo
_bold "running doctor"
echo "──────────────"
bash "$HERE/doctor.sh" || true

echo
_grn "setup done — next: ./start.sh (runs the listening watcher)"
