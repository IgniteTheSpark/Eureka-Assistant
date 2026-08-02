# Theme V2 Hardware Capture Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce the legacy card/ring audio → Tencent ASR → capture agent → Theme V2 records workflow in the independent Theme V2 Docker runtime and pass physical-device acceptance.

**Architecture:** Preserve the mature Flutter hardware contracts while implementing V2-owned device and capture domains. Durable MySQL `WorkflowJob` handlers perform asynchronous ASR and agent work; the Transactional Outbox publishes progress and completion without Redis, Kafka, legacy HTTP calls, old database access, or runtime imports from `backend/`.

**Tech Stack:** Flutter/Dart, native BLE plugins, FastAPI, Pydantic 2, SQLAlchemy 2 async, Alembic, MySQL 8, LiteLLM, HTTPX, Pytest, Docker Compose.

## Global Constraints

- Keep `docker-compose.theme-v2.yml` and the `eureka-theme-v2` Compose project isolated.
- Do not proxy, query, import, mount, or dual-write the old backend/runtime/database.
- Do not add Redis, Kafka, Celery, or another message broker.
- Preserve the REST and SSE contracts used by `DeviceController`, `DeviceSilentReconnect`, `FlashFileWorkflow`, and ring capture.
- All device, recording, job, record, notification, and retry operations are authenticated and owner-scoped.
- Never log bearer tokens, transcript bodies, model prompts, raw audio, or query-bearing signed audio URLs.
- Introduce every production behavior through a failing test first.
- Do not merge `main`; commit and push only `codex/theme-v2-ui-refactor`.

---

## File Structure

### New backend files

- `theme_v2_service/app/domains/devices/models.py` — Card and CardBinding persistence.
- `theme_v2_service/app/domains/devices/schemas.py` — mobile compatibility request/response schemas.
- `theme_v2_service/app/domains/devices/service.py` — binding ownership and state machine.
- `theme_v2_service/app/domains/devices/api.py` — `/api/cards/*` transport.
- `theme_v2_service/app/domains/capture/models.py` — CaptureFile, CaptureRecording, CaptureTurn.
- `theme_v2_service/app/domains/capture/schemas.py` — Flash/ASR compatibility and agent result schemas.
- `theme_v2_service/app/domains/capture/service.py` — recording ingestion, state transitions, retry, progress outbox.
- `theme_v2_service/app/domains/capture/asr.py` — Tencent provider interface and HTTP implementation.
- `theme_v2_service/app/domains/capture/agent.py` — capture request/result validation and baseline skill routing.
- `theme_v2_service/app/domains/capture/providers_litellm.py` — strict JSON-schema LiteLLM provider.
- `theme_v2_service/app/domains/capture/jobs.py` — `capture_asr` and `capture_process` job handlers.
- `theme_v2_service/app/domains/capture/api.py` — `/api/flash*` transport and bounded text-Flash wait.
- `theme_v2_service/migrations/versions/0006_device_bindings.py` — independent device tables.
- `theme_v2_service/migrations/versions/0007_capture_workflow.py` — capture tables and indexes.
- `theme_v2_service/tests/contract/test_device_api.py` — exact card contract.
- `theme_v2_service/tests/contract/test_capture_api.py` — exact Flash/ASR contract.
- `theme_v2_service/tests/integration/test_capture_jobs.py` — ASR/agent jobs and atomic output.
- `theme_v2_service/tests/unit/test_capture_asr.py` — Tencent parsing/error classification.
- `theme_v2_service/tests/unit/test_capture_agent.py` — prompt/result validation and routing.
- `theme_v2_service/tests/e2e/test_hardware_capture_flow.py` — fake-provider standalone workflow.

### New mobile files

- `mobile/lib/theme_v2/shell/theme_v2_device_status_adapter.dart` — live Card/Ring → Theme V2 summary.
- `mobile/test/theme_v2/shell/theme_v2_device_status_adapter_test.dart` — adapter and listener behavior.
- `mobile/test/theme_v2/theme_v2_startup_services_test.dart` — V2/legacy startup service gating.

### Modified files

- `theme_v2_service/app/main.py` — register device/capture routers.
- `theme_v2_service/app/jobs/registry.py` and `app/config.py` — capture handlers and settings.
- `theme_v2_service/app/domains/notifications/{subscribers,sse,outbox,service}.py` — typed generic SSE outbox frames.
- `theme_v2_service/migrations/env.py` and `tests/conftest.py` — import new metadata.
- `.env.theme-v2.example` and `docker-compose.theme-v2.yml` — pass capture settings.
- `mobile/lib/main.dart` and `mobile/lib/app_events.dart` — Theme V2 startup capability gate.
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart` and `theme_v2_rollout.dart` — live status adapter.
- Existing mobile device/Flash clients change only if a failing compatibility test proves a mismatch.

---

### Task 1: Device binding persistence and API

**Files:**
- Create: `theme_v2_service/app/domains/devices/{__init__,models,schemas,service,api}.py`
- Create: `theme_v2_service/migrations/versions/0006_device_bindings.py`
- Create: `theme_v2_service/tests/contract/test_device_api.py`
- Modify: `theme_v2_service/app/main.py`, `migrations/env.py`, `tests/conftest.py`

**Interfaces:**
- Produces `binding_info(session, user_id, card_sn)`, `bind_card(session, user_id, command)`, `list_bindings(session, user_id)`, and `unbind_card(session, user_id, binding_id, delete_data)`.
- Produces exact `/api/cards/*` field names consumed by Flutter.

- [ ] **Step 1: Write failing device contract tests**

```python
async def test_card_can_bind_list_and_unbind(client):
    token = await _register(client, "card-owner@example.com")
    headers = _headers(token)
    info = await client.post(
        "/api/cards/binding-info", headers=headers, json={"card_sn": "SN-001"}
    )
    assert info.json()["state"] == "never_bound_by_me"
    bound = await client.post(
        "/api/cards/bindings",
        headers=headers,
        json={
            "card_sn": "SN-001",
            "card_device_uuid": "device-uuid",
            "card_app_uuid": "app-uuid",
            "card_mac": "AA:BB",
            "card_mac_from": "android",
            "card_name": "W2",
            "card_nick": "UReka 录音卡",
        },
    )
    binding = bound.json()["binding"]
    assert binding["card_sn"] == "SN-001"
    assert (await client.get("/api/cards/bindings", headers=headers)).json()["bindings"] == [binding]
    removed = await client.post(
        f"/api/cards/{binding['binding_id']}/unbind",
        headers=headers,
        json={"delete_data": False},
    )
    assert removed.status_code == 200
```

Add separate tests for foreign active binding → 409, same-user rebind → update, foreign unbind → 404, blank fields → 400, and unauthenticated access → 401.

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_device_api.py -q
```

Expected: FAIL because `/api/cards/binding-info` returns 404.

- [ ] **Step 3: Implement models, migration, service, and API**

Use a nullable unique `active_card_id` to preserve historical bindings while allowing only one active binding per card. Service functions flush but do not commit; the request dependency owns the transaction. Catch `IntegrityError` and return 409.

- [ ] **Step 4: Run GREEN**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_device_api.py tests/integration/test_migrations.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/devices theme_v2_service/app/main.py theme_v2_service/migrations/env.py theme_v2_service/migrations/versions/0006_device_bindings.py theme_v2_service/tests/conftest.py theme_v2_service/tests/contract/test_device_api.py
git commit -m "feat(theme-v2): add device binding API"
```

### Task 2: Capture persistence and sync-client ASR ingress

**Files:**
- Create: `theme_v2_service/app/domains/capture/{__init__,models,schemas,service,api}.py`
- Create: `theme_v2_service/migrations/versions/0007_capture_workflow.py`
- Create: `theme_v2_service/tests/contract/test_capture_api.py`
- Modify: `theme_v2_service/app/main.py`, `migrations/env.py`, `tests/conftest.py`

**Interfaces:**
- Produces `accept_sync_result(...) -> CaptureAcceptance`, `accept_s3_upload(...) -> CaptureAcceptance`, and `get_recording(...)`.
- Consumes active card binding from Task 1.

- [ ] **Step 1: Write failing sync-result tests**

```python
async def test_bound_card_sync_asr_result_is_idempotently_accepted(client):
    token = await _registered_bound_card(client, "capture@example.com", "SN-001")
    payload = {
        "client_task_id": "task-001",
        "source": "realtime",
        "card_sn": "SN-001",
        "device_file_name": "flash-001.opus",
        "local_audio_sha256": "a" * 64,
        "local_audio_size_bytes": 2048,
        "audio_format": "opus",
        "asr_mode": "sync_client",
        "asr_provider": "tencent_asr_sync_client",
        "asr_status": "completed",
        "asr_text": "明天下午三点项目会",
        "asr_segments": [],
        "raw_response": {"code": 0},
    }
    first = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )
    second = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )
    assert first.json()["accepted"] is True
    assert second.json()["recording_id"] == first.json()["recording_id"]
    assert second.json()["duplicate"] is True
```

Add unbound card → 403, conflicting duplicate → 409, failed ASR terminal state, foreign recording → 404, malformed hash/size/mode → 422, and S3 upload shape tests.

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_capture_api.py -q
```

Expected: FAIL because the Flash compatibility routes are missing.

- [ ] **Step 3: Implement capture state**

Define `asr_processing → asr_done → agent_processing → done` with terminal `empty` and `failed`. The sync endpoint stores transcript/segments and enqueues one `capture_process` job using `capture-process:{recording_id}`. Failed/empty ASR does not queue agent work.

- [ ] **Step 4: Run GREEN**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_capture_api.py tests/integration/test_job_queue.py tests/integration/test_migrations.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/capture theme_v2_service/app/main.py theme_v2_service/migrations/env.py theme_v2_service/migrations/versions/0007_capture_workflow.py theme_v2_service/tests/conftest.py theme_v2_service/tests/contract/test_capture_api.py
git commit -m "feat(theme-v2): accept hardware ASR captures"
```

### Task 3: Generic outbox events and capture SSE

**Files:**
- Modify: `theme_v2_service/app/domains/notifications/{subscribers,sse,outbox,service}.py`
- Modify: `theme_v2_service/app/domains/capture/service.py`
- Create: `theme_v2_service/tests/contract/test_capture_sse.py`
- Modify: `theme_v2_service/tests/contract/test_notification_sse.py`

**Interfaces:**
- Produces `SubscriberFrame(event: str, payload: dict)`.
- Produces `publish_domain_event(...)`.
- Notification SSE remains byte-for-byte compatible.

- [ ] **Step 1: Write failing mixed-event tests**

```python
async def test_generic_outbox_frame_preserves_capture_event_name(session):
    registry = SubscriberRegistry()
    queue = registry.subscribe(USER_ID)
    async with session.begin():
        await publish_domain_event(
            session,
            event_type="flash_file_status",
            aggregate_type="capture_recording",
            aggregate_id=RECORDING_ID,
            user_id=USER_ID,
            payload={"recording_id": RECORDING_ID, "status": "asr_done"},
        )
    assert await dispatch_one(AsyncSessionFactory, registry, now=NOW)
    frame = queue.get_nowait()
    assert frame.event == "flash_file_status"
    assert frame.payload["status"] == "asr_done"
```

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_notification_sse.py tests/contract/test_capture_sse.py -q
```

Expected: FAIL because SSE always names frames `notification`.

- [ ] **Step 3: Implement typed frames**

```python
@dataclass(frozen=True)
class SubscriberFrame:
    event: str
    payload: dict[str, Any]
```

Reload Notification aggregates; publish capture `payload_json` directly. `with_heartbeats` calls `sse_event(frame.event, frame.payload)`.

- [ ] **Step 4: Run GREEN and commit**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_notification_sse.py tests/contract/test_capture_sse.py -q
git add theme_v2_service/app/domains/notifications theme_v2_service/app/domains/capture/service.py theme_v2_service/tests/contract/test_notification_sse.py theme_v2_service/tests/contract/test_capture_sse.py
git commit -m "feat(theme-v2): stream capture progress through outbox"
```

### Task 4: Async Tencent ASR job

**Files:**
- Create: `theme_v2_service/app/domains/capture/asr.py` and `jobs.py`
- Create: `theme_v2_service/tests/unit/test_capture_asr.py`
- Create: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Modify: `theme_v2_service/app/config.py`, `app/jobs/registry.py`, `docker-compose.theme-v2.yml`, `.env.theme-v2.example`

**Interfaces:**
- Produces `AsrProvider.create_task(...) -> AsrTask` and `get_result(...) -> AsrPollResult`.
- Produces `capture_asr_handler(provider)` and queues `capture_process` on success.

- [ ] **Step 1: Write failing provider/job tests**

Cover pending/running/finished/failed responses, signed URL redaction, retryable transport errors, permanent invalid responses, external task reuse, and finished transcript → process job.

```python
async def test_asr_job_reuses_checkpointed_external_task(session):
    provider = FakeAsrProvider(result=AsrPollResult.finished("记下咖啡二十八元"))
    recording = await seed_s3_recording(session, external_task_id="tencent-7")
    job = await seed_running_job(session, "capture_asr", recording.id)
    await capture_asr_handler(provider)(job)
    assert provider.created == []
    assert provider.polled == ["tencent-7"]
```

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/unit/test_capture_asr.py tests/integration/test_capture_jobs.py -q
```

- [ ] **Step 3: Implement provider and durable polling**

Add `TENCENT_ASR_SERVICE_BASE_URL`, poll interval/timeout, capture model/key/timeout settings. A pending poll checkpoints and requeues; never hold a worker lease while sleeping for the full ASR duration.

- [ ] **Step 4: Run GREEN and commit**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/unit/test_capture_asr.py tests/integration/test_capture_jobs.py tests/unit/test_config.py -q
git add theme_v2_service/app/config.py theme_v2_service/app/jobs/registry.py theme_v2_service/app/domains/capture/asr.py theme_v2_service/app/domains/capture/jobs.py theme_v2_service/tests/unit/test_capture_asr.py theme_v2_service/tests/integration/test_capture_jobs.py docker-compose.theme-v2.yml .env.theme-v2.example
git commit -m "feat(theme-v2): process async hardware ASR jobs"
```

### Task 5: Capture agent and baseline skills

**Files:**
- Create: `theme_v2_service/app/domains/capture/agent.py` and `providers_litellm.py`
- Create: `theme_v2_service/tests/unit/test_capture_agent.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`

**Interfaces:**
- Produces `ensure_capture_skills(session, user_id)`.
- Produces `CaptureAgentRequest`, `CaptureRecordCommand`, `CaptureAgentResult`.
- Produces `LiteLLMCaptureAgentProvider.organize(...)`.

- [ ] **Step 1: Write failing skill/schema/provider tests**

```python
async def test_baseline_capture_skills_are_idempotent(session):
    first = await ensure_capture_skills(session, USER_ID)
    second = await ensure_capture_skills(session, USER_ID)
    assert [s.machine_name for s in first] == [
        "todo", "expense", "contact", "idea", "notes", "misc"
    ]
    assert [s.id for s in second] == [s.id for s in first]
```

Also test event+expense output, QA with zero records, unknown/disabled skill rejection, invalid event range, custom skill acceptance, untrusted transcript markers, and invalid provider JSON.

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/unit/test_capture_agent.py -q
```

- [ ] **Step 3: Implement strict output**

```python
class CaptureRecordCommand(BaseModel):
    kind: Literal["asset", "event"]
    skill_machine_name: str | None = None
    payload: dict = Field(default_factory=dict)
    effective_at: datetime | None = None
    title: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None

class CaptureAgentResult(BaseModel):
    summary: str
    records: list[CaptureRecordCommand]
```

Use LiteLLM `response_format=json_schema` and canonical Flash intent rules.

- [ ] **Step 4: Run GREEN and commit**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/unit/test_capture_agent.py tests/integration/test_asset_service.py tests/contract/test_asset_api.py -q
git add theme_v2_service/app/domains/capture/agent.py theme_v2_service/app/domains/capture/providers_litellm.py theme_v2_service/app/domains/assets/service.py theme_v2_service/tests/unit/test_capture_agent.py
git commit -m "feat(theme-v2): add capture agent provider"
```

### Task 6: Atomic capture processing outputs

**Files:**
- Modify: `theme_v2_service/app/domains/capture/jobs.py` and `service.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Modify: `theme_v2_service/tests/integration/test_capture_jobs.py`

**Interfaces:**
- Produces `capture_process_handler(provider)`.
- Atomically writes Asset/Event, recording references, `flash_done` Notification, and Outbox events.

- [ ] **Step 1: Write failing atomic tests**

```python
async def test_capture_job_creates_multiple_records_and_notification(session):
    recording, job = await seed_transcribed_capture(
        session, "明天下午三点开项目会，咖啡二十八元"
    )
    await capture_process_handler(FakeCaptureAgentProvider(event_and_expense_result()))(job)
    saved = await session.get(CaptureRecording, recording.id)
    assert saved.process_status == "done"
    assert len(saved.result_records_json) == 2
    assert await count_rows(session, Event) == 1
    assert await count_rows(session, Asset) == 1
    assert await count_notifications(session, type="flash_done") == 1
```

Add rollback, duplicate job, foreign skill, QA, retryable provider, and permanent invalid-output tests.

- [ ] **Step 2: Run RED**

Expected: FAIL because `capture_process_handler` is missing.

- [ ] **Step 3: Implement handler**

Call the provider outside a transaction. In a short transaction lock the recording, validate state, create all records, set terminal metadata, create Notification and progress Outbox, and commit once. Completed recordings are no-ops.

- [ ] **Step 4: Run GREEN and commit**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/integration/test_capture_jobs.py tests/integration/test_trigger_consumption.py tests/e2e/test_notification_flow.py -q
git add theme_v2_service/app/domains/capture/jobs.py theme_v2_service/app/domains/capture/service.py theme_v2_service/app/jobs/registry.py theme_v2_service/tests/integration/test_capture_jobs.py
git commit -m "feat(theme-v2): persist capture agent results"
```

### Task 7: Text Flash, status, and retry compatibility

**Files:**
- Modify: `theme_v2_service/app/domains/capture/api.py` and `service.py`
- Modify: `theme_v2_service/tests/contract/test_capture_api.py`

**Interfaces:**
- `POST /api/flash` returns existing `FlashResult`.
- `GET /api/flash/recordings/{id}` returns the recording envelope.
- Retry resumes ASR or agent work according to durable state.

- [ ] **Step 1: Write failing ring/text and retry tests**

Test synchronous result, controlled pending timeout, owner-scoped status, ASR-vs-process retry selection, and deduped retries.

- [ ] **Step 2: Run RED**

Expected: FAIL at `POST /api/flash`.

- [ ] **Step 3: Implement bounded durable wait and exact response**

```python
class FlashResponse(BaseModel):
    ok: bool
    session_id: str
    input_turn_id: str
    reply: str = ""
    summary: str = ""
    cards: list[dict] = Field(default_factory=list)
    derived_assets: list[dict] = Field(default_factory=list)
    has_pending: bool = False
    elapsed_ms: int = 0
    error: str = ""
```

Use recording/turn IDs for compatibility. Poll database state; do not create an in-process agent task.

- [ ] **Step 4: Run GREEN and commit**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/contract/test_capture_api.py -q
git add theme_v2_service/app/domains/capture/api.py theme_v2_service/app/domains/capture/service.py theme_v2_service/tests/contract/test_capture_api.py
git commit -m "feat(theme-v2): complete flash compatibility API"
```

### Task 8: Live Theme V2 device status

**Files:**
- Create: `mobile/lib/theme_v2/shell/theme_v2_device_status_adapter.dart`
- Create: `mobile/test/theme_v2/shell/theme_v2_device_status_adapter_test.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart` and `theme_v2_rollout.dart`

**Interfaces:**
- Maps `DeviceController` and `RingConnection` to `DeviceStatusSummary`.
- Connected if either hardware is connected/bound; attention on card error; otherwise disconnected.

- [ ] **Step 1: Write failing adapter tests**

Assert semantic labels change from `设备：未连接` to card/ring connected without replacing the shell.

- [ ] **Step 2: Run RED**

```bash
cd mobile && flutter test test/theme_v2/shell/theme_v2_device_status_adapter_test.dart
```

- [ ] **Step 3: Implement adapter and production mounting**

Keep an optional `deviceStatus` override for tests; production listens to both controllers.

- [ ] **Step 4: Run GREEN/analyze and commit**

```bash
cd mobile && flutter test test/theme_v2/shell/theme_v2_device_status_adapter_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/device_controller_test.dart test/device_silent_reconnect_test.dart
cd mobile && flutter analyze lib/theme_v2/shell lib/device lib/ring
git add mobile/lib/theme_v2/shell mobile/lib/theme_v2/theme_v2_rollout.dart mobile/test/theme_v2/shell
git commit -m "feat(mobile): show live Theme V2 device status"
```

### Task 9: Theme V2 startup capability gating

**Files:**
- Modify: `mobile/lib/main.dart` and `mobile/lib/app_events.dart`
- Create: `mobile/test/theme_v2/theme_v2_startup_services_test.dart`

**Interfaces:**
- Keeps auth, SSE, BLE, Flash workflow, ring, reconnect, and V2 refresh.
- Prevents Pet/Nudge/Offer/legacy Timeline/Contacts/Skills startup calls.

- [ ] **Step 1: Write failing startup-policy tests**

```dart
test('Theme V2 starts hardware services without legacy product services', () {
  final policy = StartupCapabilities.forThemeV2();
  expect(policy.hardwareCapture, isTrue);
  expect(policy.notifications, isTrue);
  expect(policy.pet, isFalse);
  expect(policy.nudges, isFalse);
  expect(policy.legacyTimeline, isFalse);
});
```

- [ ] **Step 2: Run RED**

Expected: FAIL because startup is unconditional.

- [ ] **Step 3: Extract/apply capability policy**

Stop initiating unsupported requests at ownership boundaries; do not globally swallow HTTP errors. `AppEvents.start` receives whether legacy nudge recovery is enabled.

- [ ] **Step 4: Run GREEN and commit**

Run startup, auth, Today, device, and notification tests. Verify a clean V2 launch makes no `/api/pet`, `/api/nudges/*`, `/api/skills`, `/api/contacts`, or `/api/timeline` calls.

```bash
git add mobile/lib/main.dart mobile/lib/app_events.dart mobile/test/theme_v2/theme_v2_startup_services_test.dart
git commit -m "fix(mobile): isolate Theme V2 startup services"
```

### Task 10: Standalone Docker E2E

**Files:**
- Create: `theme_v2_service/tests/e2e/test_hardware_capture_flow.py`
- Modify: `theme_v2_service/scripts/smoke.sh`
- Modify: `docker-compose.theme-v2.yml` only for explicit fake-provider test wiring.

**Interfaces:**
- Exercises register → bind → transcript → worker → Event/Asset → Notification with old services stopped.

- [ ] **Step 1: Write failing real-MySQL E2E with fake external providers**

Use real FastAPI, MySQL, queue claims, handlers, and outbox. Fake only Tencent/model calls.

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/e2e/test_hardware_capture_flow.py -q
```

- [ ] **Step 3: Fix only proven integration seams**

Provider injection uses production handler factories; no test-only processing path.

- [ ] **Step 4: Run full backend suite/smoke and commit**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest -q
docker compose -f docker-compose.theme-v2.yml up -d --build
bash theme_v2_service/scripts/smoke.sh http://localhost:8100
git add theme_v2_service/tests/e2e/test_hardware_capture_flow.py theme_v2_service/scripts/smoke.sh docker-compose.theme-v2.yml
git commit -m "test(theme-v2): cover standalone hardware workflow"
```

### Task 11: APK and physical-device acceptance

**Files:** Modify production code only after a failing automated regression or reproducible device defect. Keep screenshots/log extracts in `/private/tmp`.

- [ ] **Step 1: Run final mobile verification**

```bash
cd mobile && flutter test
cd mobile && flutter analyze
cd mobile && flutter build apk --debug --dart-define=THEME_V2=true
```

- [ ] **Step 2: Install against Theme V2 only**

```bash
adb -s RFCY71B21YK install -r mobile/build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8100
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

- [ ] **Step 3: Verify short card capture**

Confirm BLE sync, client-sync ASR, sync-result 200, `capture_process` success, `flash_file_status done`, visible record, and restart persistence.

- [ ] **Step 4: Verify large card and ring paths**

Confirm S3 upload + `capture_asr` + agent for a large recording. Confirm ring double-tap record/stop + `POST /api/flash`.

- [ ] **Step 5: Verify clean exception log**

Clear logcat and confirm no 404/500 for supported startup/hardware routes and no raw `ApiException(...)` UI.

- [ ] **Step 6: Commit only test-proven device fixes**

Use a focused defect message; skip if no code changes.

### Task 12: Final verification and push

**Files:** Update plan checkboxes. Do not create a PR or merge `main`.

- [ ] **Step 1: Run completion checks**

```bash
git diff --check
git status -sb
git log --oneline --decorate -n 20
docker compose -f docker-compose.theme-v2.yml ps
```

Expected: clean worktree; API/MySQL healthy; worker running.

- [ ] **Step 2: Push current branch only**

```bash
git push origin codex/theme-v2-ui-refactor
```

- [ ] **Step 3: Report evidence**

Report backend/Flutter test counts, analyze result, APK path, Docker health, physical card short/large result, ring result, API status summary, final commit, and remote branch. State that `main` was not merged.

