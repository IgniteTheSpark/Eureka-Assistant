# Theme V2 Legacy Agent Migration — Tranche 1 Implementation Plan

> **For Codex:** Execute this plan task-by-task with test-driven development. Do not edit or stage unrelated dirty files. The approved architecture in `docs/superpowers/specs/2026-08-05-theme-v2-legacy-agent-migration-design.md` is authoritative.

**Goal:** Establish the durable Session/InputTurn foundation for the migrated legacy Agent and fix the current critical capture failure: final ASR text must appear immediately in a real daily Flash Session, custom Agent writes must tolerate missing optional data, and an already-open Session must refresh as processing changes.

**Architecture:** Keep the current Theme V2 worker, outbox, SSE, MySQL, and card presenter. Add a physical `session_type=flash` ChatSession keyed by user and local date, a first-class InputTurn, and recording-to-session/message links. ASR final materializes the visible turn and running Agent placeholder in the same transaction that enqueues processing. Existing capture processing updates that placeholder. Agent-originated custom Asset validation uses an internal permissive profile; manual API writes remain strict. SSE carries Session invalidation only, and mobile treats it as a debounced refetch signal.

**Tech Stack:** FastAPI, SQLAlchemy 2 async, Alembic/MySQL, durable WorkflowJob/outbox/SSE, Flutter/Dart, pytest, flutter_test.

## Program boundary

This tranche is the first independently deployable slice of the approved migration. It does not redefine the final architecture.

1. **Tranche 1 — durable Session foundation (this plan):** InputTurn, physical daily Flash Session, running/failed message durability, permissive custom Agent writes, live invalidation/refetch.
2. **Tranche 2 — internal Eureka CRUD MCP:** local stdio MCP server, user-scoped Theme V2 CRUD adapters, idempotent mutations, AssetField, Contact/Event and pending-confirmation contracts.
3. **Tranche 3 — unified legacy Chat:** migrate `assistant.py`, route every Session type through `/api/chat`, adapt the compatibility Flash route, retire separate FlashChatProvider behavior.
4. **Tranche 4 — legacy Flash pipeline:** dispatcher, intent normalizer, built-in/dynamic skills, sibling parallelism, CRUD MCP execution, aggregation, QA-without-write.
5. **Tranche 5 — presenter, data migration, rollout:** Theme V2 card presenter adapter, legacy evaluation parity, FlashChatMessage backfill/retirement, flags, cleanup, device acceptance.

## Non-negotiable contracts for this tranche

- One physical capture creates exactly one CaptureRecording and contributes exactly one daily Flash count.
- A physical daily Flash Session is a real UUID and unique by `(user_id, session_type, session_date)`.
- Final non-empty ASR creates or reuses that Session, persists one InputTurn, one user SessionMessage, and one running Agent SessionMessage, links the recording, enqueues processing, increments the Session revision, and writes `session_changed` in one transaction.
- Retrying organization reuses the same InputTurn and Agent message; it does not increment the Flash count or duplicate the user transcript.
- Chat turns create InputTurn provenance but no CaptureRecording.
- Custom-skill Agent writes tolerate omitted schema-required fields and extra extracted keys. Baseline built-in invariants and manual create/edit validation remain strict.
- The UI renders persisted data only. SSE tells an open Session to refetch; it is not the message source of truth.

---

### Task 1: Freeze the foundation contracts with failing tests

**Files:**

- Add: `theme_v2_service/tests/unit/test_agent_asset_validation_profile.py`
- Add: `theme_v2_service/tests/integration/test_capture_session_materialization.py`
- Modify: `theme_v2_service/tests/unit/test_session_chat.py`
- Add: `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`

**Step 1: Add a failing custom-write validation test**

Create a custom running skill whose JSON schema requires `distance`, `duration`, and `run_date`. Assert:

```python
result = CaptureAgentResult(
    summary="已记录跑步。",
    records=[CaptureRecordCommand(
        kind="asset",
        skill_machine_name="running_training_log",
        payload={"distance": 2, "location": "深圳湾人才公园"},
    )],
)

assert validate_capture_result(result, [custom_skill]) is result
```

Also assert the same partial payload is still rejected by strict/manual `validate_asset_payload`.

**Step 2: Add failing ASR-final materialization tests**

Cover sync and async completion paths. After final non-empty ASR, assert:

- one flash ChatSession exists with the expected local date;
- one InputTurn exists with `source=voice`, transcript, ASR/file provenance, and stable turn index;
- user and running agent SessionMessages share that InputTurn;
- CaptureRecording links to the Session, InputTurn, and Agent message;
- one capture process job is queued;
- one `session_changed` outbox event carries the Session UUID and revision;
- calling the finalization helper again creates no duplicates.

Add a retry test proving the same Agent message returns to `running` and no new InputTurn/session message is inserted.

**Step 3: Add a failing Chat provenance test**

Change the existing `/api/chat` service test to assert a real InputTurn row is created and both messages reference it, while CaptureRecording count remains unchanged.

**Step 4: Add a failing mobile invalidation test**

Use a fake API and injected invalidation notifier. Load `2026-08-05`, emit a matching `session_changed`, and assert the controller debounces and reloads the active daily Session without user refresh. Emit a different Session/date and assert there is no reload.

**Step 5: Run the new tests and confirm RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test pytest \
  tests/unit/test_agent_asset_validation_profile.py \
  tests/integration/test_capture_session_materialization.py \
  tests/unit/test_session_chat.py -q
```

```bash
cd mobile && flutter test test/theme_v2/capture/capture_session_realtime_test.dart
```

Expected: failures identify the missing validation profile, InputTurn/links/materializer, and invalidation listener.

---

### Task 2: Add physical Session and InputTurn persistence

**Files:**

- Modify: `theme_v2_service/app/domains/sessions/models.py`
- Modify: `theme_v2_service/app/domains/capture/models.py`
- Modify: `theme_v2_service/app/db/models.py`
- Add: `theme_v2_service/migrations/versions/0014_agent_session_foundation.py`
- Modify: `theme_v2_service/app/domains/sessions/schemas.py`
- Modify: `theme_v2_service/app/domains/sessions/service.py`
- Modify: `theme_v2_service/tests/conftest.py` only if model import registration requires it

**Step 1: Add the first-class InputTurn model**

Add `input_turns` with:

- UUID primary key;
- user/session/file/recording ownership links;
- per-Session integer `turn_index` with unique `(session_id, turn_index)`;
- transcript text and ASR segments;
- source, ASR provider, language, and provenance JSON;
- created/updated timestamps.

Make `SessionMessage.input_turn_id` a nullable FK with `SET NULL` deletion behavior.

**Step 2: Extend physical Sessions and recordings additively**

Add `ChatSession.session_date` and monotonic integer `revision`. Add unique `(user_id, session_type, session_date)`. Keep ordinary chat rows valid with a null date.

Add nullable `CaptureRecording.session_id`, `input_turn_id`, and `agent_message_id` FKs plus indexes. Keep CaptureTurn and FlashChatMessage for compatibility in this tranche.

**Step 3: Write the idempotent Alembic migration**

Migration `0014_agent_session_foundation` must:

- create InputTurn and new columns/constraints;
- create physical flash ChatSessions for existing non-empty recordings, grouped by user/local date;
- link existing recordings;
- backfill InputTurn and SessionMessages from CaptureTurn/recording state without duplicating on rerun;
- preserve current FlashChatMessage rows for the later unified-chat migration;
- clear top-level `required` only for non-baseline custom UserSkill schemas (Task 5 contract), preserving baseline skill invariants.

Use deterministic UUIDs for backfilled rows or guarded inserts so the data step is rerunnable.

**Step 4: Implement Session helpers**

Add helpers that lock/create the daily flash Session, allocate a turn index under the Session row lock, create an InputTurn, increment revision, and publish a `session_changed` event. Extend Session payloads with `session_date` and `revision`. Permit internal creation of `session_type=flash` while keeping public arbitrary session-type input constrained.

**Step 5: Run model/service tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test pytest \
  tests/integration/test_capture_session_materialization.py \
  tests/unit/test_session_chat.py -q
```

Expected: persistence helpers and Chat provenance assertions pass; capture finalization assertions may still fail until Task 3.

---

### Task 3: Materialize final ASR into Session atomically

**Files:**

- Modify: `theme_v2_service/app/domains/capture/service.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `theme_v2_service/app/domains/sessions/service.py`
- Modify: `theme_v2_service/app/domains/capture/schemas.py`
- Modify: `theme_v2_service/tests/contract/test_capture_api.py`
- Modify: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Modify: `theme_v2_service/tests/e2e/test_hardware_capture_flow.py`

**Step 1: Implement one idempotent finalization helper**

Create a service function invoked by text capture, sync client ASR, and async ASR completion. Within the caller's transaction it must:

1. lock the recording;
2. return existing linked objects when already materialized;
3. resolve the local date from `capture_started_at` and configured timezone;
4. get/create and lock the daily flash Session;
5. create the InputTurn and compatibility CaptureTurn if missing;
6. create user and running Agent SessionMessages;
7. link all IDs on CaptureRecording;
8. enqueue the deduplicated capture process job;
9. bump Session revision and publish `session_changed`.

Do not create an empty daily Session when ASR text is empty or failed.

**Step 2: Reuse the persisted Agent message during processing**

At job start, set the linked Agent message to `running`. On success, write summary/cards/status/elapsed time into that row. On permanent or exhausted failure, write `failed` and the safe user-facing error while retaining the user transcript. Bump the Session revision and emit `session_changed` for every persisted state transition.

**Step 3: Make retry idempotent**

`retry_recording` must clear the existing Agent error, set the same message back to `running`, and enqueue the same dedupe key. It must not create another daily Session, InputTurn, user message, or countable capture.

**Step 4: Return physical Session identity from compatibility APIs**

Add `physical_session_id`/`session_revision` to recording and daily-session payloads while retaining date IDs required by the current mobile controller. Do not rename existing response fields in this tranche.

**Step 5: Run capture suites**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test pytest \
  tests/contract/test_capture_api.py \
  tests/integration/test_capture_jobs.py \
  tests/e2e/test_hardware_capture_flow.py \
  tests/integration/test_capture_session_materialization.py -q
```

Expected: all pass, including failed organization retaining the visible transcript and failed Agent message.

---

### Task 4: Give ordinary Chat turns real provenance

**Files:**

- Modify: `theme_v2_service/app/domains/sessions/service.py`
- Modify: `theme_v2_service/app/domains/sessions/api.py`
- Modify: `theme_v2_service/app/domains/sessions/schemas.py`
- Modify: `theme_v2_service/tests/contract/test_session_api.py`
- Modify: `theme_v2_service/tests/unit/test_session_chat.py`

**Step 1: Replace fabricated turn IDs**

`create_turn` creates an InputTurn with source `typed`, a new per-Session index, and provenance describing the Chat API. The user and running Agent messages reference the persisted row.

**Step 2: Persist every Agent state transition**

On Chat completion/failure, update the existing Agent SessionMessage, bump Session revision, and publish `session_changed`. Preserve disconnect shielding already implemented in Theme V2.

**Step 3: Assert Session-type neutrality**

Add a service/contract test proving a physical `session_type=flash` Session can call the same `/api/chat` turn creation path and no CaptureRecording is created. Full legacy Assistant behavior is Tranche 3; this task freezes the routing boundary now.

**Step 4: Run Session suites**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test pytest \
  tests/contract/test_session_api.py \
  tests/unit/test_session_chat.py \
  tests/unit/test_session_tools.py -q
```

Expected: all pass.

---

### Task 5: Implement permissive custom Agent writes without weakening manual writes

**Files:**

- Modify: `theme_v2_service/app/domains/assets/validation.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/domains/capture/agent.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `theme_v2_service/app/domains/capture/providers_litellm.py`
- Modify: `theme_v2_service/app/domains/assets/skill_design.py`
- Modify: `theme_v2_service/tests/unit/test_capture_agent.py`
- Modify: `theme_v2_service/tests/unit/test_asset_validation.py` if present; otherwise add it
- Modify: relevant skill-designer API tests

**Step 1: Introduce an internal validation profile**

Use an internal enum such as `AssetWriteProfile.manual` and `AssetWriteProfile.agent`. Do not expose a client-selectable request field.

- `manual`: retain current required, type, enum, and additional-property validation.
- `agent` for non-baseline custom skills: require only an object payload; validate/normalize fields that are present when safe; do not fail for missing required keys or additional keys; never invent absent values.
- baseline built-ins: retain explicit invariant checks.

**Step 2: Apply the profile at both validation layers**

`validate_capture_result` and the internal `create_asset` call made by the capture worker must agree. A provider result cannot pass one layer and fail the transaction in the next.

Preserve the underlying `CaptureOutputError` message when possible instead of collapsing every schema error into `invalid capture provider response`.

**Step 3: Stop new custom skills from creating hard required arrays**

Normalize new/updated custom skill drafts so their top-level `required` array is empty for Agent capture. UI field metadata may still describe display priority; it must not become a capture-time hard requirement.

**Step 4: Prove the exact reported scenario**

Test a custom running schema that previously required duration. The transcript result containing only distance/location must persist the Asset and leave omitted fields absent. A second valid sibling record (for example water intake) must still persist.

**Step 5: Run validation and capture tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test pytest \
  tests/unit/test_agent_asset_validation_profile.py \
  tests/unit/test_capture_agent.py \
  tests/integration/test_capture_jobs.py -q
```

Expected: custom partial capture passes; manual incomplete create/edit still returns validation error.

---

### Task 6: Refetch an already-open Flash Session on invalidation

**Files:**

- Add: `mobile/lib/theme_v2/session/session_invalidation.dart`
- Modify: `mobile/lib/app_events.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_session_page.dart` only around controller lifecycle; preserve existing uncommitted injected-controller/new-chat changes
- Add: `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_session_page_test.dart` only if necessary; preserve existing uncommitted coverage

**Step 1: Add a typed invalidation notifier**

Parse `session_changed` payload into `{sessionId, sessionDate, revision, reason}`. Keep the latest event in a ValueNotifier or small injectable Listenable. Continue bumping global data revision for other screens.

**Step 2: Listen from CaptureSessionController**

Track the physical Session UUID and current date returned by the compatibility API. When a matching newer revision arrives, debounce for roughly 150–250 ms and refetch. Do not append SSE payloads directly. Ignore unrelated Sessions, stale revisions, and events after dispose.

**Step 3: Preserve the transcript during background refresh**

Background invalidation refresh must not clear current messages or replace the whole surface with a spinner. It may update `streaming`, messages, cards, and the inline error from the authoritative response.

**Step 4: Verify mobile behavior**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_page_test.dart \
  test/theme_v2/session/session_state_test.dart
```

Expected: active matching Session refreshes once; unrelated events do not; dispose cancels pending refresh; current new-chat behavior remains intact.

---

### Task 7: Migration and regression verification

**Files:**

- Modify only files already named by Tasks 1–6 if verification finds a defect

**Step 1: Check migration from a populated database**

Bring up an isolated test database at revision 0013, seed at least:

- a completed capture;
- a failed capture with ASR text;
- multiple same-day captures;
- an existing ordinary Chat Session;
- a custom skill with a non-empty required array.

Upgrade to head twice (second pass via a restored seed snapshot or rerun-safe backfill helper) and assert no duplicate Session/InputTurn/message rows and no loss of capture/chat data.

**Step 2: Run the full Theme V2 backend suite**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test pytest -q
```

Expected: zero failures.

**Step 3: Run focused Flutter analysis and tests**

Run:

```bash
cd mobile && flutter analyze \
  lib/app_events.dart \
  lib/theme_v2/session/session_invalidation.dart \
  lib/theme_v2/capture/capture_session_controller.dart \
  lib/theme_v2/capture/capture_session_page.dart \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_page_test.dart
```

```bash
cd mobile && flutter test test/theme_v2/capture test/theme_v2/session
```

Expected: analyzer clean and tests pass.

**Step 4: Run a fresh device smoke test**

With the Theme V2 Docker stack and Android device connected:

1. install/run the current branch;
2. open today's Flash Session;
3. record a hardware Flash containing a partial custom running record plus another valid intent;
4. observe ASR text and persisted running state appear without manual refresh;
5. leave and re-enter while Agent runs and confirm state persists;
6. confirm the Flash count increased by one, not by derived record count;
7. retry a forced/known failed organization and confirm no duplicate transcript/count.

**Step 5: Review and commit only tranche files**

Inspect `git diff`, run `git diff --check`, stage explicit paths only, and commit with:

```text
feat(theme-v2): add durable flash session foundation
```

Do not merge to main. Do not stage unrelated pre-existing edits.

**Step 6: Write and begin Tranche 2 plan**

After this tranche is verified, create the detailed internal CRUD MCP implementation plan using the program boundary above and continue execution.
