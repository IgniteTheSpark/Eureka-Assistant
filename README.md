# Eureka Assistant

A personal-assistant app: capture thoughts by voice or text, and an AI agent
files them into typed cards (todos, ideas, expenses, notes, custom skills…),
answers questions over your own data, generates HTML report summaries, and
syncs items to third-party tools (DingTalk / Notion / Google Calendar) via MCP.

## Stack

| Layer | Tech |
|---|---|
| Frontend | Vite + React + TypeScript + Tailwind |
| Backend | FastAPI (Python) |
| Agent | Google ADK + LLM via LiteLLM (OpenRouter) |
| Tools | FastMCP (internal CRUD + external MCP servers) |
| Database | PostgreSQL + pgvector |
| Dev runtime | Docker Compose (db + backend) |

## Prerequisites

- **Docker Desktop** (runs Postgres + the backend)
- **Node 18+** (frontend dev server)
- An **OpenRouter API key** — free to create at https://openrouter.ai/keys
  (the agent needs it; everything else is optional)

## Quick start

```bash
# 1. Clone
git clone https://github.com/IgniteTheSpark/Eureka-Assistant.git
cd Eureka-Assistant

# 2. Configure — copy the template and fill in your OpenRouter key
cp .env.example .env
#   then edit .env: set OPENROUTER_API_KEY=sk-or-v1-...
#   (leave the rest as-is for a first run — MCP defaults to a built-in stub)

# 3. Backend + database (Docker): start db, migrate, seed skills, start backend
docker compose up -d db
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend python -m db.seed
docker compose up -d backend
#   backend → http://localhost:8000   (API docs at /docs)

# 4. Frontend (separate terminal)
cd frontend
npm install
npm run dev
#   app → http://localhost:5173
```

Open **http://localhost:5173** and you're running. The DB starts empty (just the
seeded skill types) — create a few items from the bottom **+** button, or talk
to the agent.

## Configuration

All runtime config is environment variables in `.env` (read by `docker-compose.yml`).
See `.env.example` for the full list with comments. The essentials:

| Var | Required | What |
|---|---|---|
| `OPENROUTER_API_KEY` | ✅ | LLM access (https://openrouter.ai/keys) |
| `EUREKA_MCP_ENABLED` | — | Which external MCPs the agent can call. Default `fake_external` (a stub — no real account needed). |
| `DINGTALK_AIHUB_URL_*` | — | DingTalk AIHub gateway URLs (only if you enable the `dingtalk_*` MCPs) |

### Optional: real third-party tools

- **DingTalk** — subscribe to the MCPs on AIHub, copy each instance's 接入 URL
  (it contains a `?key=…`) into `DINGTALK_AIHUB_URL_CALENDAR/TODO/NOTES`, and add
  `dingtalk_calendar,dingtalk_todo,dingtalk_notes` to `EUREKA_MCP_ENABLED`.
- **Google Calendar** — uses OAuth credential *files*, not env vars. Drop them
  in `mcp-credentials/` and add `google_calendar` to `EUREKA_MCP_ENABLED`.
  See `mcp-credentials/README.md` for the one-time OAuth steps.

After changing `.env`, restart the backend: `docker compose restart backend`.

## Credentials & security

`.env` and the real files in `mcp-credentials/` are **gitignored** — they never
get committed. Forks ship only `.env.example` and `mcp-credentials/README.md`,
so you bring your own keys. Never commit a real key or token.

## Hardware voice capture (optional)

`integrations/flash-card/` links the **W1/W2 BLE voice card** to Eureka: hold
the card button → FlashType captures over BLE → local Whisper ASR → the flash
pipeline, with a live 「正在聆听」 overlay. It wraps the third-party FlashType
app (which owns BLE capture); the bridge, watcher, setup, and docs are here.

```bash
cd integrations/flash-card
./setup.sh      # install whisper + model, write config, print FlashType wiring
./start.sh      # run the listening watcher (foreground)
./doctor.sh     # preflight when something doesn't connect
```

See [`integrations/flash-card/README.md`](integrations/flash-card/README.md)
for the full setup, the chain diagram, and troubleshooting.

## Reset the database

To wipe data and re-seed from scratch (keeps schema, re-runs migrations + seed):

```bash
docker compose down -v        # drops the db volume
docker compose up -d db
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend python -m db.seed
docker compose up -d backend
```

## Project layout

```
backend/         FastAPI app, ADK agents, FastMCP servers, Alembic migrations, db/seed
frontend/        Vite + React app (the UI)
integrations/    flash-card BLE → Whisper → /api/flash bridge (optional)
docs/, rebuild/  product/design/architecture notes
docker-compose.yml   db + backend for local dev
```

## API reference (selected)

```
POST /api/flash              Flash capture → agent pipeline → asset cards
POST /api/chat               Chat with the agent (SSE stream)
GET  /api/sessions[/{id}]    Sessions + messages
GET  /api/assets             List assets (filter by skill / keyword / date)
POST /api/assets             Create an asset
GET  /api/events, /contacts  First-class entities
GET  /api/skills             Registered skill types (render specs)
GET  /api/tasks/{id}         Async third-party-MCP task status
GET  /api/notifications      Notifications (+ SSE stream)
GET  /health                 Health check
```
