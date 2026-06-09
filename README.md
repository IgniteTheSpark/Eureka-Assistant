# Eureka Assistant

A personal-assistant app: capture thoughts by voice or text, and an AI agent files
them into typed cards (todos, ideas, expenses, notes, contacts, events, custom
skills…), answers questions over your own data, synthesizes illustrated HTML
report summaries, and syncs items to third-party tools (DingTalk / Notion / Google
Calendar) — now via **per-user** connected apps. A lightweight pet/gamification
layer rewards capture.

The **primary client is the native Flutter iOS app** (`mobile/`); the web app
(`frontend/`) is a visual-parity reference, not the shipping client.

## Stack

| Layer | Tech |
|---|---|
| Primary client | **Flutter** — native iOS app (`mobile/`); reports render in an in-app WebView |
| Web (reference) | Vite + React + TypeScript (`frontend/`, parity reference — not shipped) |
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
- A **DeepSeek API key** — get one at https://platform.deepseek.com (the agent needs it)
- *(optional)* Node 18+ if you want to run the reference web frontend

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

> The reference web frontend (optional): `cd frontend && npm install && npm run dev`
> → http://localhost:5173. It's a parity demo, not the shipping client.

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

## Hardware voice capture (optional)

[`integrations/flash-card/`](integrations/flash-card/README.md) links a **BLE voice
card** to Eureka on macOS: hold the card button → FlashType captures over BLE → local
Whisper ASR → the flash pipeline. (A native phone-direct path — phone ↔ recording card
over BLE/WiFi — is designed in [`spec/13-baizhi-integration.md`](spec/13-baizhi-integration.md) §13.3.)

```bash
cd integrations/flash-card
./setup.sh      # install whisper + model, write config, print FlashType wiring
./start.sh      # run the listening watcher (foreground)
./doctor.sh     # preflight when something doesn't connect
```

## Reset the database

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
frontend/        Vite + React reference demo (visual parity — not the shipping client)
deploy/          Production deploy (Caddy auto-HTTPS + Docker Compose on a VM)
spec/            Source-of-truth spec (chapters 00–13 + handoffs)
integrations/    flash-card BLE → Whisper → /api/flash bridge (macOS, optional)
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
