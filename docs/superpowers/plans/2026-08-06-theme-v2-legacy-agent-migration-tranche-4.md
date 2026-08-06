# Theme V2 Legacy Agent Migration — Tranche 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bounded Theme V2 capture organizer with the legacy-compatible Flash dispatcher, atomic intent normalizer, built-in/dynamic Skill execution, first-class Contact handling, parallel MCP execution, aggregation, and Theme V2 card presentation.

**Architecture:** Keep Theme V2 recordings, daily Sessions, InputTurns, durable jobs, MySQL, local FastMCP subprocess, outbox/SSE, and mobile components authoritative. Port the legacy behavior into Theme V2 modules without importing the legacy backend at runtime. A dispatcher returns normalized atomic intents; each intent executes through the trusted internal MCP runtime; Python aggregates domain results and the Theme V2 presenter snapshots cards. Contact ambiguity is a durable pending action, never a guessed write.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, LiteLLM, FastMCP 2.14, MySQL 8, Alembic, pytest, Dart, Flutter.

## Global Constraints

- `docs/superpowers/specs/2026-08-05-theme-v2-legacy-agent-migration-design.md` is authoritative.
- Behavioral references are `backend/agents/flash_pipeline.py`, `backend/agents/intent_normalizer.py`, `backend/agents/flash_reply.py`, `backend/agents/skill_factory.py`, and `backend/skills/flash-*/SKILL.md`.
- Do not import or start the legacy backend at Theme V2 runtime.
- Do not restore legacy `idea`, `misc`, or `other`; free-form fallback is `notes`.
- Do not add a unique `(user_id, normalized_name)` Contact constraint. Same-name people are valid.
- All mutations use the Theme V2 internal MCP runtime with trusted user, Session, InputTurn, and tool-call provenance injected server-side.
- Report and Morning Brief remain out of this tranche.
- Preserve unrelated dirty Pen/mobile work; use RED → GREEN for every change.

---

### Task 1: Port the Flash dispatcher and deterministic intent normalizer

**Files:**
- Create: `theme_v2_service/app/domains/capture/dispatcher.py`
- Create: `theme_v2_service/app/domains/capture/intent_normalizer.py`
- Modify: `theme_v2_service/app/domains/capture/agent.py`
- Modify: `theme_v2_service/app/domains/capture/providers_litellm.py`
- Test: `theme_v2_service/tests/unit/test_flash_dispatcher.py`
- Test: `theme_v2_service/tests/unit/test_flash_intent_normalizer.py`

**Interfaces:**
- Produces: `FlashIntent(type, source_text, domain)` and `FlashDispatchResult(intents)`.
- Produces: `normalize_intents(intents, custom_skill_catalog)` enforcing atomic expenses and Event range rules.
- Changes: LiteLLM provider dispatches intents rather than fabricating final records.

- [x] **Step 1: Write failing dispatcher/normalizer contract tests**

Cover multi-intent expense + todo, two expenses in one model intent, single-time meeting → Todo, complete range → Event, `idea|misc|other → notes`, custom Skill priority only over Notes, QA with no mutation, and transcript prompt-injection isolation.

- [x] **Step 2: Run focused tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_flash_dispatcher.py tests/unit/test_flash_intent_normalizer.py
```

- [x] **Step 3: Implement dispatcher and normalization**

Build the runtime custom Skill hint from enabled `UserSkill` schemas/render metadata. Keep classification tool-less and parse fenced JSON defensively. Model syntax/schema drift is retryable; deterministic invariants run after decoding.

- [x] **Step 4: Run focused tests and require GREEN**

Run the Step 2 command and require PASS.

### Task 2: Execute built-in and dynamic Skills through internal MCP

**Files:**
- Create: `theme_v2_service/app/domains/capture/skills.py`
- Create: `theme_v2_service/app/domains/capture/pipeline.py`
- Modify: `theme_v2_service/app/internal_mcp/runtime.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Test: `theme_v2_service/tests/unit/test_flash_skills.py`
- Test: `theme_v2_service/tests/unit/test_flash_pipeline.py`
- Test: `theme_v2_service/tests/integration/test_capture_jobs.py`

**Interfaces:**
- Produces: `FlashSkillResult` with `operation`, domain references, source text, status, optional reply, and tool snapshots.
- Produces: `LegacyFlashPipeline.run(...)` with parallel independent intent execution and deterministic aggregation.
- Changes: capture jobs ask the pipeline to execute records instead of directly calling `create_asset`/`create_event` from model JSON.

- [x] **Step 1: Write failing executor tests**

Assert Todo uses `tool_create_todo`, Notes uses `tool_create_note`, Expense CRUD uses asset query/update/delete tools, Event requires a complete range and uses first-class Event tools, QA produces text with no write, custom Skill writes a partial Agent-profile payload, and every tool call receives trusted provenance.

- [x] **Step 2: Run focused tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_flash_skills.py tests/unit/test_flash_pipeline.py tests/integration/test_capture_jobs.py
```

- [x] **Step 3: Implement Skill execution and aggregation**

Allow parallel sibling intent execution with stable result order. Reconstruct success from a successful tool result even when the sub-Skill's final JSON is malformed. Enforce one surfaced mutation per atomic intent and prune only same-turn unreferenced duplicates with the legacy provenance safety guards.

- [x] **Step 4: Run focused tests and require GREEN**

Run the Step 2 command and require PASS.

### Task 3: Restore first-class Contact create/update/delete and durable ambiguity

**Files:**
- Modify: `theme_v2_service/app/domains/sessions/models.py`
- Create: `theme_v2_service/app/domains/sessions/pending_actions.py`
- Create: `theme_v2_service/app/domains/sessions/api_pending_actions.py`
- Create: `theme_v2_service/app/domains/sessions/schemas_pending_actions.py`
- Create: `theme_v2_service/migrations/versions/0016_agent_pending_actions.py`
- Modify: `theme_v2_service/app/domains/capture/skills.py`
- Modify: `theme_v2_service/app/main.py`
- Test: `theme_v2_service/tests/unit/test_contact_flash_skill.py`
- Test: `theme_v2_service/tests/integration/test_contact_pending_actions.py`
- Test: `theme_v2_service/tests/contract/test_pending_actions_api.py`

**Interfaces:**
- Produces: `AgentPendingAction` with operation, candidate snapshots, patch/delete intent, owner/Session/InputTurn/Agent message, status, selected Contact, and resolution source.
- Produces: resolve/cancel endpoints with idempotent candidate-set enforcement.

- [x] **Step 1: Write failing Alex regression tests**

Prove: first `添加 Alex，他在 Acme 工作` creates one first-class Contact and zero contact-shaped Assets; later `Alex 的职业改成设计师` updates the same Contact and keeps count one; two exact Alex rows produce a persisted `pending_confirmation` and mutate neither; contains-only `Alex Chen` never binds as exact Alex.

- [x] **Step 2: Run focused tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_contact_flash_skill.py \
  tests/integration/test_contact_pending_actions.py \
  tests/contract/test_pending_actions_api.py
```

- [x] **Step 3: Implement exact-name decision and pending state**

Query `exact_contacts` through `tool_query_contact`; 0 creates, 1 updates/deletes, 2+ stores candidates and intent with no mutation. Resolution may select only a stored candidate and is idempotent under row lock. Persist Agent message status as `waiting_confirmation` and publish Session invalidation.

- [x] **Step 4: Run migration and focused tests to GREEN**

Upgrade a clean Theme V2 database through `0016`, run the Step 2 suite, and require PASS.

### Task 4: Aggregate through the Theme V2 presenter and live transcript

**Files:**
- Create: `theme_v2_service/app/domains/capture/presenter.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `theme_v2_service/app/domains/sessions/schemas.py`
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_session_page.dart`
- Test: `theme_v2_service/tests/unit/test_capture_presenter.py`
- Test: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Test: `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`
- Test: `mobile/test/theme_v2/capture/capture_session_page_test.dart`

**Interfaces:**
- The running Agent placeholder becomes `done`, `waiting_confirmation`, or per-turn `failed`.
- Persisted cards include display snapshots and live entity references.
- An open daily Session sees final ASR text, Agent loading, completion/cards, or a turn-local failure without refresh.

- [x] **Step 1: Write failing presenter/realtime tests**

Cover partial success, Event, Expense, Contact create/update, pending candidates, custom Skill, reload durability, and a failed capture scoped only to its Agent turn.

- [x] **Step 2: Run focused tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_capture_presenter.py tests/integration/test_capture_jobs.py
cd mobile && flutter test \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_page_test.dart
```

- [x] **Step 3: Implement deterministic aggregation and mobile pending cards**

The short completion reply may use a bounded read-only model call with deterministic fallback. Card failure cannot erase a successful mutation. Candidate taps and natural-language Chat resolution operate on the same pending row.

- [x] **Step 4: Run focused tests and require GREEN**

Run the Step 2 commands and require PASS.

### Task 5: Full Flash acceptance and isolated commit

**Files:**
- Modify only when a failing acceptance test requires it: files from Tasks 1–4.

- [x] **Step 1: Run the backend Flash, MCP, Session, timeline, and notification suites**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_flash_dispatcher.py \
  tests/unit/test_flash_intent_normalizer.py \
  tests/unit/test_flash_skills.py \
  tests/unit/test_flash_pipeline.py \
  tests/unit/test_contact_flash_skill.py \
  tests/unit/test_capture_presenter.py \
  tests/integration/test_internal_mcp_stdio.py \
  tests/integration/test_internal_mcp_tools.py \
  tests/integration/test_capture_jobs.py \
  tests/integration/test_contact_pending_actions.py \
  tests/integration/test_capture_session_materialization.py \
  tests/contract/test_capture_api.py \
  tests/contract/test_pending_actions_api.py \
  tests/e2e/test_hardware_capture_flow.py
```

- [x] **Step 2: Run legacy-parity eval fixtures**

Add and run deterministic cases for multi-intent, expense correction, Contact Alex create/update/ambiguity, Event attendee exact/zero/multiple binding, Notes fallback, custom Skill routing, QA, and temporal placement.

- [ ] **Step 3: Build, install, and test on the connected phone**

Use a real ring recording to verify: transcript appears live, one loading state appears, Alex update does not duplicate, an ambiguous same-name update survives Session re-entry, cards navigate, notification opens the physical Session, and the Flash count increments once per hardware recording only.

- [ ] **Step 4: Commit Tranche 4 without pushing or merging**

Keep Report/Morning Brief and Tranche 5 data backfill out of this commit.
