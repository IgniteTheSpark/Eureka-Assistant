#!/usr/bin/env python3
"""
listen-watcher — bridge the card's recording state into Eureka's「正在聆听」
overlay WITHOUT touching FlashType (keeps the vendor sample pristine).

FlashType logs `Flash memo started: ...` on button-down and
`Flash memo finished: ...` on release. We tail its log and POST
/api/flash/listening {on|off} so the Eureka UI can show a live listening
indicator the moment you hold the card button.

Run it alongside FlashType (separate terminal):
    python3 listen-watcher.py

Env overrides:
    EUREKA_LISTENING_URL   default http://localhost:8000/api/flash/listening
    FLASH_TYPE_LOG         default ~/.flash-type/flash-type.log
"""
import json
import os
import time
import urllib.request

from _env import load_env_file

# Pick up flash-card.env when run bare (start.sh also sources it; shell wins).
load_env_file(__file__)

LOG_PATH = os.environ.get("FLASH_TYPE_LOG", os.path.expanduser("~/.flash-type/flash-type.log"))
URL = os.environ.get("EUREKA_LISTENING_URL", "http://localhost:8000/api/flash/listening")

# Safety net: if a "started" never gets a matching "finished" (app crash,
# missed log line), auto-clear the overlay after this many seconds.
MAX_LISTEN_SEC = 30


def post(state: str) -> None:
    body = json.dumps({"state": state}).encode("utf-8")
    req = urllib.request.Request(
        URL, data=body, headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=5).read()
        print(f"[listen-watcher] → {state}", flush=True)
    except Exception as e:  # noqa: BLE001
        print(f"[listen-watcher] POST {state} failed: {e}", flush=True)


def follow(path: str):
    """tail -F: wait for the file, seek to end, yield appended lines."""
    while not os.path.exists(path):
        time.sleep(0.5)
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(0, os.SEEK_END)
        while True:
            line = f.readline()
            if line:
                yield line
            else:
                yield None  # tick — lets the caller check the watchdog
                time.sleep(0.2)


def main() -> None:
    print(f"[listen-watcher] watching {LOG_PATH}", flush=True)
    listening = False
    started_at = 0.0
    for line in follow(LOG_PATH):
        now = time.monotonic()
        if line is None:
            # watchdog: force-off if a recording has been "open" too long
            if listening and (now - started_at) > MAX_LISTEN_SEC:
                post("off")
                listening = False
            continue
        if "Flash memo started" in line:
            if not listening:
                post("on")
                listening = True
                started_at = now
        elif "Flash memo finished" in line or "Flash memo handling failed" in line:
            if listening:
                post("off")
                listening = False


if __name__ == "__main__":
    main()
