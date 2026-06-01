#!/usr/bin/env bash
# start — run the listening watcher (foreground).
# ───────────────────────────────────────────────────────────────────────────
# listen-watcher tails FlashType's log and POSTs mic state to Eureka so the
# UI shows the「正在聆听」overlay while you hold the card button. Keep this
# running (one terminal) for the whole session; Ctrl-C to stop.
#
# Before tailing, it fires a self-test: flashes the overlay on→off so you can
# confirm the browser link works even before touching the card.
#
# (The transcription bridge, eureka-bridge.py, is launched by FlashType on
# each capture — not by this script.)
#
# Usage:  ./start.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="$HERE/flash-card.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    set -a; . "$ENV_FILE"; set +a
fi
EUREKA_LISTENING_URL="${EUREKA_LISTENING_URL:-http://localhost:8000/api/flash/listening}"

ping_overlay() {
    curl -fsS --max-time 4 -X POST "$EUREKA_LISTENING_URL" \
        -H 'Content-Type: application/json' -d "{\"state\":\"$1\"}" >/dev/null 2>&1
}

echo "self-test: flashing the 正在聆听 overlay (watch the app)…"
if ping_overlay on; then
    sleep 1
    ping_overlay off
    echo "  ✓ overlay reachable at $EUREKA_LISTENING_URL"
else
    echo "  ! could not reach $EUREKA_LISTENING_URL — is the backend up? (run ./doctor.sh)"
fi

echo "starting listen-watcher (Ctrl-C to stop)…"
exec python3 "$HERE/listen-watcher.py"
