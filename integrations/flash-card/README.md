# Flash-card hardware bridge

Connects the **W1/W2 BLE voice card** to Eureka so holding the card's
flash-memo button records a thought, transcribes it on your Mac, and runs it
through the flash pipeline — assets, events, reminders appear in the app.

## The chain

```
┌────────┐   BLE    ┌───────────┐  WAV   ┌──────────────────┐  text   ┌─────────┐
│ W1/W2  │ ───────▶ │ FlashType │ ─────▶ │ eureka-bridge.py │ ──────▶ │ Eureka  │
│  card  │  hold    │ (Mac app) │ {wav}  │ (whisper.cpp ASR)│  POST   │ backend │
└────────┘  button  └─────┬─────┘        └──────────────────┘ /api/flash └────────┘
                          │ logs "Flash memo started/finished"
                          ▼
                  ┌──────────────────┐  POST /api/flash/listening {on|off}
                  │ listen-watcher.py│ ──────────────────────────▶ 「正在聆听」overlay
                  └──────────────────┘
```

**FlashType is a third-party Mac app** and owns the part we can't: the BLE
handshake, Opus capture, and WAV decode. This folder is the glue around it —
it does **not** replace FlashType. You install + pair the card in FlashType
once; everything else here is one command.

## Prerequisites

- **FlashType** installed, with the W1/W2 card paired (handles BLE + capture).
- **Homebrew** — for whisper.cpp (`setup.sh` offers to install it).
- **Eureka backend** running locally (`docker compose up -d backend` from the
  repo root).

## Quickstart

```bash
cd integrations/flash-card

# 1. Install whisper + model, create config, print the FlashType wiring.
./setup.sh

# 2. Paste the printed FLASH_TYPE_ASR / FLASH_TYPE_ASR_COMMAND exports into
#    the shell FlashType launches from (its scripts/env.local.sh), then
#    restart FlashType so it picks up the external-ASR command.

# 3. Run the listening watcher (keep it open; Ctrl-C to stop).
./start.sh
```

Now hold the card button: the app shows 「正在聆听」 while you speak, and the
transcript flows into your flash session on release.

## Scripts

| Script | What it does |
|---|---|
| `setup.sh` | Idempotent. Installs whisper-cpp (with a prompt), downloads the model, creates `flash-card.env`, prints the FlashType config, runs `doctor.sh`. |
| `doctor.sh` | Read-only preflight. Checks whisper, model, backend, FlashType log, config. Run it first when something doesn't work. |
| `start.sh` | Self-tests the overlay, then runs `listen-watcher.py` in the foreground. |
| `eureka-bridge.py` | Invoked **by FlashType** per capture: whisper.cpp transcribe → `POST /api/flash`. |
| `listen-watcher.py` | Tails FlashType's log → `POST /api/flash/listening {on\|off}`. |
| `_env.py` | Loads `flash-card.env` into the two Python scripts (FlashType doesn't source your shell). |

## Configuration

All tunables live in `flash-card.env` (created from `flash-card.env.example`,
**gitignored**). Both the shell scripts and the Python scripts read it.

| Var | Default | Meaning |
|---|---|---|
| `EUREKA_FLASH_URL` | `http://localhost:8000/api/flash` | Transcript ingest endpoint. |
| `EUREKA_LISTENING_URL` | `http://localhost:8000/api/flash/listening` | Mic-state endpoint. |
| `EUREKA_WHISPER_BIN` | `/opt/homebrew/bin/whisper-cli` | whisper.cpp binary. |
| `EUREKA_WHISPER_MODEL` | `~/.flash-type/models/ggml-base.bin` | ggml model. Swap for `small`/`medium` for more accuracy. |
| `EUREKA_WHISPER_LANG` | `zh` | Language hint (FlashType's per-capture `{language}` overrides it). |
| `FLASH_TYPE_LOG` | `~/.flash-type/flash-type.log` | Log the watcher tails. |

## Troubleshooting

Run `./doctor.sh` — it pinpoints which link is broken. Common cases:

- **Card records but nothing reaches Eureka** → FlashType isn't using the
  external ASR command. Re-check the `FLASH_TYPE_ASR_COMMAND` export and
  restart FlashType. Confirm whisper works: `./doctor.sh`.
- **No 「正在聆听」 overlay** → `listen-watcher.py` isn't running, or
  `FLASH_TYPE_LOG` is wrong. `start.sh`'s self-test should flash the overlay;
  if it doesn't, the backend is unreachable.
- **Empty / wrong transcript** → try a larger model (`ggml-small.bin`) or set
  `EUREKA_WHISPER_LANG` correctly.

## Optional: auto-start the watcher at login (launchd)

`start.sh` runs in the foreground (one terminal). To have the watcher run in
the background at login instead, create
`~/Library/LaunchAgents/com.eureka.flashcard.watcher.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.eureka.flashcard.watcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>/ABS/PATH/TO/integrations/flash-card/listen-watcher.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

Then `launchctl load ~/Library/LaunchAgents/com.eureka.flashcard.watcher.plist`.
(The transcription bridge still runs on demand via FlashType — no agent needed
for it.)

## Production note

The bridge POSTs without an auth token because the demo backend runs in
single-user mode (`core/auth.py` returns a fixed user id). For a multi-user
deployment, add an `Authorization` header in `eureka-bridge.py` /
`listen-watcher.py` and validate it in `get_current_user_id`.
