# Theme V2 Session and Chat Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ordinary Theme V2 Sessions persistent and restore the `/api/chat` pipeline used by the existing mobile Chat controller.

**Architecture:** Add a focused Session domain to the isolated service, preserve the mobile REST/SSE contract, and implement a bounded LiteLLM chat provider with current-user query/create tools. Session and transcript persistence are independent from daily Flash Session chat.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Alembic, LiteLLM, SSE, pytest, Dart, Flutter.

## Global Constraints

- Do not depend on the legacy Docker service or Google ADK runtime.
- Keep daily Flash Sessions and ordinary Chat Sessions distinct.
- Session history must survive navigation and app re-entry.
- Deleting a Session must not delete assets created by it.
- All reads/writes are owner-scoped.

---

### Task 1: Add Session persistence and REST contracts

**Files:**
- Create: `theme_v2_service/migrations/versions/0013_chat_sessions.py`
- Create: `theme_v2_service/app/domains/sessions/__init__.py`
- Create: `theme_v2_service/app/domains/sessions/models.py`
- Create: `theme_v2_service/app/domains/sessions/schemas.py`
- Create: `theme_v2_service/app/domains/sessions/service.py`
- Create: `theme_v2_service/app/domains/sessions/api.py`
- Modify: `theme_v2_service/app/db/models.py`
- Modify: `theme_v2_service/app/main.py`
- Modify: `theme_v2_service/tests/conftest.py`
- Modify: `theme_v2_service/tests/integration/test_migrations.py`
- Test: `theme_v2_service/tests/contract/test_session_api.py`

**Interfaces:**
- Produces: `ChatSession`, `ChatMessage`, and asset provenance columns
  `session_id`/`source_input_turn_id`.
- Produces: `/api/sessions*` routes consumed by `ChatController`.

- [ ] **Step 1: Write failing migration and owner-scoped CRUD tests**

```python
created = await client.post("/api/sessions", headers=_headers(owner), json={
    "session_type": "chat",
})
assert created.status_code == 200
session_id = created.json()["session_id"]
assert (await client.get("/api/sessions", headers=_headers(owner))).json()["sessions"][0]["id"] == session_id
assert (await client.get(f"/api/sessions/{session_id}", headers=_headers(foreign))).status_code == 404
```

Cover blank create, subject `peek_only`, list, detail, context add/remove,
message ordering, delete, and cross-user isolation.

- [ ] **Step 2: Run and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/contract/test_session_api.py tests/integration/test_migrations.py -q`

Expected: 404 from `/api/sessions` and missing tables.

- [ ] **Step 3: Implement models, migration, service, and routes**

Use UUID strings and UTC-naive MySQL timestamps. `context_asset_ids_json` is a
JSON list of strings. Message roles are `user` and `agent`; status is
`running`, `done`, or `failed`. Session delete sets asset provenance Session
fields to null before deleting the transcript.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/migrations/versions/0013_chat_sessions.py theme_v2_service/app/domains/sessions theme_v2_service/app/db/models.py theme_v2_service/app/main.py theme_v2_service/tests/conftest.py theme_v2_service/tests/integration/test_migrations.py theme_v2_service/tests/contract/test_session_api.py
git commit -m "feat(theme-v2): restore ordinary session contracts"
```

### Task 2: Implement the bounded Chat provider and tool loop

**Files:**
- Create: `theme_v2_service/app/domains/sessions/chat.py`
- Create: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/config.py`
- Modify: `docker-compose.theme-v2.yml`
- Modify: `.env.theme-v2.example`
- Test: `theme_v2_service/tests/unit/test_session_chat.py`
- Test: `theme_v2_service/tests/unit/test_session_tools.py`

**Interfaces:**
- Produces: `SessionChatProvider.answer(...) -> SessionChatResult`.
- Produces: bounded tools `query_assets`, `create_asset`, `query_events`,
  `create_event`.
- Adds `CHAT_AGENT_ENABLED`, `CHAT_AGENT_MODEL`, `CHAT_AGENT_API_KEY`, and
  `CHAT_AGENT_TIMEOUT_SECONDS`, defaulting to capture-agent values in Compose.

- [ ] **Step 1: Write failing provider/tool tests**

Assert prompt isolation, history/context inclusion, owner-scoped queries,
schema-valid create, rejection of unknown fields, and deterministic tool-result
normalization. Example:

```python
with pytest.raises(AssetPayloadInvalid):
    await create_asset_tool(session, user_id, skill_id, {
        "distance": 5,
        "acceptance_marker": "forbidden",
    })
```

- [ ] **Step 2: Run and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/unit/test_session_chat.py tests/unit/test_session_tools.py -q`

Expected: import failures for the new Session Chat modules.

- [ ] **Step 3: Implement provider and bounded tools**

Use LiteLLM chat completion. The system prompt treats history, attached assets,
and user text as untrusted data. Execute only the allow-listed tools and stop
after a bounded number of tool rounds. Return normalized text plus tool events
and renderable cards.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/sessions/chat.py theme_v2_service/app/domains/sessions/tools.py theme_v2_service/app/config.py docker-compose.theme-v2.yml .env.theme-v2.example theme_v2_service/tests/unit/test_session_chat.py theme_v2_service/tests/unit/test_session_tools.py
git commit -m "feat(theme-v2): add bounded session chat provider"
```

### Task 3: Add `/api/chat` SSE with durable turn recovery

**Files:**
- Create: `theme_v2_service/app/domains/sessions/api_chat.py`
- Modify: `theme_v2_service/app/domains/sessions/service.py`
- Modify: `theme_v2_service/app/main.py`
- Test: `theme_v2_service/tests/contract/test_chat_api.py`
- Test: `theme_v2_service/tests/integration/test_chat_recovery.py`

**Interfaces:**
- Produces: `POST /api/chat` SSE frames `meta`, `token`, `tool_call`,
  `tool_result`, `error`, `done`.
- Persists a `running` agent message before provider work and finalizes it to
  `done` or `failed`.

- [ ] **Step 1: Write failing SSE and recovery tests**

```python
response = await client.post("/api/chat", headers=_headers(token), json={
    "user_text": "今天记录了什么？",
    "session_id": "",
})
assert response.status_code == 200
assert "event: meta" in response.text
assert "event: done" in response.text
```

Then reload `/api/sessions/{id}/messages` and assert the user and finalized
agent messages replay oldest-first. Seed a `running` message, finalize it after
the view has left, and assert polling reads the completed result.

- [ ] **Step 2: Run and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/contract/test_chat_api.py tests/integration/test_chat_recovery.py -q`

Expected: 404 from `/api/chat`.

- [ ] **Step 3: Implement durable SSE lifecycle**

Resolve/create a chat Session, persist user + running agent messages, emit
`meta`, stream or chunk answer text, emit tool events, finalize the message,
then emit `done`. On provider failure finalize as `failed` and emit a public
error without exposing provider secrets.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/sessions/api_chat.py theme_v2_service/app/domains/sessions/service.py theme_v2_service/app/main.py theme_v2_service/tests/contract/test_chat_api.py theme_v2_service/tests/integration/test_chat_recovery.py
git commit -m "feat(theme-v2): restore durable chat SSE"
```

### Task 4: Align the mobile Chat controller with Theme V2 asset contracts

**Files:**
- Modify: `mobile/lib/chat/chat_controller.dart`
- Test: `mobile/test/theme_v2/session/chat_controller_theme_v2_api_test.dart`
- Test: `mobile/test/theme_v2/session/chat_controller_retry_test.dart`
- Test: `mobile/test/theme_v2/session/session_state_test.dart`

**Interfaces:**
- Consumes: Session REST and Chat SSE contracts from Tasks 1 and 3.
- Changes precipitation to resolve `user_skill_id` before posting `/api/assets`.

- [ ] **Step 1: Write failing mobile API tests**

Assert a blank Theme V2 chat sends `/api/chat`, receives `meta`, persists the
Session ID, appears in history, reloads messages, and creates a precipitated
asset with `user_skill_id` rather than legacy `user_skill_name`.

- [ ] **Step 2: Run and verify RED**

Run: `cd mobile && flutter test test/theme_v2/session/chat_controller_theme_v2_api_test.dart`

Expected: precipitate request uses the legacy request body or replay fails.

- [ ] **Step 3: Implement minimal client alignment**

Keep the established UI/session state matrix. Change only request adaptation,
public error copy, and any SSE frame normalization required by the service
contract.

- [ ] **Step 4: Run focused mobile Session tests**

Run: `cd mobile && flutter test test/theme_v2/session/chat_controller_theme_v2_api_test.dart test/theme_v2/session/chat_controller_retry_test.dart test/theme_v2/session/session_state_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/chat/chat_controller.dart mobile/test/theme_v2/session/chat_controller_theme_v2_api_test.dart mobile/test/theme_v2/session/chat_controller_retry_test.dart mobile/test/theme_v2/session/session_state_test.dart
git commit -m "fix(session): connect Theme V2 chat contracts"
```
