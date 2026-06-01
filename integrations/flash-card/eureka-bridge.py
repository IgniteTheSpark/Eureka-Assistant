#!/usr/bin/env python3
"""
eureka-bridge — FlashType `external` ASR hook → Eureka flash pipeline.

The W1/W2 BLE card + FlashType handle BLE handshake, Opus capture, and
decode to a 16kHz mono WAV. FlashType's `--asr external` backend then runs
THIS command with the decoded WAV path and expects the transcript on stdout
(see ExternalCommandTranscriber.swift).

We use that hook to splice the card into Eureka:
  1. Transcribe the WAV locally with whisper.cpp (offline, no API key).
  2. POST the transcript to Eureka's existing /api/flash text endpoint, which
     runs the flash pipeline (intent dispatch → assets / events / etc.).
  3. Print the transcript to stdout — FlashType's contract.

Why ASR here (host) instead of in Eureka: whisper.cpp is installed on the
host, while the Eureka backend runs in Docker. Transcribing in the bridge
avoids shipping whisper into the container or needing a cloud key, and
reuses the already-working /api/flash text path.

Wired up from scripts/env.local.sh:
    export FLASH_TYPE_ASR="external"
    export FLASH_TYPE_ASR_COMMAND='python3 /abs/path/eureka-bridge.py {wav} {language}'

Tunable via env (sensible macOS/Homebrew defaults):
    EUREKA_WHISPER_BIN     default /opt/homebrew/bin/whisper-cli
    EUREKA_WHISPER_MODEL   default ~/.flash-type/models/ggml-base.bin
    EUREKA_FLASH_URL       default http://localhost:8000/api/flash
"""
import json
import os
import subprocess
import sys
import urllib.request

HOME = os.path.expanduser("~")
WHISPER_BIN   = os.environ.get("EUREKA_WHISPER_BIN", "/opt/homebrew/bin/whisper-cli")
WHISPER_MODEL = os.environ.get("EUREKA_WHISPER_MODEL", f"{HOME}/.flash-type/models/ggml-base.bin")
FLASH_URL     = os.environ.get("EUREKA_FLASH_URL", "http://localhost:8000/api/flash")


def log(msg: str) -> None:
    # Diagnostics go to stderr so they never pollute the transcript stdout
    # that FlashType reads.
    sys.stderr.write(f"[eureka-bridge] {msg}\n")
    sys.stderr.flush()


def transcribe(wav_path: str, language: str) -> str:
    """Run whisper.cpp and return the plain transcript (no timestamps)."""
    cmd = [WHISPER_BIN, "-m", WHISPER_MODEL, "-f", wav_path, "-nt"]
    if language:
        cmd += ["-l", language]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        log(f"whisper failed ({proc.returncode}): {proc.stderr.strip()[:300]}")
        return ""
    # -nt prints just the text (possibly across lines); join + tidy.
    return " ".join(line.strip() for line in proc.stdout.splitlines() if line.strip()).strip()


def post_to_eureka(text: str) -> None:
    """Feed the transcript into Eureka's flash pipeline. Best-effort: a
    backend hiccup must not make FlashType think ASR failed."""
    body = json.dumps({"text": text, "source": "voice"}).encode("utf-8")
    req = urllib.request.Request(
        FLASH_URL, data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        derived = data.get("derived_assets") or data.get("cards") or []
        log(f"posted to Eureka ok — {len(derived)} item(s) derived")
    except Exception as e:  # noqa: BLE001 — never crash the ASR hook
        log(f"POST to Eureka failed (transcript still returned): {e}")


def main() -> int:
    wav = sys.argv[1] if len(sys.argv) > 1 else ""
    language = sys.argv[2] if len(sys.argv) > 2 else "zh"

    if not wav or not os.path.exists(wav):
        log(f"missing/invalid wav path: {wav!r}")
        return 1

    text = transcribe(wav, language)
    if not text:
        log("empty transcript")
        return 1

    post_to_eureka(text)

    # FlashType reads stdout as the final transcript.
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
