# Theme V2 Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement deterministic proactive-summary and pre-event report triggers with durable Trackers, Executions, notification revisions, dismiss/consume semantics, concurrency protection, and Worker compensation.

**Architecture:** Asset creation evaluates the lightweight accumulation rule inside the same MySQL transaction. Time-driven event rules and compensation scans run in the existing Worker, while unique keys, relation-table counting, row locks, and Notification Outbox writes make repeated evaluation safe.

**Tech Stack:** FastAPI, SQLAlchemy 2 async, MySQL 8 row locks, Python `zoneinfo`, WorkflowJob/Worker foundation, Notification Outbox, pytest.

## Global Constraints

- Requires the Service Foundation and Notification plans to be complete.
- Product truth is `spec/design/theme-v2-trigger.md`; runtime truth is the Theme V2 isolated service design.
- Phase 1 implements only `proactive_summary` and `pre_event_report`.
- Trigger definitions are code registrations, not database rows.
- Trigger evaluation never invokes an Agent, Web Search, image model, Renderer, or external service.
- Proactive threshold is both `cycle_age >= 7 days` and `new_asset_count >= 7`.
- After the first notification, an unconsumed execution may notify only on the first new Asset of a later local calendar day.
- Dismiss suppresses notifications for 7 days but does not expire the execution or stop accumulation.
- Consuming a proactive execution starts a new cycle and applies a 7-day proactive suppression from consumption time.
- A user-initiated Report never reads or mutates Trigger state.
- Every execution stores references, not Asset content snapshots.
- Cross-user IDs return `404`; expired execution consumption returns `410`.

---

## File Structure

### Create

- `theme_v2_service/app/domains/triggers/models.py`
- `theme_v2_service/app/domains/triggers/definitions.py`
- `theme_v2_service/app/domains/triggers/proactive_summary.py`
- `theme_v2_service/app/domains/triggers/pre_event_report.py`
- `theme_v2_service/app/domains/triggers/notifications.py`
- `theme_v2_service/app/domains/triggers/service.py`
- `theme_v2_service/app/domains/triggers/api.py`
- `theme_v2_service/app/domains/triggers/maintenance.py`
- `theme_v2_service/migrations/versions/0003_triggers.py`
- `theme_v2_service/tests/unit/test_trigger_definitions.py`
- `theme_v2_service/tests/unit/test_proactive_summary_rules.py`
- `theme_v2_service/tests/unit/test_pre_event_rules.py`
- `theme_v2_service/tests/integration/test_proactive_summary.py`
- `theme_v2_service/tests/integration/test_trigger_concurrency.py`
- `theme_v2_service/tests/integration/test_pre_event_trigger.py`
- `theme_v2_service/tests/integration/test_trigger_compensation.py`
- `theme_v2_service/tests/contract/test_trigger_dismiss_api.py`

### Modify

- `theme_v2_service/app/domains/assets/service.py` — call proactive evaluator after Asset flush.
- `theme_v2_service/app/main.py` — register Dismiss API.
- `theme_v2_service/app/worker.py` — run pre-event and compensation ticks.

---

### Task 1: Add Trigger persistence and code definitions

**Files:**

- Create: `theme_v2_service/app/domains/triggers/models.py`
- Create: `theme_v2_service/app/domains/triggers/definitions.py`
- Create: `theme_v2_service/migrations/versions/0003_triggers.py`
- Create: `theme_v2_service/tests/unit/test_trigger_definitions.py`
- Create: `theme_v2_service/tests/integration/test_trigger_concurrency.py`

**Interfaces:**

- Consumes: foundation `Base`, UserSkill, Asset, Event.
- Produces: `TriggerTracker`, `TriggerCountedAsset`, `TriggerExecution`, and `TRIGGER_DEFINITIONS`.

- [ ] **Step 1: Write failing schema and definition tests**

```python
def test_phase_one_definitions_are_closed():
    assert set(TRIGGER_DEFINITIONS) == {"proactive_summary", "pre_event_report"}
    assert TRIGGER_DEFINITIONS["proactive_summary"].workflow_type == "report_generation"
    assert TRIGGER_DEFINITIONS["proactive_summary"].minimum_days == 7
    assert TRIGGER_DEFINITIONS["proactive_summary"].minimum_assets == 7
```

The integration test concurrently inserts the same `(tracker_id, asset_id)` twice and expects exactly one `TriggerCountedAsset` row.

- [ ] **Step 2: Add ORM models and constraints**

`TriggerTracker` fields follow the spec. Add unique `(user_id, trigger_type, scope_type, scope_id)` and indexes for active execution and dismissal scans.

`TriggerCountedAsset` fields are `id`, `tracker_id`, `asset_id`, `counted_at`; unique `(tracker_id, asset_id)`. This table is the count truth.

`TriggerExecution` fields follow the spec. Add unique `dedupe_key`, index `(user_id, status, created_at)`, and index `(tracker_id, status)`. Store `payload_json` as MySQL JSON and `revision` as a positive integer.

- [ ] **Step 3: Add immutable code definitions**

```python
@dataclass(frozen=True)
class TriggerDefinition:
    trigger_type: str
    signal_type: str
    workflow_type: str
    minimum_days: int | None = None
    minimum_assets: int | None = None


TRIGGER_DEFINITIONS = {
    "proactive_summary": TriggerDefinition("proactive_summary", "asset_created", "report_generation", 7, 7),
    "pre_event_report": TriggerDefinition("pre_event_report", "time", "report_generation"),
}
```

- [ ] **Step 4: Apply migration and run tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm api alembic upgrade head`

Expected: current revision becomes `0003_triggers`.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_trigger_definitions.py tests/integration/test_trigger_concurrency.py -q`

Expected: constraints and definitions PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/triggers/models.py theme_v2_service/app/domains/triggers/definitions.py theme_v2_service/migrations/versions/0003_triggers.py theme_v2_service/tests/unit/test_trigger_definitions.py theme_v2_service/tests/integration/test_trigger_concurrency.py
git commit -m "feat(theme-v2): add trigger tracker execution schema"
```

---

### Task 2: Implement pure proactive-summary decisions

**Files:**

- Create: `theme_v2_service/app/domains/triggers/proactive_summary.py`
- Create: `theme_v2_service/tests/unit/test_proactive_summary_rules.py`

**Interfaces:**

- Consumes: immutable tracker/execution snapshots, `now`, and user timezone.
- Produces: `ProactiveDecision` without database or notification side effects.

- [ ] **Step 1: Write the full rule matrix as failing tests**

Test exact cases:

```text
2 days + 7 assets                 -> no execution
7 days + 3 assets                 -> no execution
7 days + 7th asset                -> create execution revision 1 and notify
20 days + 7th asset               -> create execution revision 1 and notify
available + same-day new asset    -> update payload/revision, no notification
available + next-day first asset  -> update payload/revision and notify
dismissed + new asset             -> update only
suppressed + new asset            -> update only
dismiss expired + no new asset    -> no action
dismiss expired + first new asset -> notify
```

- [ ] **Step 2: Define the pure decision type**

```python
@dataclass(frozen=True)
class ProactiveDecision:
    create_execution: bool
    append_asset: bool
    next_revision: int | None
    should_notify: bool
    notification_local_date: date | None
```

- [ ] **Step 3: Implement local-day-aware evaluation**

```python
def decide_proactive_summary(snapshot: ProactiveSnapshot, *, now: datetime, timezone_name: str) -> ProactiveDecision:
    local_date = now.replace(tzinfo=timezone.utc).astimezone(ZoneInfo(timezone_name)).date()
    threshold_met = snapshot.cycle_age(now) >= timedelta(days=7) and snapshot.new_asset_count >= 7
    if snapshot.active_execution is None:
        return ProactiveDecision(threshold_met, True, 1 if threshold_met else None, threshold_met, local_date if threshold_met else None)
    blocked = snapshot.dismissed_until and now < snapshot.dismissed_until
    blocked = blocked or bool(snapshot.proactive_suppressed_until and now < snapshot.proactive_suppressed_until)
    next_revision = snapshot.active_execution.revision + 1
    should_notify = not blocked and snapshot.last_notified_local_date != local_date
    return ProactiveDecision(False, True, next_revision, should_notify, local_date if should_notify else None)
```

The snapshot count passed to this function includes the current newly inserted Asset exactly once.

- [ ] **Step 4: Run pure rule tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_proactive_summary_rules.py -q`

Expected: the entire matrix PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/triggers/proactive_summary.py theme_v2_service/tests/unit/test_proactive_summary_rules.py
git commit -m "feat(theme-v2): define proactive summary rules"
```

---

### Task 3: Evaluate proactive Trigger inside Asset creation

**Files:**

- Create: `theme_v2_service/app/domains/triggers/notifications.py`
- Create: `theme_v2_service/app/domains/triggers/service.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Create: `theme_v2_service/tests/integration/test_proactive_summary.py`
- Extend: `theme_v2_service/tests/integration/test_trigger_concurrency.py`

**Interfaces:**

- Consumes: flushed Asset, locked Tracker, pure `ProactiveDecision`, and `create_notification(session, command)`.
- Produces: `on_asset_created(session, asset, now, timezone_name) -> None`.

- [ ] **Step 1: Write failing transaction and concurrency tests**

Cover initial threshold, same-day revision without second notification, next-day notification, duplicate Asset signal, rollback, and ten concurrent Asset creates producing one Tracker and one active Execution.

- [ ] **Step 2: Implement tracker creation and locking**

`get_or_create_tracker_for_update` first selects by unique scope with `FOR UPDATE`. If absent, insert and flush; on duplicate-key race, rollback only to a nested savepoint, then re-select with `FOR UPDATE`. Never rollback the outer Asset transaction.

- [ ] **Step 3: Count the Asset with a relation row**

Insert `TriggerCountedAsset(tracker_id, asset_id)` in a nested transaction. On duplicate key, return without changing count, execution, or revision. On success, set `new_asset_count` from a `COUNT(*)` query so it cannot drift from the relation truth.

- [ ] **Step 4: Create or update the execution**

Initial dedupe key:

```python
dedupe_key = f"proactive_summary:{tracker.id}:{tracker.cycle_started_at.isoformat()}"
```

Payload always contains ordered current-cycle Asset IDs, `primary_skill_id`, `scope_started_at`, `scope_ended_at`, and `asset_count`. Existing available execution receives the new Asset ID and increments revision even when notification is suppressed.

- [ ] **Step 5: Publish a deduplicated revision Notification in the same transaction**

```python
async def ensure_report_available_notification(session, *, execution, tracker, title, body, local_date):
    link = f"report-start:{execution.id}:{execution.revision}"
    existing = await session.scalar(select(Notification.id).where(
        Notification.user_id == execution.user_id,
        Notification.type == "report_available",
        Notification.link == link,
    ))
    if existing is None:
        await create_notification(session, NotificationCreate(
            user_id=execution.user_id,
            type="report_available",
            title=title,
            body=body,
            link=link,
        ))
    tracker.last_notified_at = utc_now()
    tracker.last_notified_local_date = local_date
    execution.last_notified_revision = execution.revision
```

- [ ] **Step 6: Call the hook from `create_asset`**

After `session.flush()` and before the caller commits:

```python
await on_asset_created(session, asset=asset, now=utc_now(), timezone_name=settings.default_user_timezone)
```

The hook remains deterministic and does not call external code.

- [ ] **Step 7: Run integration tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_proactive_summary.py tests/integration/test_trigger_concurrency.py -q`

Expected: all transaction, revision, dedupe, and concurrency cases PASS.

- [ ] **Step 8: Commit**

```bash
git add theme_v2_service/app/domains/triggers/notifications.py theme_v2_service/app/domains/triggers/service.py theme_v2_service/app/domains/assets/service.py theme_v2_service/tests/integration/test_proactive_summary.py theme_v2_service/tests/integration/test_trigger_concurrency.py
git commit -m "feat(theme-v2): trigger proactive reports from assets"
```

---

### Task 4: Add Dismiss and atomic consumption contracts

**Files:**

- Create: `theme_v2_service/app/domains/triggers/api.py`
- Modify: `theme_v2_service/app/domains/triggers/service.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/tests/contract/test_trigger_dismiss_api.py`
- Create: `theme_v2_service/tests/integration/test_trigger_consumption.py`

**Interfaces:**

- Consumes: execution ID, current user, workflow run ID, and current time.
- Produces: `dismiss_execution` and `consume_execution`; Report Generation Task 2 calls the latter inside its Run transaction.

- [ ] **Step 1: Write failing Dismiss and consume tests**

Test available Dismiss, repeated Dismiss moving the 7-day window, consumed idempotency, expired `410`, cross-user `404`, proactive cycle reset, and tracker-free pre-event consumption.

- [ ] **Step 2: Implement Dismiss**

```python
async def dismiss_execution(session, *, user_id: str, execution_id: str, now: datetime) -> TriggerExecution:
    execution = await owned_execution_for_update(session, user_id, execution_id)
    if execution.status == "expired": raise ExecutionExpired()
    if execution.status == "consumed": return execution
    if execution.trigger_type != "proactive_summary": return execution
    tracker = await session.get(TriggerTracker, execution.tracker_id, with_for_update=True)
    tracker.dismissed_until = now + timedelta(days=7)
    return execution
```

- [ ] **Step 3: Implement atomic consumption**

`consume_execution` locks the owned row. For `consumed`, return its existing `workflow_run_id`; for `expired`, raise `ExecutionExpired`; for available, set `consumed`, `consumed_at`, and `workflow_run_id`. When a Tracker exists, clear `active_execution_id`, set `last_consumed_at`, set suppression to `now + 7 days`, reset cycle time/count, and delete that Tracker's `TriggerCountedAsset` rows.

- [ ] **Step 4: Expose only the Dismiss endpoint**

Register `POST /api/trigger-executions/{execution_id}/dismiss`. Do not create a public consume or list API.

- [ ] **Step 5: Run tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/contract/test_trigger_dismiss_api.py tests/integration/test_trigger_consumption.py -q`

Expected: all cases PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/triggers/api.py theme_v2_service/app/domains/triggers/service.py theme_v2_service/app/main.py theme_v2_service/tests/contract/test_trigger_dismiss_api.py theme_v2_service/tests/integration/test_trigger_consumption.py
git commit -m "feat(theme-v2): add trigger dismiss and consume contracts"
```

---

### Task 5: Implement pre-event T-60 evaluation

**Files:**

- Create: `theme_v2_service/app/domains/triggers/pre_event_report.py`
- Create: `theme_v2_service/tests/unit/test_pre_event_rules.py`
- Create: `theme_v2_service/tests/integration/test_pre_event_trigger.py`

**Interfaces:**

- Consumes: scheduled Event and `now`.
- Produces: `evaluate_pre_event(session, event, now)` and `scan_pre_event_window(session, now)`.

- [ ] **Step 1: Write the full time-rule matrix**

Test scheduled non-all-day at T-60, created inside one hour, all-day, cancelled, already started, rescheduled, repeated scan, and ordinary reminder coexistence at T-30/T-15.

- [ ] **Step 2: Implement pure eligibility**

```python
def is_pre_event_eligible(event: Event, now: datetime) -> bool:
    return event.status == "scheduled" and not event.all_day and event.start_at > now


def should_fire_pre_event(event: Event, now: datetime) -> bool:
    return is_pre_event_eligible(event, now) and event.start_at <= now + timedelta(hours=1)
```

- [ ] **Step 3: Implement deduplicated execution creation**

Use `pre_event_report:<event_id>:<UTC start_at>` as unique dedupe key, revision 1, no Tracker, and payload containing `event_id`, `event_start_at`, and `event_title`. Create `report_available` Notification with `report-start:<execution_id>:1` in the same transaction.

- [ ] **Step 4: Expire stale event executions**

On each scan, expire unconsumed executions for cancelled events, changed start timestamps, and events whose start time is `<= now`. A rescheduled event can create a new execution because its dedupe key changes.

- [ ] **Step 5: Run tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_pre_event_rules.py tests/integration/test_pre_event_trigger.py -q`

Expected: all time, change, expiry, dedupe, and notification cases PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/triggers/pre_event_report.py theme_v2_service/tests/unit/test_pre_event_rules.py theme_v2_service/tests/integration/test_pre_event_trigger.py
git commit -m "feat(theme-v2): add pre-event report trigger"
```

---

### Task 6: Add Worker scheduling and compensation

**Files:**

- Create: `theme_v2_service/app/domains/triggers/maintenance.py`
- Modify: `theme_v2_service/app/worker.py`
- Create: `theme_v2_service/tests/integration/test_trigger_compensation.py`
- Create: `theme_v2_service/tests/e2e/test_trigger_notification_flow.py`

**Interfaces:**

- Consumes: pre-event scan, available Executions, Trackers, Notification service.
- Produces: repeat-safe one-minute Trigger maintenance tick.

- [ ] **Step 1: Write failing compensation tests**

Seed and recover:

```text
available execution with last_notified_revision < revision
notification already exists but tracker acknowledgement is stale
tracker points to missing/expired execution
cancelled or started event still available
same maintenance window run twice
```

- [ ] **Step 2: Implement one maintenance tick**

```python
async def run_trigger_maintenance(session: AsyncSession, *, now: datetime) -> TriggerMaintenanceResult:
    expired = await expire_stale_pre_event_executions(session, now=now)
    fired = await scan_pre_event_window(session, now=now)
    repaired = await repair_missing_notifications(session, now=now)
    trackers = await repair_tracker_references(session, now=now)
    return TriggerMaintenanceResult(expired=expired, fired=fired, notifications_repaired=repaired, trackers_repaired=trackers)
```

Every sub-operation locks rows in stable ID order, uses existing dedupe keys, and commits once per bounded batch of at most 100 rows.

- [ ] **Step 3: Schedule the tick in Worker**

Run every 60 seconds with immediate first tick. A tick exception is logged with counts/IDs only and does not stop WorkflowJob polling. SIGTERM cancels future ticks after the active transaction finishes.

- [ ] **Step 4: Run the full Trigger gate**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_trigger_definitions.py tests/unit/test_proactive_summary_rules.py tests/unit/test_pre_event_rules.py tests/integration/test_proactive_summary.py tests/integration/test_trigger_concurrency.py tests/integration/test_trigger_consumption.py tests/integration/test_pre_event_trigger.py tests/integration/test_trigger_compensation.py tests/contract/test_trigger_dismiss_api.py tests/e2e/test_trigger_notification_flow.py -q`

Expected: all Trigger tests PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/triggers/maintenance.py theme_v2_service/app/worker.py theme_v2_service/tests/integration/test_trigger_compensation.py theme_v2_service/tests/e2e/test_trigger_notification_flow.py
git commit -m "feat(theme-v2): add trigger scheduler and compensation"
```

---

## Completion Gate

- The threshold matrix, daily reminder rule, Dismiss, consume, cooldown, and manual-report isolation match the spec.
- Concurrent Assets create one Tracker, one active Execution, and count each Asset once.
- Pre-event T-60 is emitted once per `(event_id, start_at)` and reacts correctly to cancel/reschedule/start.
- Every report suggestion exists as a durable TriggerExecution and Notification; Trigger never creates a ReportGenerationRun itself.
- Trigger maintenance is repeat-safe and does not use Redis, Kafka, external scheduler, or Agent calls.
