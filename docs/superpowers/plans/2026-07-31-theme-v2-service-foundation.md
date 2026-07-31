# Theme V2 Service Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the isolated `theme_v2_service` runtime, independent MySQL database, authentication boundary, core UserSkill/Asset/Event records, durable WorkflowJob queue, and Docker lifecycle required by every Theme V2 backend feature.

**Architecture:** A modular FastAPI monolith and a separate Worker process share one MySQL 8 database and one Python image. SQLAlchemy/Alembic own persistence, jobs use `FOR UPDATE SKIP LOCKED` plus leases, and all files and Docker resources remain isolated from the legacy backend.

**Tech Stack:** Python 3.12, FastAPI 0.115+, SQLAlchemy 2.0.36+, Alembic 1.14+, MySQL 8.0, aiomysql, pymysql, Pydantic Settings, pytest, Docker Compose.

## Global Constraints

- Source lives under `theme_v2_service/`; it must not import runtime modules from `backend/`.
- Compose project name is `eureka-theme-v2`; API host port is `8100`, MySQL host port is `127.0.0.1:3307`.
- The database is `eureka_theme_v2`, uses `utf8mb4`, starts empty, and has an independent Alembic history and named volume.
- UUIDs use `CHAR(36)`; timestamps use UTC `DATETIME(6)` and serialize as ISO 8601 with `Z`.
- API and Worker use the same image but different entry points.
- Phase 1 has one API instance and at least one Worker; no Redis, Kafka, Celery, PostgreSQL, or legacy database connection.
- Every mutation uses an injected `AsyncSession`; domain/application code must not open or commit its own session.
- Unit tests may use fakes; locking, lease, migration, and transaction tests must run against MySQL 8 rather than SQLite.
- Do not stop or delete the legacy Compose project or its volumes in this plan.

---

## File Structure

### Create

- `theme_v2_service/app/main.py` — FastAPI app and lifecycle.
- `theme_v2_service/app/worker.py` — durable job worker entry point.
- `theme_v2_service/app/config.py` — environment validation.
- `theme_v2_service/app/auth/security.py` — HS256 verification.
- `theme_v2_service/app/auth/dependencies.py` — `get_current_user_id`.
- `theme_v2_service/app/db/base.py` — declarative base and UTC helpers.
- `theme_v2_service/app/db/session.py` — async session factory.
- `theme_v2_service/app/db/models.py` — foundation ORM models.
- `theme_v2_service/app/domains/assets/service.py` — UserSkill/Asset/Event application services.
- `theme_v2_service/app/domains/assets/api.py` — minimal create/read endpoints used by later slices.
- `theme_v2_service/app/jobs/models.py` — job enums and payload types.
- `theme_v2_service/app/jobs/queue.py` — claim, lease, complete, fail.
- `theme_v2_service/app/jobs/registry.py` — job handler registry.
- `theme_v2_service/app/jobs/runner.py` — polling loop.
- `theme_v2_service/migrations/env.py` and initial revision — isolated schema.
- `theme_v2_service/tests/unit/` — pure configuration/auth/job tests.
- `theme_v2_service/tests/integration/` — MySQL migration, transaction, and lease tests.
- `theme_v2_service/Dockerfile`
- `theme_v2_service/requirements.txt`
- `theme_v2_service/requirements-dev.txt`
- `theme_v2_service/pytest.ini`
- `theme_v2_service/alembic.ini`
- `docker-compose.theme-v2.yml`
- `.env.theme-v2.example`

### Preserve

- `backend/`
- `docker-compose.yml`
- `docker-compose.prod.yml`
- legacy Docker volumes and networks

---

### Task 1: Bootstrap the isolated Python package and configuration

**Files:**

- Create: `theme_v2_service/app/__init__.py`
- Create: `theme_v2_service/app/config.py`
- Create: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/requirements.txt`
- Create: `theme_v2_service/requirements-dev.txt`
- Create: `theme_v2_service/pytest.ini`
- Create: `theme_v2_service/Dockerfile`
- Create: `docker-compose.theme-v2.yml`
- Create: `theme_v2_service/docker/mysql-init/01-test-database.sql`
- Create: `theme_v2_service/tests/unit/test_config.py`

**Interfaces:**

- Consumes: environment variables from `.env.theme-v2` or Compose.
- Produces: `Settings`, `get_settings()`, `app`, `/health`, and `/ready`.

- [ ] **Step 1: Write failing configuration tests**

```python
from pydantic import ValidationError
from app.config import Settings


def test_prod_rejects_dev_secret():
    try:
        Settings(env="prod", database_url="mysql://u:p@mysql/db", jwt_secret="dev-insecure-change-me")
    except ValidationError:
        return
    raise AssertionError("prod must reject the development JWT secret")


def test_theme_v2_defaults_are_isolated():
    settings = Settings()
    assert settings.api_port == 8000
    assert settings.database_url.endswith("/eureka_theme_v2")
    assert settings.worker_poll_seconds == 0.5
    assert settings.job_lease_seconds == 60
```

- [ ] **Step 2: Run the test and verify the missing package failure**

Run: `cd theme_v2_service && python -m pytest tests/unit/test_config.py -q`

Expected: FAIL with `ModuleNotFoundError: No module named 'app'`.

- [ ] **Step 3: Add dependencies and typed settings**

`requirements.txt` must contain the approved version floors:

```text
fastapi>=0.115.0
uvicorn[standard]>=0.32.0
sqlalchemy>=2.0.36
aiomysql>=0.2.0
pymysql>=1.1.0
alembic>=1.14.0
pydantic>=2.10.0
pydantic-settings>=2.7.0
orjson>=3.10.0,<4.0.0
httpx>=0.28.0
```

`requirements-dev.txt`:

```text
-r requirements.txt
pytest>=8.3.0
pytest-asyncio>=0.24.0
```

`app/config.py`:

```python
from functools import lru_cache
from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "dev"
    api_port: int = 8000
    database_url: str = "mysql://theme_v2:theme_v2@mysql:3306/eureka_theme_v2"
    jwt_secret: str = "dev-insecure-change-me"
    worker_poll_seconds: float = 0.5
    job_lease_seconds: int = 60
    media_root: str = "/data/media"
    default_user_timezone: str = "Asia/Shanghai"

    @model_validator(mode="after")
    def reject_insecure_prod(self):
        if self.env in {"prod", "production"} and self.jwt_secret == "dev-insecure-change-me":
            raise ValueError("JWT_SECRET must be changed in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 4: Add the minimal app and health route**

```python
from fastapi import FastAPI

app = FastAPI(title="Eureka Theme V2 API", version="2.0.0")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "theme-v2"}
```

`/ready` is added in Task 2 after the database dependency exists.

- [ ] **Step 5: Add the bootstrap image and isolated MySQL/API Compose**

The Dockerfile installs `requirements-dev.txt`, copies the service, and runs
`uvicorn app.main:app --host 0.0.0.0 --port 8000`. The initial Compose file sets
`name: eureka-theme-v2`, defines the MySQL service and healthcheck from Task 6,
defines API on host port 8100 with the Theme V2 database URL, and defines a
non-running-by-default `test` service whose URL targets `eureka_theme_v2_test`.
The MySQL init SQL creates that test database with `utf8mb4` and grants it only
to the `theme_v2` user. Task 6 adds Alembic ordering, Worker, media volume, and
final health gates after every foundation model exists.

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY . .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```sql
CREATE DATABASE IF NOT EXISTS eureka_theme_v2_test
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON eureka_theme_v2_test.* TO 'theme_v2'@'%';
```

```yaml
name: eureka-theme-v2
services:
  mysql:
    image: mysql:8.0
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    environment:
      MYSQL_DATABASE: eureka_theme_v2
      MYSQL_USER: theme_v2
      MYSQL_PASSWORD: ${THEME_V2_DB_PASSWORD:-theme_v2}
      MYSQL_ROOT_PASSWORD: ${THEME_V2_DB_ROOT_PASSWORD:-theme_v2_root}
    ports: ["127.0.0.1:3307:3306"]
    volumes:
      - mysql_data:/var/lib/mysql
      - ./theme_v2_service/docker/mysql-init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u theme_v2 -p$$MYSQL_PASSWORD --silent"]
      interval: 5s
      timeout: 5s
      retries: 20
  api:
    build: ./theme_v2_service
    ports: ["8100:8000"]
    environment:
      DATABASE_URL: mysql://theme_v2:${THEME_V2_DB_PASSWORD:-theme_v2}@mysql:3306/eureka_theme_v2
      JWT_SECRET: ${THEME_V2_JWT_SECRET:-dev-insecure-change-me}
    depends_on:
      mysql: {condition: service_healthy}
    volumes: ["./theme_v2_service:/app"]
  test:
    build: ./theme_v2_service
    profiles: ["test"]
    environment:
      DATABASE_URL: mysql://theme_v2:${THEME_V2_DB_PASSWORD:-theme_v2}@mysql:3306/eureka_theme_v2_test
      JWT_SECRET: test-only-secret
      ENV: test
    depends_on:
      mysql: {condition: service_healthy}
    volumes:
      - ./theme_v2_service:/app
      - media_data:/data/media
volumes:
  mysql_data:
  media_data:
```

- [ ] **Step 6: Run the unit test**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_config.py -q`

Expected: `2 passed`.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app theme_v2_service/tests/unit/test_config.py theme_v2_service/requirements.txt theme_v2_service/requirements-dev.txt theme_v2_service/pytest.ini theme_v2_service/Dockerfile theme_v2_service/docker/mysql-init/01-test-database.sql docker-compose.theme-v2.yml
git commit -m "feat(theme-v2): bootstrap isolated service"
```

---

### Task 2: Add MySQL sessions, physical type conventions, and test schema lifecycle

**Files:**

- Create: `theme_v2_service/app/db/__init__.py`
- Create: `theme_v2_service/app/db/base.py`
- Create: `theme_v2_service/app/db/session.py`
- Create: `theme_v2_service/tests/conftest.py`
- Create: `theme_v2_service/tests/integration/test_database.py`
- Modify: `theme_v2_service/app/main.py`

**Interfaces:**

- Consumes: `Settings.database_url`.
- Produces: `Base`, `new_uuid()`, `utc_now()`, `AsyncSessionFactory`, `session_scope()`, isolated MySQL fixtures, and database-backed `/ready`.

- [ ] **Step 1: Write a failing MySQL migration test**

```python
from sqlalchemy import text
from app.db.session import AsyncSessionFactory


async def test_theme_v2_test_mysql_connection():
    async with AsyncSessionFactory() as session:
        database = (await session.execute(text("SELECT DATABASE()"))).scalar_one()
    assert database == "eureka_theme_v2_test"
```

- [ ] **Step 2: Add base and session modules**

```python
from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def new_uuid() -> str:
    return str(uuid4())


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)
```

```python
from contextlib import asynccontextmanager
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from app.config import get_settings


def _async_url(url: str) -> str:
    scheme, rest = url.split("://", 1)
    return f"{scheme.split('+', 1)[0]}+aiomysql://{rest}"


engine = create_async_engine(_async_url(get_settings().database_url), pool_pre_ping=True, pool_recycle=1800)
AsyncSessionFactory = async_sessionmaker(engine, expire_on_commit=False)


@asynccontextmanager
async def session_scope():
    async with AsyncSessionFactory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

- [ ] **Step 3: Add MySQL integration fixtures**

`tests/conftest.py` imports all current model modules, asserts `SELECT DATABASE()`
is exactly `eureka_theme_v2_test`, recreates only `Base.metadata` before the
integration session, and truncates rows between tests. Production schema
creation remains Alembic-only and is added in Task 6 after the foundation
models are complete.

Run: `docker compose -f docker-compose.theme-v2.yml up -d mysql`

Expected: only the Theme V2 MySQL service starts and becomes healthy.

- [ ] **Step 4: Add database readiness**

```python
from fastapi import HTTPException
from sqlalchemy import text
from app.db.session import AsyncSessionFactory


@app.get("/ready")
async def ready() -> dict[str, str]:
    try:
        async with AsyncSessionFactory() as session:
            await session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}
```

- [ ] **Step 5: Run the integration test against MySQL**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_database.py -q`

Expected: `1 passed` against database `eureka_theme_v2_test`.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/db theme_v2_service/app/main.py theme_v2_service/tests/conftest.py theme_v2_service/tests/integration/test_database.py
git commit -m "feat(theme-v2): add isolated mysql sessions"
```

---

### Task 3: Implement the self-contained Bearer authentication boundary

**Files:**

- Create: `theme_v2_service/app/auth/__init__.py`
- Create: `theme_v2_service/app/auth/models.py`
- Create: `theme_v2_service/app/auth/security.py`
- Create: `theme_v2_service/app/auth/dependencies.py`
- Create: `theme_v2_service/app/auth/api.py`
- Create: `theme_v2_service/tests/unit/test_auth.py`
- Create: `theme_v2_service/tests/contract/test_auth_api.py`
- Modify: `theme_v2_service/app/main.py`

**Interfaces:**

- Consumes: `Settings.jwt_secret` and `Authorization: Bearer <token>`.
- Produces: `UserAccount`, `create_token(user_id: str) -> str`, `decode_token(token: str) -> dict | None`, `get_current_user_id(request: Request) -> str`, and independent register/login/me endpoints.

- [ ] **Step 1: Write failing token and dependency tests**

```python
from app.auth.security import create_token, decode_token


def test_token_round_trip(monkeypatch):
    token = create_token("user-1", now=1_700_000_000, ttl_seconds=3600)
    assert decode_token(token, now=1_700_000_001)["sub"] == "user-1"


def test_tampered_token_is_rejected():
    token = create_token("user-1")
    assert decode_token(token + "x") is None
```

- [ ] **Step 2: Implement strict HS256 with the standard library**

Copy the stable encoding approach from `backend/core/security.py`, but make clock injection explicit:

```python
def create_token(user_id: str, *, now: int | None = None, ttl_seconds: int = 86400) -> str:
    issued_at = int(time.time()) if now is None else now
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"sub": user_id, "iat": issued_at, "exp": issued_at + ttl_seconds}
    signing_text = f"{_b64u(json.dumps(header, separators=(',', ':')).encode())}.{_b64u(json.dumps(payload, separators=(',', ':')).encode())}"
    signature = hmac.new(get_settings().jwt_secret.encode(), signing_text.encode(), hashlib.sha256).digest()
    return f"{signing_text}.{_b64u(signature)}"


def decode_token(token: str, *, now: int | None = None) -> dict | None:
    try:
        header_text, payload_text, signature_text = token.split(".")
        header = json.loads(_b64u_dec(header_text))
        if header != {"alg": "HS256", "typ": "JWT"}:
            return None
        signing_text = f"{header_text}.{payload_text}"
        expected = hmac.new(get_settings().jwt_secret.encode(), signing_text.encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64u_dec(signature_text)):
            return None
        payload = json.loads(_b64u_dec(payload_text))
        current = int(time.time()) if now is None else now
        if not payload.get("sub") or int(payload.get("exp", 0)) < current:
            return None
        return payload
    except (ValueError, TypeError, json.JSONDecodeError):
        return None
```

The module also defines `_b64u` and `_b64u_dec` exactly as the legacy stable implementation does; it does not import the legacy module.

- [ ] **Step 3: Implement the FastAPI dependency**

```python
from fastapi import HTTPException, Request
from app.auth.security import decode_token


def get_current_user_id(request: Request) -> str:
    value = request.headers.get("Authorization", "")
    if value.startswith("Bearer "):
        payload = decode_token(value[7:].strip())
        if payload and payload.get("sub"):
            return str(payload["sub"])
    raise HTTPException(status_code=401, detail="未登录或登录已过期")
```

- [ ] **Step 4: Add password hashing and the owned account table**

Copy the PBKDF2-HMAC-SHA256 format from `backend/core/security.py` into the V2
module without importing legacy code. `UserAccount` has `id`, unique normalized
`email`, `password_hash`, and `created_at`; it has no foreign key to a legacy
user table. Use 200,000 iterations, 16 random salt bytes, and constant-time hash
comparison.

- [ ] **Step 5: Add compatible email auth endpoints**

Register:

```text
POST /api/auth/register {email, password} -> {ok, token, user}
POST /api/auth/login    {email, password} -> {ok, token, user}
GET  /api/auth/me                         -> {ok, user}
```

Normalize email with trim/lowercase, require a basic valid address and minimum
six-character password, return `409` for duplicate register, `401` for invalid
credentials, and use the token subject as every domain `user_id`. These routes
let Theme V2 run without the legacy auth container; external Baizhi OAuth is
outside the four approved specs and is not required for this Phase 1 gate.

- [ ] **Step 6: Run auth tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_auth.py tests/contract/test_auth_api.py -q`

Expected: token, password, register, duplicate, login, me, expiry, tamper, and unauthorized cases PASS.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/auth theme_v2_service/app/main.py theme_v2_service/tests/unit/test_auth.py theme_v2_service/tests/contract/test_auth_api.py
git commit -m "feat(theme-v2): add independent auth boundary"
```

---

### Task 4: Add the minimum UserSkill, Asset, and Event domain foundation

**Files:**

- Create: `theme_v2_service/app/db/models.py`
- Create: `theme_v2_service/app/domains/assets/schemas.py`
- Create: `theme_v2_service/app/domains/assets/service.py`
- Create: `theme_v2_service/app/domains/assets/api.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/tests/integration/test_asset_service.py`
- Create: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**

- Consumes: authenticated `user_id` and injected `AsyncSession`.
- Produces: `UserSkill`, `Asset`, `Event`, `create_asset(session, user_id, command)`, and ownership-safe CRUD needed by Trigger, Report, and Today.

- [ ] **Step 1: Write the failing ownership and persistence test**

```python
async def test_asset_is_scoped_to_owner(session):
    skill = await create_user_skill(session, "user-1", UserSkillCreate(machine_name="notes", display_name="笔记", schema={}))
    asset = await create_asset(session, "user-1", AssetCreate(user_skill_id=skill.id, payload={"content": "x"}))
    await session.commit()
    assert await get_asset(session, "user-1", asset.id) is not None
    assert await get_asset(session, "user-2", asset.id) is None
```

- [ ] **Step 2: Add ORM models with explicit physical types**

`UserSkill` fields: `id`, `user_id`, `machine_name`, `display_name`, `description`, `domain`, `schema_json`, `created_at`, `updated_at`; unique `(user_id, machine_name)`.

`Asset` fields: `id`, `user_id`, `user_skill_id`, `payload_json`, `effective_at`, `created_at`, `updated_at`; indexes `(user_id, created_at)` and `(user_id, user_skill_id, effective_at)`.

`Event` fields: `id`, `user_id`, `title`, `description`, `location`, `start_at`, `end_at`, `all_day`, `status`, `created_at`, `updated_at`; indexes `(user_id, start_at)` and `(user_id, created_at)`.

Every relationship is optional at ORM level unless the database foreign key is needed for ownership-safe joins. No model references legacy table names.

- [ ] **Step 3: Implement the transaction-neutral service interface**

```python
async def create_asset(session: AsyncSession, user_id: str, command: AssetCreate) -> Asset:
    skill = await session.scalar(select(UserSkill).where(UserSkill.id == command.user_skill_id, UserSkill.user_id == user_id))
    if skill is None:
        raise AssetNotFound()
    asset = Asset(user_id=user_id, user_skill_id=skill.id, payload_json=command.payload, effective_at=command.effective_at)
    session.add(asset)
    await session.flush()
    return asset
```

The function must not commit; Trigger Task 2 will extend this same transaction after `flush()`.

- [ ] **Step 4: Expose only the minimal authenticated API**

Create:

```text
POST /api/user-skills
GET  /api/user-skills
GET  /api/user-skills/{skill_id}
POST /api/assets
GET  /api/assets
GET  /api/assets/{asset_id}
PATCH /api/assets/{asset_id}
DELETE /api/assets/{asset_id}
POST /api/events
GET  /api/events
GET  /api/events/{event_id}
PATCH /api/events/{event_id}
DELETE /api/events/{event_id}
```

Asset list supports owned `user_skill_id`, `created_from`, `created_to`, and
bounded `limit`; Event list supports owned start/created bounds and bounded
limit. Asset update changes payload/effective time but never calls the
Asset-created Trigger hook. Event update supports title, description, location,
start/end, all-day, and scheduled/cancelled status so pre-event maintenance can
observe reschedule/cancel. Deletes are physical in Phase 1. All object misses,
including cross-user IDs, return `404`. Register the router in `app/main.py`.

- [ ] **Step 5: Run database and API tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_asset_service.py tests/contract/test_asset_api.py -q`

Expected: ownership, list bounds, update-without-create-hook, Event reschedule,
physical delete, and CRUD tests PASS against MySQL.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/db/models.py theme_v2_service/app/domains/assets theme_v2_service/app/main.py theme_v2_service/tests/integration/test_asset_service.py theme_v2_service/tests/contract/test_asset_api.py
git commit -m "feat(theme-v2): add core asset event records"
```

---

### Task 5: Implement the durable WorkflowJob queue and Worker loop

**Files:**

- Create: `theme_v2_service/app/jobs/__init__.py`
- Create: `theme_v2_service/app/jobs/models.py`
- Create: `theme_v2_service/app/jobs/queue.py`
- Create: `theme_v2_service/app/jobs/registry.py`
- Create: `theme_v2_service/app/jobs/runner.py`
- Create: `theme_v2_service/app/worker.py`
- Modify: `theme_v2_service/app/db/models.py`
- Create: `theme_v2_service/tests/integration/test_job_queue.py`
- Create: `theme_v2_service/tests/unit/test_job_registry.py`

**Interfaces:**

- Consumes: committed `WorkflowJob` rows.
- Produces: `enqueue_job`, `claim_next_job`, `renew_lease`, `complete_job`, `fail_job`, and `JobHandlerRegistry`.

- [ ] **Step 1: Write failing concurrency and lease tests**

```python
async def test_two_workers_cannot_claim_the_same_job(session_factory):
    job_id = await seed_job(session_factory, job_type="probe", dedupe_key="probe:1")
    first, second = await asyncio.gather(
        claim_with_new_session(session_factory, "worker-a"),
        claim_with_new_session(session_factory, "worker-b"),
    )
    claimed = [job.id for job in (first, second) if job is not None]
    assert claimed == [job_id]


async def test_expired_lease_can_be_reclaimed(session_factory, clock):
    job = await seed_running_job(session_factory, lease_owner="dead", lease_expires_at=clock.now_minus(seconds=1))
    reclaimed = await claim_with_new_session(session_factory, "worker-b")
    assert reclaimed.id == job.id
    assert reclaimed.lease_owner == "worker-b"
```

- [ ] **Step 2: Add `WorkflowJob`**

Use the runtime design fields plus a unique nullable `input_dedupe_key`. The claim index is `(status, available_at, lease_expires_at)`. Status strings are `queued`, `running`, `succeeded`, `failed`, and `cancelled`.

- [ ] **Step 3: Implement short-transaction claim semantics**

```python
async def claim_next_job(session: AsyncSession, *, owner: str, now: datetime, lease_seconds: int) -> WorkflowJob | None:
    candidate = await session.scalar(
        select(WorkflowJob)
        .where(
            or_(
                and_(WorkflowJob.status == "queued", WorkflowJob.available_at <= now),
                and_(WorkflowJob.status == "running", WorkflowJob.lease_expires_at < now),
            )
        )
        .order_by(WorkflowJob.available_at, WorkflowJob.created_at)
        .with_for_update(skip_locked=True)
        .limit(1)
    )
    if candidate is None:
        return None
    candidate.status = "running"
    candidate.attempt += 1
    candidate.lease_owner = owner
    candidate.lease_expires_at = now + timedelta(seconds=lease_seconds)
    candidate.started_at = candidate.started_at or now
    await session.flush()
    return candidate
```

The caller commits immediately and runs the handler outside this transaction.

- [ ] **Step 4: Implement guarded completion and retry**

`complete_job` and `fail_job` must update only when `id`, `status == running`, and `lease_owner` all match. Retryable failure sets `queued`, clears lease fields, and computes bounded exponential backoff with jitter; exhausted or permanent failure sets `failed`.

- [ ] **Step 5: Implement the handler registry and polling loop**

```python
JobHandler = Callable[[WorkflowJob], Awaitable[None]]


class JobHandlerRegistry:
    def __init__(self): self._handlers: dict[str, JobHandler] = {}
    def register(self, job_type: str, handler: JobHandler) -> None: self._handlers[job_type] = handler
    def resolve(self, job_type: str) -> JobHandler: return self._handlers[job_type]
```

`run_worker()` creates a stable owner ID, claims one job, dispatches it, heartbeats long jobs, and sleeps `worker_poll_seconds` only when no job was found. SIGTERM stops claiming new work and lets the active handler finish within the Compose stop grace period.

- [ ] **Step 6: Run queue tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_job_registry.py tests/integration/test_job_queue.py -q`

Expected: registry, dedupe, concurrent claim, guarded completion, retry, and lease recovery tests PASS.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/jobs theme_v2_service/app/worker.py theme_v2_service/app/db/models.py theme_v2_service/tests/unit/test_job_registry.py theme_v2_service/tests/integration/test_job_queue.py
git commit -m "feat(theme-v2): add durable workflow job queue"
```

---

### Task 6: Add the isolated Docker Compose lifecycle

**Files:**

- Modify: `theme_v2_service/Dockerfile`
- Modify: `docker-compose.theme-v2.yml`
- Create: `.env.theme-v2.example`
- Create: `theme_v2_service/alembic.ini`
- Create: `theme_v2_service/migrations/env.py`
- Create: `theme_v2_service/migrations/versions/0001_foundation.py`
- Create: `theme_v2_service/tests/integration/test_migrations.py`
- Create: `theme_v2_service/tests/integration/test_runtime_isolation.py`
- Create: `theme_v2_service/scripts/smoke.sh`

**Interfaces:**

- Consumes: the app, migrations, and worker entry points from Tasks 1–5.
- Produces: independently startable `mysql`, `migrate`, `api`, and `worker` services.

- [ ] **Step 1: Create the production migration from complete foundation metadata**

Configure Alembic to import UserAccount, UserSkill, Asset, Event, and WorkflowJob metadata.
Create revision `0001_foundation` with those five tables, every index and unique
constraint from Tasks 4–5, `mysql.DATETIME(fsp=6)`, MySQL JSON, `String(36)`,
and `mysql_charset="utf8mb4"`. Apply it to a fresh disposable Theme V2
database, downgrade to base, and upgrade to head again before continuing.

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test alembic downgrade base
docker compose -f docker-compose.theme-v2.yml run --rm test alembic upgrade head
docker compose -f docker-compose.theme-v2.yml run --rm test alembic downgrade base
docker compose -f docker-compose.theme-v2.yml run --rm test alembic upgrade head
```

Expected: both upgrade cycles end at `0001_foundation` without editing the
development or legacy database.

- [ ] **Step 2: Write a runtime isolation test**

```python
async def test_runtime_uses_theme_v2_database(client, session):
    health = await client.get("/health")
    assert health.json()["service"] == "theme-v2"
    assert (await session.execute(text("SELECT DATABASE()"))).scalar_one() == "eureka_theme_v2"
```

- [ ] **Step 3: Finalize the shared image**

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY . .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 4: Finalize Compose with project-scoped resources**

`docker-compose.theme-v2.yml` must set `name: eureka-theme-v2` and define:

```yaml
services:
  mysql:
    image: mysql:8.0
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    environment:
      MYSQL_DATABASE: eureka_theme_v2
      MYSQL_USER: theme_v2
      MYSQL_PASSWORD: ${THEME_V2_DB_PASSWORD:-theme_v2}
      MYSQL_ROOT_PASSWORD: ${THEME_V2_DB_ROOT_PASSWORD:-theme_v2_root}
    ports: ["127.0.0.1:3307:3306"]
    volumes:
      - mysql_data:/var/lib/mysql
      - ./theme_v2_service/docker/mysql-init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u theme_v2 -p$$MYSQL_PASSWORD --silent"]
      interval: 5s
      timeout: 5s
      retries: 20
  migrate:
    build: ./theme_v2_service
    command: alembic upgrade head
    depends_on:
      mysql: {condition: service_healthy}
    environment: &theme_v2_env
      DATABASE_URL: mysql://theme_v2:${THEME_V2_DB_PASSWORD:-theme_v2}@mysql:3306/eureka_theme_v2
      JWT_SECRET: ${THEME_V2_JWT_SECRET:-dev-insecure-change-me}
    volumes:
      - ./theme_v2_service:/app
      - media_data:/data/media
  api:
    build: ./theme_v2_service
    ports: ["8100:8000"]
    environment: *theme_v2_env
    depends_on:
      migrate: {condition: service_completed_successfully}
    volumes:
      - ./theme_v2_service:/app
      - media_data:/data/media
  worker:
    build: ./theme_v2_service
    command: python -m app.worker
    environment: *theme_v2_env
    depends_on:
      migrate: {condition: service_completed_successfully}
    volumes:
      - ./theme_v2_service:/app
      - media_data:/data/media
  test:
    build: ./theme_v2_service
    profiles: ["test"]
    environment:
      DATABASE_URL: mysql://theme_v2:${THEME_V2_DB_PASSWORD:-theme_v2}@mysql:3306/eureka_theme_v2_test
      JWT_SECRET: test-only-secret
      ENV: test
    depends_on:
      mysql: {condition: service_healthy}
    volumes:
      - ./theme_v2_service:/app
      - media_data:/data/media
volumes:
  mysql_data:
  media_data:
```

- [ ] **Step 5: Add the smoke script**

`scripts/smoke.sh` must use `set -euo pipefail`, call `curl -fsS http://localhost:8100/health`, call `/ready`, and run the migration and runtime isolation tests inside the API container. It must not invoke any legacy Compose command.

- [ ] **Step 6: Build and run the independent stack**

Run: `docker compose -f docker-compose.theme-v2.yml up -d --build`

Expected: `mysql` healthy, `migrate` exited 0, `api` healthy on 8100, and `worker` running.

- [ ] **Step 7: Run the full foundation gate**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit tests/integration/test_database.py tests/integration/test_migrations.py tests/integration/test_asset_service.py tests/integration/test_job_queue.py tests/integration/test_runtime_isolation.py -q`

Expected: all selected tests PASS.

- [ ] **Step 8: Verify the legacy resources are untouched**

Run: `docker compose -f docker-compose.theme-v2.yml config --volumes`

Expected: only `mysql_data` and `media_data` under project `eureka-theme-v2`; no `mysqldata` external volume and no legacy network.

- [ ] **Step 9: Commit**

```bash
git add theme_v2_service/Dockerfile theme_v2_service/scripts/smoke.sh theme_v2_service/tests/integration/test_runtime_isolation.py theme_v2_service/alembic.ini theme_v2_service/migrations docker-compose.theme-v2.yml .env.theme-v2.example
git commit -m "build(theme-v2): add isolated docker runtime"
```

---

## Completion Gate

Run:

```bash
docker compose -f docker-compose.theme-v2.yml up -d --build
docker compose -f docker-compose.theme-v2.yml run --rm api alembic current
docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit tests/integration -q
curl -fsS http://localhost:8100/health
curl -fsS http://localhost:8100/ready
```

Expected:

- Alembic reports `0001_foundation (head)`.
- All foundation tests pass against MySQL 8.
- API and Worker use the new database and shared image.
- No command starts, stops, mounts, or queries the legacy backend or its MySQL volume.
- The next plan may rely on `AsyncSessionFactory`, `get_current_user_id`, UserSkill/Asset/Event, and WorkflowJob queue interfaces.
