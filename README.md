# Eureka Assistant

A personal-assistant app: capture thoughts by voice or text, and an AI agent files
them into typed cards (todos, ideas, expenses, notes, contacts, events, custom
skills…), answers questions over your own data, synthesizes illustrated HTML
report summaries, and syncs items to third-party tools (DingTalk / Notion / Google
Calendar) — now via **per-user** connected apps. A lightweight pet/gamification
layer rewards capture.

The primary client is the native Flutter app (`mobile/`). The Mac ring client
(`ring-desktop/`) connects a BraveChip ring directly for voice capture, gesture
routing, and haptic desktop notifications.

## Stack

| Layer | Tech |
|---|---|
| Primary client | **Flutter** — native iOS app (`mobile/`); reports render in an in-app WebView |
| Ring desktop | Python + Bleak + PyObjC (`ring-desktop/`, macOS) |
| Backend | FastAPI (Python, async) + **Google ADK** agents |
| LLM | **DeepSeek direct API** (`api.deepseek.com`) via LiteLLM; OpenRouter fallback for dev |
| Tools | **FastMCP** (internal CRUD) + external MCP (per-user Connected Apps) |
| Database | **MySQL 8** (aiomysql / pymysql) — *not* Postgres/pgvector |
| Auth | email + password → HS256 JWT, plus 百智 OAuth; per-user data isolation |
| AI imagery | 豆包 Seedream (Volcengine Ark) for report illustrations |
| Dev runtime | Docker Compose (MySQL `db` + `backend`) |

## What's inside

- **Capture (Flash)** — `POST /api/flash`: a dispatcher routes a thought to parallel
  sub-skills that file it into typed cards. Synchronous, returns the cards.
- **Chat assistant** — `POST /api/chat` (SSE): one ADK agent over your data — create /
  update / query / report-redirect, plus general Q&A.
- **Connected apps (per-user)** — each user connects their own DingTalk / Notion in
  *设置 → 已连接应用* (credentials encrypted server-side). The agent reads them
  synchronously (`use_connected_app` — 查日程/待办/改时间…) or writes asynchronously
  (`tool_create_task`). See [`spec/01-agent-architecture.md`](spec/01-agent-architecture.md) §1.6 / §1.6b.
- **Reports** — a synthesis pipeline turns selected assets into a single-file
  illustrated HTML report (charts + AI imagery + motion).
- **Pet / gamification** — a cosmetic pet that grows from capture, with a 40-rung
  milestone ladder.
- **百智 (100wiser) OAuth login** — 百智 as IdP; Eureka still mints its own session JWT.

The authoritative design is the **`spec/`** directory (chapters 00–13 + handoffs).
Start at [`spec/README.md`](spec/README.md).

## Prerequisites

- **Docker Desktop** (runs MySQL + the backend)
- **Flutter SDK** + **Xcode** (to run the iOS app on a simulator/device)
- **Node.js + npm** (to run the local Ring Demo website)
- A **DeepSeek API key** — get one at https://platform.deepseek.com (the agent needs it)
- *(optional)* Python 3 + macOS Bluetooth/Accessibility permissions for `ring-desktop/`

## Quick start

```bash
# 1. Clone
git clone <repo-url>
cd Eureka-Assistant

# 2. Configure — copy the template, set your DeepSeek key (+ a JWT secret)
cp .env.example .env
#   edit .env: DEEPSEEK_API_KEY=sk-...   (see .env.example for the full list)

# 3. Backend + MySQL (Docker): start db, migrate, seed skills, start backend
docker compose up -d db
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend python -m db.seed
docker compose up -d backend
#   backend → http://localhost:8000   (API docs at /docs, health at /health)

# 4. iOS app (Flutter) — the primary client
cd mobile
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:8000
#   register an account in-app, then capture from the + button or talk to the agent
```

## Configuration

All runtime config is environment variables in the **root `.env`** (read by
`docker-compose.yml` and passed into the backend). See `.env.example` for the
full, commented list. The essentials:

| Var | Required | What |
|---|---|---|
| `DEEPSEEK_API_KEY` | ✅ | Primary LLM (https://platform.deepseek.com). Blank → falls back to OpenRouter (dev only). |
| `JWT_SECRET` | ✅ (prod) | Session-token signing key. `openssl rand -hex 32`. |
| `CONNECTED_APPS_KEY` | ✅ (prod) | Fernet key encrypting per-user third-party credentials. The backend refuses to boot in prod without it. Generate: `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"` |
| `IMAGE_API_KEY` / `IMAGE_MODEL` | — | 豆包 Seedream key/model for report images (blank → reports come out image-less). |
| `OPENROUTER_API_KEY` | — | Legacy LLM fallback + the gemini image fallback. |
| `BAIZHI_*` | — | 百智 (100wiser) OAuth login (blank → 百智 login disabled, email login unaffected). |

After changing `.env`, **recreate** the backend so it picks up new env:
`docker compose up -d backend` (not `restart` — that keeps stale env).

### Third-party tools are per-user (not env)

Each user connects their own DingTalk / Notion in the app (*👤 → 已连接应用*): they
paste their AIHub gateway URL / token, which is stored **Fernet-encrypted, scoped to
their `user_id`**, and never returned to any client. The old global
`EUREKA_MCP_ENABLED` + `DINGTALK_AIHUB_URL_*` env path is **deprecated**.

## Credentials & security

`.env`, `deploy/.env.prod`, and the real files in `mcp-credentials/` are
**gitignored** — they never get committed. Forks ship only the `.env.example`
templates, so you bring your own keys. Never commit a real key or token.

## Deploy (production)

[`deploy/`](deploy/README.md) stands up the backend + MySQL behind **Caddy**
(automatic HTTPS via Let's Encrypt) on a single VM, so the iOS app reaches the API
over `https://`. See [`deploy/README.md`](deploy/README.md) for the full steps;
build the app with `--dart-define=API_BASE=https://<your-domain>`.

## Ring desktop (optional)

[`ring-desktop/`](ring-desktop/README.md) connects the BraveChip ring directly to
macOS. It supports eight gestures, voice transcription into the focused app, and
haptic notifications from Codex/Claude-style desktop workflows. The current code
was migrated from the former standalone repository; provenance is recorded in
[`ring-desktop/UPSTREAM.md`](ring-desktop/UPSTREAM.md).

```bash
cd ring-desktop
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp config.example.json config.json
python -m ring_desktop.app
```

## Ring Demo (local, real-ring flow)

The exhibition demo runs entirely on one Mac: MySQL and the Eureka Backend run
in Docker, while Ring Desktop and the Vite Demo Web app run on macOS. After
cloning the repository, run the setup script from the repository root:

```bash
./scripts/setup-ring-demo.sh
```

On its first run, the script checks the macOS prerequisites, copies
`.env.example` to the gitignored `.env`, generates a strong local JWT secret,
enables the exhibition Reset control, and exits before installing anything.
Edit `.env` and set:

```bash
DEEPSEEK_API_KEY=<the exhibition DeepSeek key>
```

Do not commit `.env` or share it in screenshots. Then rerun setup; it creates the
Ring Desktop virtualenv/config, installs the Demo Web dependencies, builds the
Backend, starts MySQL, and applies migrations and seed data:

```bash
./scripts/setup-ring-demo.sh
```

The setup is non-destructive: it never removes the Docker data volume and does
not replace an existing `.env` or `ring-desktop/config.json`. You can rerun its
launch checks without installing or changing anything:

```bash
./scripts/setup-ring-demo.sh --check
```

### Run the exhibition demo

Start all four local processes from one terminal:

```bash
./scripts/run-ring-demo.sh
```

The script starts MySQL and the Backend, waits for the Backend health check,
starts the Demo Web on the fixed address `http://127.0.0.1:5173`, and keeps Ring
Desktop in the foreground. Keep the terminal open. `Control-C` stops Ring
Desktop and the Demo Web; the Docker services and exhibition data stay running
for the next visitor.

On the first Ring Desktop launch, allow Bluetooth when macOS prompts. Also open
*System Settings → Privacy & Security → Accessibility* and enable the terminal
app that launches the script. If Bluetooth was previously denied, enable that
terminal in the Bluetooth privacy list too. Restart the run script after changing
permissions.

Open `http://localhost:5173`. Sign in with an existing local UReka email/password,
or use **Create account** (passwords must be at least six characters). Use the same
account in the existing UReka client to confirm that Flash assets share the same
Backend/MySQL data.

The low-emphasis **Operator Controls** panel is available from Home, Flash, and
Vibe. It shows the current account and requires a second confirmation before
resetting. A successful reset deletes only that account's demo content and clears
the current Demo UI; it preserves the account, Skills, Connected Apps, card
configuration, and active ring connection. Reset before handing the demo to the
next visitor. If reset reports that it is unavailable, confirm
`DEMO_RESET_ENABLED=true` in `.env` and restart the run script.

### Troubleshooting

| Symptom | Check |
|---|---|
| Docker prerequisite or health check fails | Start Docker Desktop, then run `./scripts/setup-ring-demo.sh --check`. Inspect Backend startup with `docker compose logs backend`. |
| Port `8000` is occupied | Stop the other local Backend, or identify it with `lsof -nP -iTCP:8000 -sTCP:LISTEN`. |
| Demo Web says port `5173` is occupied | Close the earlier Vite process, or identify it with `lsof -nP -iTCP:5173 -sTCP:LISTEN`. The runner intentionally does not silently choose another port. |
| Ring connection API on `17863` is unavailable | Stop any older Ring Desktop process, restart `./scripts/run-ring-demo.sh`, then check macOS Bluetooth permission. |
| Gestures do not reach Codex or DingTalk | Grant Accessibility permission to the terminal that launched the script, restart it, and focus the target app. |
| Ring is absent from scan results | Disconnect it from the phone/other Mac, keep it awake, and scan again. |
| Operator Reset returns `401` | Sign in again; the local account token is no longer valid. |

### Physical-ring smoke checklist

This checklist requires a real ring and is not covered by the automated tests:

1. Stop any phone app that may already own the ring connection, then scan for and
   connect the `BCL…` ring in the Demo Web connection panel.
2. Enter Flash. Double-tap once to start recording and double-tap again to stop.
3. Confirm the transcript appears in Flash, `/api/flash` returns real assets, and
   the cards render in the Demo Web.
4. Open the existing UReka client with the same account and confirm those assets
   appear there.
5. Return home, enter Vibe, focus Codex, and exercise its configured gesture
   mappings; then focus DingTalk and exercise its configured mappings.
6. Start ASR, switch between Flash and Vibe before transcription completes, and
   confirm the late result is not delivered into the new mode.
7. Close the Demo Web tab and confirm Ring Desktop returns to standalone routing
   (the lease fallback expires within 10 seconds if browser release is missed).

## Reset the whole local database (development only)

Do not use this during an exhibition: it deletes every local account and all
configuration. Use **Operator Controls → Reset demo data** for normal visitor
turnover.

```bash
docker compose down -v        # drops the MySQL volume
docker compose up -d db
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend python -m db.seed
docker compose up -d backend
```

## Project layout

```
mobile/          Flutter iOS app — the PRIMARY client
backend/         FastAPI app, ADK agents, FastMCP servers, Alembic migrations, db/seed
ring-desktop/    macOS ring BLE, voice, gesture routing, and haptic notifications
ring-demo/       Local React/Vite website for the real-ring Flash and Vibe demo
deploy/          Production deploy (Caddy auto-HTTPS + Docker Compose on a VM)
spec/            Source-of-truth spec (chapters 00–13 + handoffs)
docker-compose.yml   MySQL db + backend for local dev
```

## API reference (selected)

```
POST /api/auth/register|login          Email + password → JWT
GET  /api/auth/baizhi/authorize        百智 OAuth bridge URL (§13.1)
POST /api/flash                        Flash capture → agent pipeline → asset cards
POST /api/chat                         Chat with the agent (SSE stream)
GET  /api/sessions[/{id}]              Sessions + messages
GET  /api/assets   POST /api/assets    List / create assets (filter by skill/keyword/date)
GET  /api/events, /api/contacts        First-class entities
GET  /api/skills                       Registered skill types (render specs)
GET  /api/connectors                   Connectable third-party apps (catalog)
GET  /api/connected-apps               This user's connected apps (per-user)
GET  /api/reports  POST /api/reports   Synthesis/report engine
GET  /api/pet, /api/pet/milestones     Pet + 40-milestone progress
GET  /api/tasks/{id}                   Async third-party-MCP task status
GET  /api/notifications                Notifications (+ SSE stream)
GET  /health                           Health check
```
