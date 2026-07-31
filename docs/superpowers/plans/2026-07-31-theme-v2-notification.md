# Theme V2 Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the Theme V2 notification history, read/delete APIs, MySQL Transactional Outbox, and authenticated SSE delivery without Redis or cross-process in-memory assumptions.

**Architecture:** Domain producers write `Notification` and `OutboxEvent` through one injected SQLAlchemy session. The single API process polls committed Outbox rows and fans them to per-user in-memory SSE queues; the notification table remains the recovery truth when frames are duplicated or dropped.

**Tech Stack:** FastAPI, SQLAlchemy 2 async, MySQL 8, asyncio, SSE, pytest, the Theme V2 foundation runtime.

## Global Constraints

- Requires completion of `docs/superpowers/plans/2026-07-31-theme-v2-service-foundation.md`.
- The canonical behavior is `spec/design/theme-v2-notification.md` plus the runtime design.
- Notification fields remain `id`, `user_id`, `type`, `title`, `body`, `link`, `read`, `created_at`; do not add a generic action/source/workflow model.
- Notification rows are immutable except `read`; explicit delete physically removes the row.
- Retention is 14 days; list default is 30 and maximum is 100.
- Domain producers and Worker never call the API container.
- Outbox delivery is at-least-once; clients deduplicate with Notification ID and recover by listing history.
- Phase 1 has one API instance; no Redis, Kafka, PostgreSQL `LISTEN/NOTIFY`, or report-progress SSE.
- Every private endpoint and SSE connection derives `user_id` from Bearer auth; cross-user IDs return `404` or an idempotent success without revealing existence.

---

## File Structure

### Create

- `theme_v2_service/app/domains/notifications/models.py` — Notification and OutboxEvent ORM rows.
- `theme_v2_service/app/domains/notifications/schemas.py` — public payloads and internal create command.
- `theme_v2_service/app/domains/notifications/service.py` — create, list, read, delete, prune.
- `theme_v2_service/app/domains/notifications/subscribers.py` — bounded per-user queues.
- `theme_v2_service/app/domains/notifications/outbox.py` — polling dispatcher.
- `theme_v2_service/app/domains/notifications/sse.py` — SSE encoding and heartbeat wrapper.
- `theme_v2_service/app/domains/notifications/api.py` — REST and stream routes.
- `theme_v2_service/migrations/versions/0002_notifications_outbox.py`
- `theme_v2_service/tests/unit/test_notification_schemas.py`
- `theme_v2_service/tests/unit/test_subscribers.py`
- `theme_v2_service/tests/integration/test_notification_service.py`
- `theme_v2_service/tests/integration/test_notification_outbox.py`
- `theme_v2_service/tests/contract/test_notification_api.py`
- `theme_v2_service/tests/contract/test_notification_sse.py`

### Modify

- `theme_v2_service/app/main.py` — register routes and dispatcher lifecycle.
- `theme_v2_service/app/jobs/registry.py` — register notification maintenance handler.
- `theme_v2_service/app/worker.py` — enqueue/run the daily retention maintenance tick.

---

### Task 1: Add Notification and Outbox persistence

**Files:**

- Create: `theme_v2_service/app/domains/notifications/models.py`
- Create: `theme_v2_service/app/domains/notifications/schemas.py`
- Create: `theme_v2_service/migrations/versions/0002_notifications_outbox.py`
- Create: `theme_v2_service/tests/integration/test_notification_service.py`

**Interfaces:**

- Consumes: foundation `Base`, `AsyncSession`, `new_uuid`, and `utc_now`.
- Produces: `Notification`, `OutboxEvent`, `NotificationCreate`, and `NotificationPayload`.

- [ ] **Step 1: Write the failing persistence test**

```python
async def test_notification_and_outbox_commit_together(session):
    notification = await create_notification(
        session,
        NotificationCreate(user_id="user-1", type="report_done", title="报告已生成", link="report:r1"),
    )
    await session.commit()
    events = (await session.scalars(select(OutboxEvent))).all()
    assert len(events) == 1
    assert events[0].aggregate_id == notification.id
    assert events[0].event_type == "notification.created"
```

- [ ] **Step 2: Define the ORM rows**

`Notification` uses `String(36)` ID, `String(32)` type, `String(255)` title/link, nullable text body, boolean `read` default false, and UTC `DATETIME(6)` `created_at`. Add indexes `(user_id, created_at)` and `(user_id, read, created_at)`.

`OutboxEvent` fields are `id`, `event_type`, `aggregate_type`, `aggregate_id`, `user_id`, `payload_json`, `created_at`, `available_at`, `attempt`, `published_at`, and `last_error`; add index `(published_at, available_at, id)`.

- [ ] **Step 3: Define strict schemas**

```python
from pydantic import BaseModel, ConfigDict, Field


class NotificationCreate(BaseModel):
    user_id: str
    type: str = Field(min_length=1, max_length=32)
    title: str = Field(min_length=1)
    body: str = ""
    link: str | None = Field(default=None, max_length=255)


class NotificationPayload(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    type: str
    title: str
    body: str
    link: str | None
    read: bool
    created_at: datetime
```

The service truncates title to 255 characters before insert, matching the spec.

- [ ] **Step 4: Generate and run migration `0002_notifications_outbox`**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm api alembic upgrade head`

Expected: Alembic advances from `0001_foundation` to `0002_notifications_outbox` and both tables use `utf8mb4`.

- [ ] **Step 5: Run the persistence test**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_notification_service.py -q`

Expected: atomic insert and rollback cases PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/notifications/models.py theme_v2_service/app/domains/notifications/schemas.py theme_v2_service/migrations/versions/0002_notifications_outbox.py theme_v2_service/tests/integration/test_notification_service.py
git commit -m "feat(theme-v2): add notification outbox schema"
```

---

### Task 2: Implement transaction-neutral notification services

**Files:**

- Create: `theme_v2_service/app/domains/notifications/service.py`
- Modify: `theme_v2_service/tests/integration/test_notification_service.py`
- Create: `theme_v2_service/tests/unit/test_notification_schemas.py`

**Interfaces:**

- Consumes: `AsyncSession` owned by the caller.
- Produces: `create_notification`, `list_notifications`, `mark_read`, `mark_all_read`, `delete_notification`, and `prune_notifications`.

- [ ] **Step 1: Add failing behavior tests**

Add five tests named `test_list_is_newest_first_and_reports_unread`,
`test_mark_read_is_owner_scoped_and_idempotent`,
`test_delete_is_owner_scoped_and_idempotent`,
`test_prune_deletes_only_rows_older_than_fourteen_days`, and
`test_rollback_removes_notification_and_outbox`. Seed rows for `user-1` and
`user-2`; assert descending `created_at`, the exact unread count, unchanged
cross-user rows after both repeated mutations, deletion only before
`now - 14 days`, and zero Notification/Outbox rows after an explicit rollback.

- [ ] **Step 2: Implement `create_notification`**

```python
async def create_notification(session: AsyncSession, command: NotificationCreate) -> Notification:
    notification = Notification(
        user_id=command.user_id,
        type=command.type,
        title=command.title[:255],
        body=command.body,
        link=command.link,
    )
    session.add(notification)
    await session.flush()
    session.add(OutboxEvent(
        event_type="notification.created",
        aggregate_type="notification",
        aggregate_id=notification.id,
        user_id=notification.user_id,
        payload_json={"notification_id": notification.id},
    ))
    await session.flush()
    return notification
```

This function never opens a session, commits, catches database errors, or publishes SSE.

- [ ] **Step 3: Implement list and ownership-safe mutations**

`list_notifications(session, user_id, limit)` clamps `limit` to 1–100, sorts by `created_at DESC, id DESC`, and separately counts unread rows. Read-all updates only unread rows for that user. Single read and delete treat missing/cross-user IDs as idempotent no-op.

- [ ] **Step 4: Implement retention**

```python
async def prune_notifications(session: AsyncSession, *, now: datetime) -> int:
    cutoff = now - timedelta(days=14)
    result = await session.execute(delete(Notification).where(Notification.created_at < cutoff))
    return int(result.rowcount or 0)
```

Pruning is global and run by Worker; it does not run inside normal notification creation.

- [ ] **Step 5: Run service tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_notification_schemas.py tests/integration/test_notification_service.py -q`

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/notifications/service.py theme_v2_service/tests/unit/test_notification_schemas.py theme_v2_service/tests/integration/test_notification_service.py
git commit -m "feat(theme-v2): add notification services"
```

---

### Task 3: Add authenticated Notification REST APIs

**Files:**

- Create: `theme_v2_service/app/domains/notifications/api.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/tests/contract/test_notification_api.py`

**Interfaces:**

- Consumes: notification services and `get_current_user_id`.
- Produces: list, read, read-all, and delete endpoints under `/api/notifications`.

- [ ] **Step 1: Write failing contract tests**

```python
async def test_list_requires_auth_and_returns_unread(client, token, seeded_notifications):
    assert (await client.get("/api/notifications")).status_code == 401
    response = await client.get("/api/notifications?limit=30", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["unread"] == 1
    assert len(response.json()["notifications"]) == 2


async def test_cross_user_read_does_not_reveal_notification(client, token, other_notification):
    response = await client.post(f"/api/notifications/{other_notification.id}/read", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
```

- [ ] **Step 2: Implement endpoints with one session boundary each**

```text
GET    /api/notifications?limit=30
POST   /api/notifications/{notification_id}/read
POST   /api/notifications/read-all
DELETE /api/notifications/{notification_id}
```

Each handler opens `AsyncSessionFactory`, calls one service, commits once for mutations, and serializes `created_at` with a UTC suffix.

- [ ] **Step 3: Register the router**

```python
from app.domains.notifications.api import router as notification_router
app.include_router(notification_router, prefix="/api", tags=["notifications"])
```

- [ ] **Step 4: Run contract tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/contract/test_notification_api.py -q`

Expected: auth, limit, ordering, unread, read/read-all, delete, and ownership cases PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/notifications/api.py theme_v2_service/app/main.py theme_v2_service/tests/contract/test_notification_api.py
git commit -m "feat(theme-v2): add notification api"
```

---

### Task 4: Implement bounded subscribers and SSE encoding

**Files:**

- Create: `theme_v2_service/app/domains/notifications/subscribers.py`
- Create: `theme_v2_service/app/domains/notifications/sse.py`
- Create: `theme_v2_service/tests/unit/test_subscribers.py`
- Create: `theme_v2_service/tests/contract/test_notification_sse.py`

**Interfaces:**

- Consumes: serialized `NotificationPayload` dictionaries.
- Produces: `SubscriberRegistry`, `sse_event`, `sse_comment`, and `with_heartbeats`.

- [ ] **Step 1: Write failing queue tests**

```python
async def test_registry_is_user_scoped():
    registry = SubscriberRegistry(queue_size=1)
    first = registry.subscribe("user-1")
    second = registry.subscribe("user-2")
    assert registry.publish("user-1", {"id": "n1"}) == 0
    assert await first.get() == {"id": "n1"}
    assert second.empty()


def test_full_queue_drops_frame_without_raising():
    registry = SubscriberRegistry(queue_size=1)
    queue = registry.subscribe("user-1")
    registry.publish("user-1", {"id": "n1"})
    assert registry.publish("user-1", {"id": "n2"}) == 1
```

- [ ] **Step 2: Implement the registry**

```python
class SubscriberRegistry:
    def __init__(self, queue_size: int = 100):
        self._queue_size = queue_size
        self._subscribers: dict[str, set[asyncio.Queue[dict]]] = {}

    def subscribe(self, user_id: str) -> asyncio.Queue[dict]:
        queue = asyncio.Queue(maxsize=self._queue_size)
        self._subscribers.setdefault(user_id, set()).add(queue)
        return queue

    def unsubscribe(self, user_id: str, queue: asyncio.Queue[dict]) -> None:
        subscribers = self._subscribers.get(user_id)
        if subscribers is None:
            return
        subscribers.discard(queue)
        if not subscribers:
            self._subscribers.pop(user_id, None)

    def publish(self, user_id: str, payload: dict) -> int:
        dropped = 0
        for queue in tuple(self._subscribers.get(user_id, ())):
            try:
                queue.put_nowait(payload)
            except asyncio.QueueFull:
                dropped += 1
        return dropped
```

`publish` calls `put_nowait`, counts full queues, and never blocks the dispatcher.

- [ ] **Step 3: Implement safe SSE helpers**

`sse_event("notification", payload)` returns UTF-8 text with one `event:` line and JSON serialized on `data:`. `with_heartbeats` yields `: heartbeat\n\n` every 15 seconds while preserving cancellation and closing the subscriber in `finally`.

- [ ] **Step 4: Run unit tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_subscribers.py -q`

Expected: user isolation, unsubscribe, full queue drop, and encoding tests PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/notifications/subscribers.py theme_v2_service/app/domains/notifications/sse.py theme_v2_service/tests/unit/test_subscribers.py
git commit -m "feat(theme-v2): add notification sse registry"
```

---

### Task 5: Dispatch committed Outbox rows to SSE

**Files:**

- Create: `theme_v2_service/app/domains/notifications/outbox.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/tests/integration/test_notification_outbox.py`
- Modify: `theme_v2_service/tests/contract/test_notification_sse.py`

**Interfaces:**

- Consumes: committed `OutboxEvent(notification.created)` rows and `SubscriberRegistry`.
- Produces: `dispatch_one(session_factory, registry, now) -> bool` and app lifecycle polling.

- [ ] **Step 1: Write failure-window tests**

Add four async tests with those exact names. The first holds an insert open in
one session and confirms a second session cannot select it. The second commits,
dispatches once, and asserts only the matching user's queue receives the
serialized row. The third deletes the Notification before dispatch and asserts
the Outbox row is marked published with an empty queue. The fourth injects a
failure after `registry.publish` but before commit, runs dispatch again, and
asserts two frames carry the same Notification ID.

- [ ] **Step 2: Implement one-row dispatch**

```python
async def dispatch_one(session_factory, registry: SubscriberRegistry, *, now: datetime) -> bool:
    async with session_factory() as session:
        event = await session.scalar(
            select(OutboxEvent)
            .where(OutboxEvent.published_at.is_(None), OutboxEvent.available_at <= now)
            .order_by(OutboxEvent.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if event is None:
            return False
        notification = await session.get(Notification, event.aggregate_id)
        if notification is not None:
            registry.publish(notification.user_id, NotificationPayload.model_validate(notification).model_dump(mode="json"))
        event.published_at = now
        event.last_error = None
        await session.commit()
        return True
```

On an exception, rollback, increment `attempt`, store a sanitized error, set a bounded `available_at`, commit, and return `True` so the loop remains alive.

- [ ] **Step 3: Add API lifecycle ownership**

Create exactly one `SubscriberRegistry` and one dispatcher task in FastAPI lifespan. Shutdown cancels and awaits the task. The Worker must not start this dispatcher.

- [ ] **Step 4: Add the SSE route**

```text
GET /api/notifications/stream
```

The route authenticates before returning `StreamingResponse`, immediately emits `: connected`, emits `notification` events, sets `Cache-Control: no-cache` and `X-Accel-Buffering: no`, and unregisters the queue on disconnect.

- [ ] **Step 5: Run outbox and SSE tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_notification_outbox.py tests/contract/test_notification_sse.py -q`

Expected: commit visibility, user routing, duplicate semantics, dropped-frame recovery, auth, and heartbeat tests PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/notifications/outbox.py theme_v2_service/app/domains/notifications/api.py theme_v2_service/app/main.py theme_v2_service/tests/integration/test_notification_outbox.py theme_v2_service/tests/contract/test_notification_sse.py
git commit -m "feat(theme-v2): dispatch notification outbox over sse"
```

---

### Task 6: Add retention maintenance and end-to-end recovery coverage

**Files:**

- Create: `theme_v2_service/app/domains/notifications/maintenance.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Modify: `theme_v2_service/app/worker.py`
- Create: `theme_v2_service/tests/integration/test_notification_maintenance.py`
- Create: `theme_v2_service/tests/e2e/test_notification_flow.py`

**Interfaces:**

- Consumes: WorkflowJob registry and notification service.
- Produces: idempotent `notification_prune` maintenance execution and a complete Worker-to-SSE flow.

- [ ] **Step 1: Write failing maintenance and end-to-end tests**

The end-to-end test must:

1. open an authenticated SSE connection;
2. create a Notification + Outbox in a Worker-owned session;
3. observe the same Notification ID in SSE;
4. list history and observe the same row;
5. reconnect, list again, and recover even when no SSE frame is replayed.

- [ ] **Step 2: Register the prune handler**

```python
async def handle_notification_prune(job: WorkflowJob) -> None:
    async with AsyncSessionFactory() as session:
        await prune_notifications(session, now=utc_now())
        await session.commit()
```

Use dedupe key `maintenance:notification-prune:<UTC date>`. The Worker scheduler inserts at most one row per UTC date; repeated startup is safe because of the unique key.

- [ ] **Step 3: Run the complete Notification gate**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_notification_schemas.py tests/unit/test_subscribers.py tests/integration/test_notification_service.py tests/integration/test_notification_outbox.py tests/integration/test_notification_maintenance.py tests/contract/test_notification_api.py tests/contract/test_notification_sse.py tests/e2e/test_notification_flow.py -q`

Expected: all Notification tests PASS.

- [ ] **Step 4: Commit**

```bash
git add theme_v2_service/app/domains/notifications/maintenance.py theme_v2_service/app/jobs/registry.py theme_v2_service/app/worker.py theme_v2_service/tests/integration/test_notification_maintenance.py theme_v2_service/tests/e2e/test_notification_flow.py
git commit -m "feat(theme-v2): complete notification recovery flow"
```

---

## Completion Gate

- A Worker transaction can create a Notification without calling the API process.
- The API dispatcher publishes the committed row to the correct authenticated SSE subscribers.
- Duplicate or dropped real-time frames do not lose notification history.
- Read, read-all, delete, retention, list limit, ownership, and 14-day recovery semantics match the spec.
- Outbox age and failure count are available to the later observability slice.
- No Redis, Kafka, PostgreSQL driver, or legacy notification module is imported.
