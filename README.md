# Eureka-BrandNew

Full-stack rebuild of Eureka 3.0 — personal knowledge OS.

## Stack

| Layer | Tech |
|---|---|
| Frontend | HTML/JS → Vercel |
| Backend | FastAPI + Python |
| Agent | Google ADK + Claude (via LiteLLM) |
| MCP Tools | FastMCP |
| Database | PostgreSQL + pgvector |
| Deployment | Google Cloud Run (backend) + Vercel (frontend) |

## Local Development

### 1. Start PostgreSQL

```bash
docker compose up db -d
```

### 2. Run migrations + seed

```bash
cd backend
pip install -r requirements.txt
DATABASE_URL=postgresql://eureka:eureka@localhost:5432/eureka alembic upgrade head
DATABASE_URL=postgresql://eureka:eureka@localhost:5432/eureka python -m db.seed
```

### 3. Configure environment

```bash
cp backend/.env.example backend/.env
# Edit backend/.env — set ANTHROPIC_API_KEY
```

### 4. Start backend

```bash
cd backend
uvicorn main:app --reload
# API available at http://localhost:8000
# Docs at http://localhost:8000/docs
```

### 5. Open frontend

```bash
# Open Eureka-BrandNew/frontend/index.html in browser
# Set backend URL in browser console:
# localStorage.setItem('EUREKA_API', 'http://localhost:8000')
```

## Deployment

### Frontend → Vercel
1. Connect GitHub repo
2. Set Root Directory: `Eureka-BrandNew/frontend`
3. No build command needed (static)

### Backend → Google Cloud Run
```bash
cd backend
gcloud run deploy eureka-backend \
  --source . \
  --region asia-east1 \
  --set-env-vars "DATABASE_URL=...,ANTHROPIC_API_KEY=..."
```

### Database → Cloud SQL (PostgreSQL)
```bash
gcloud sql instances create eureka-db \
  --database-version=POSTGRES_16 \
  --region=asia-east1 \
  --tier=db-f1-micro
```

## API Reference

```
POST /api/flash          Flash note → agent pipeline → asset cards
POST /api/query          Global Q&A across all assets
GET  /api/sessions       List sessions (filter by date)
GET  /api/sessions/{id}  Session detail + assets
GET  /api/assets         List assets (structured filter or keyword)
GET  /api/assets/{id}    Single asset detail
POST /api/assets         Manually create asset
GET  /health             Health check
```

## Architecture

```
User Input (text/voice)
    ↓
FastAPI (/api/flash or /api/query)
    ↓
Google ADK Root Agent (intent router)
    ├── Flash Agent → dispatcher → skills → write assets to DB
    └── Query Agent → SQL index / semantic search → answer
    ↓
MCP Tools (FastMCP) ↔ PostgreSQL
    ↓
asset_fields index for structured queries (no LLM needed)
```
