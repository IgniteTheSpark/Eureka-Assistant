# Theme V2 Legacy Agent Migration — Tranche 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the simplified Theme V2 Session and Flash-chat assistants with one durable, legacy-compatible Chat pipeline that uses the local Eureka CRUD MCP runtime for every tool operation.

**Architecture:** Keep Theme V2 `ChatSession`, `InputTurn`, `SessionMessage`, durable completion, outbox/SSE, MySQL, and cards as the authority. Port the in-scope behavior of the legacy Assistant into a bounded multi-round LiteLLM tool loop, obtain the complete tool catalog from one lazy/recoverable local FastMCP stdio subprocess, and route ordinary and physical daily Flash Sessions through the same turn service. The date compatibility route remains temporarily but delegates to that service and never writes `FlashChatMessage`.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, FastMCP 2.14, LiteLLM, MySQL 8, pytest, Dart, Flutter.

## Global Constraints

- `docs/superpowers/specs/2026-08-05-theme-v2-legacy-agent-migration-design.md` is authoritative.
- Do not import the legacy `backend` service at Theme V2 runtime.
- Do not start external MCP, Task Skill, Connected Apps, Suggest, Morning Briefing, or the legacy Report pipeline.
- Every Chat mutation and query uses the Theme V2 local stdio MCP subprocess with trusted user/Session/InputTurn arguments injected by the server runtime.
- Typed Chat in a physical Flash Session creates an `InputTurn(source="typed")`, creates no `CaptureRecording`, and does not change the Flash count.
- Preserve unrelated dirty Pen and mobile files; stage only files listed in this plan.
- Use test-first RED → GREEN cycles for every behavior change.

---

### Task 1: Add the persistent internal MCP client runtime

**Files:**
- Create: `theme_v2_service/app/internal_mcp/runtime.py`
- Modify: `theme_v2_service/app/main.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Test: `theme_v2_service/tests/unit/test_internal_mcp_runtime.py`
- Test: `theme_v2_service/tests/unit/test_session_tools.py`

**Interfaces:**
- Produces: `InternalMCPRuntime.start()`, `list_openai_tools()`, `call_tool(...)`, and `close()`.
- Produces: `get_internal_mcp_runtime()` process singleton.
- Changes: `SessionToolExecutor(..., runtime=...)` injects `user_id`, `session_id`, `source_input_turn_id`, and `tool_call_id` after model output.

- [ ] **Step 1: Write failing runtime lifecycle and trusted-injection tests**

```python
runtime = InternalMCPRuntime(client_factory=factory)
assert len(await runtime.list_openai_tools()) >= 20
result = await runtime.call_tool("tool_query_asset", {"user_id": "model"}, trusted=trusted)
assert fake.calls[0][1]["user_id"] == "owner"
await runtime.close()
assert fake.exits == 1
```

Also make the first fake client fail once and assert the runtime closes it, creates one replacement, and replays the read-only call once.

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_internal_mcp_runtime.py tests/unit/test_session_tools.py
```

Expected: import failure for `app.internal_mcp.runtime` and the current direct in-process executor does not use the fake runtime.

- [ ] **Step 3: Implement the lazy/recoverable stdio runtime**

Use one cached `fastmcp.Client` configured with:

```python
{
    "mcpServers": {
        "eureka": {
            "command": sys.executable,
            "args": ["-m", "app.internal_mcp.server"],
            "env": os.environ.copy(),
        }
    }
}
```

Convert every MCP `Tool` to LiteLLM/OpenAI format using `name`, `description`, and `inputSchema`. Serialize lifecycle transitions behind an `asyncio.Lock`; allow concurrent healthy calls; on transport failure close/reset and retry once. Parse FastMCP text/structured results into the normalized dictionary returned by `SessionToolExecutor`.

- [ ] **Step 4: Wire startup/shutdown and verify GREEN**

Start the runtime during FastAPI lifespan only when Chat Agent is enabled, fail readiness/startup when the internal MCP cannot list tools, and always close it during shutdown. Run the Step 2 command and require PASS.

### Task 2: Port the legacy Chat Assistant behavior and full tool loop

**Files:**
- Create: `theme_v2_service/app/domains/sessions/legacy_assistant.py`
- Modify: `theme_v2_service/app/domains/sessions/chat.py`
- Modify: `theme_v2_service/app/domains/sessions/service.py`
- Test: `theme_v2_service/tests/unit/test_legacy_assistant.py`
- Test: `theme_v2_service/tests/unit/test_session_chat.py`

**Interfaces:**
- Produces: `build_legacy_assistant_instruction(context: LegacyChatContext) -> str`.
- Produces: `build_legacy_chat_messages(...) -> list[dict]`.
- Changes: `LiteLLMSessionChatProvider.answer(...)` supports up to six dependent tool rounds and parallel sibling calls in one round.

- [ ] **Step 1: Write failing behavior-contract tests**

Assert the instruction encodes these in-scope legacy contracts:

```python
assert "CREATE / QUERY / UPDATE / DELETE" in prompt
assert "tool_create_contact" in prompt
assert "刚才那个" in prompt
assert "把刚才的回答存成随记" in prompt
assert "普通问答不创建记录" in prompt
assert "外部 MCP" in prompt and "不可使用" in prompt
```

Add a three-completion provider test: first completion queries an asset, second updates the returned ID, third answers from the successful result. Assert both tool results are appended to history, both cards/results are captured, and the stable tool-call IDs reach the executor.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_legacy_assistant.py tests/unit/test_session_chat.py
```

Expected: the legacy instruction module is missing and the current provider stops after one tool round.

- [ ] **Step 3: Implement the in-scope legacy prompt and multi-round loop**

Port the behavioral rules, not legacy infrastructure imports:

- natural CREATE/QUERY/UPDATE/DELETE and honest success claims;
- normal QA without writes;
- Chat opinion versus explicit capture;
- follow-up field completion updates the preceding entity;
- explicit save-from-previous-reply creates a note;
- Todo/Event time-range distinction;
- registered custom skill selection and partial payloads;
- Contact/Event first-class tools;
- report requests redirect to the existing Report entry;
- external MCP/Task/Connected Apps/Morning Briefing are unavailable.

Feed current local date/time, Session ID, InputTurn ID, enabled skill catalog, Session-linked entities, attached/subject context, and persisted tool/card snapshots into the prompt. Never trust a user/model-supplied owner ID.

- [ ] **Step 4: Persist complete tool snapshots and verify GREEN**

Store all tool calls/results in `SessionMessage.tool_call_json` and `tool_result_json` as `{"calls": [...]}` / `{"results": [...]}` while keeping response parsing backward-compatible with the previous single-object shape. Run the Step 2 tests and require PASS.

### Task 3: Extract one durable turn service and unify the compatibility route

**Files:**
- Create: `theme_v2_service/app/domains/sessions/turns.py`
- Modify: `theme_v2_service/app/domains/sessions/api_chat.py`
- Modify: `theme_v2_service/app/domains/capture/api.py`
- Modify: `theme_v2_service/app/domains/capture/service.py`
- Modify: `theme_v2_service/app/domains/capture/schemas.py`
- Test: `theme_v2_service/tests/contract/test_chat_api.py`
- Test: `theme_v2_service/tests/contract/test_capture_api.py`

**Interfaces:**
- Produces: `prepare_chat_turn(...) -> PreparedChatTurn` and `complete_chat_turn(...) -> CompletedChatTurn`.
- `/api/chat` remains SSE and uses those functions.
- `/api/flash/sessions/{date}/chat` resolves the physical UUID and calls the same functions, returning a temporary JSON compatibility envelope.

- [ ] **Step 1: Write failing route-unification tests**

For the date compatibility route, assert:

```python
assert typed_turn.source == "typed"
assert typed_turn.session_id == physical_session.id
assert capture_count_after == capture_count_before
assert flash_chat_message_count == 0
assert persisted_agent.text == response.json()["reply"]
```

Assert provider context and tool behavior are identical when sending the same turn through `/api/chat` with the physical Session ID.

- [ ] **Step 2: Run contract tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/contract/test_chat_api.py tests/contract/test_capture_api.py
```

Expected: the compatibility route writes `FlashChatMessage` and uses `FlashChatProvider`.

- [ ] **Step 3: Implement the shared durable turn service**

Move Session validation/creation, history/context loading, user/running message creation, provider completion, final state/card/tool persistence, revision bump, and public error normalization into `sessions/turns.py`. Keep the provider task shielded from client disconnect. Make the compatibility route a thin physical-Session lookup plus the same service invocation.

- [ ] **Step 4: Stop new FlashChatMessage writes and verify GREEN**

Keep the table and old-row reader only for the Tranche 5 backfill, but remove it from all new Chat execution. Run the Step 2 command and require PASS.

### Task 4: Move the Flash Session mobile surface to the physical Session transcript

**Files:**
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Modify: `mobile/test/theme_v2/capture/flash_notification_target_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`
- Test: `mobile/test/theme_v2/capture/capture_session_unified_chat_test.dart`

**Interfaces:**
- `CaptureSessionController` loads `/api/sessions/{physical_session_id}/messages` as transcript authority.
- `CaptureSessionController.send` streams `/api/chat` with the physical Session UUID.
- The date remains presentation/compatibility metadata only.

- [ ] **Step 1: Write failing controller tests**

Assert loading a date response with `physical_session_id` fetches the unified message endpoint, preserves message ordering/status/cards, and sends:

```dart
turnStream('/api/chat', {
  'session_id': physicalSessionId,
  'user_text': '把刚才那个改成下午三点',
});
```

Assert the controller never sends new text to `/api/flash/sessions/{date}/chat` and an SSE error remains scoped to that Chat turn.

- [ ] **Step 2: Run the new Flutter tests and verify RED**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/capture/capture_session_unified_chat_test.dart \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/flash_notification_target_test.dart
```

Expected: current controller uses the date compatibility POST route and rebuilds recordings separately from Chat messages.

- [ ] **Step 3: Implement the physical-session transcript adapter**

Inject the established `ChatTurnStream`, fold `meta/token/tool_call/tool_result/error/done` into the current `ChatMessage`, and reconcile persisted messages after completion or re-entry. Retain recording-detail fallback only for historical rows that lack a physical Session ID.

- [ ] **Step 4: Run focused Flutter tests and require GREEN**

Run the Step 2 command plus `test/theme_v2/session/session_state_test.dart` and require PASS.

### Task 5: Tranche acceptance, isolated stack, and commit

**Files:**
- Modify only when a failing acceptance test requires it: files from Tasks 1–4.

- [ ] **Step 1: Run backend Chat/MCP/Capture suites**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_internal_mcp_runtime.py \
  tests/unit/test_internal_mcp_server.py \
  tests/integration/test_internal_mcp_stdio.py \
  tests/integration/test_internal_mcp_tools.py \
  tests/unit/test_legacy_assistant.py \
  tests/unit/test_session_chat.py \
  tests/unit/test_session_tools.py \
  tests/contract/test_chat_api.py \
  tests/contract/test_capture_api.py \
  tests/integration/test_capture_session_materialization.py
```

- [ ] **Step 2: Run Flutter regression suites and analyze touched Dart**

```bash
cd mobile && flutter test \
  test/theme_v2/capture/capture_session_unified_chat_test.dart \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/flash_notification_target_test.dart \
  test/theme_v2/session/session_state_test.dart

flutter analyze lib/theme_v2/capture/capture_session_controller.dart \
  test/theme_v2/capture/capture_session_unified_chat_test.dart
```

- [ ] **Step 3: Rebuild the isolated Theme V2 services and check readiness**

```bash
docker compose -f docker-compose.theme-v2.yml up -d --build api worker
docker compose -f docker-compose.theme-v2.yml exec -T api \
  python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/ready').read().decode())"
```

- [ ] **Step 4: Build/install the Theme V2 APK and verify on the connected device**

Build with `THEME_V2=true` and `API_BASE=http://localhost:8000`, install on `RFCY71B21YK`, retain `adb reverse tcp:8000 tcp:8100`, and verify an existing daily Flash Session can send a Chat turn, leave, return, and replay the completed answer without changing the Flash count.

- [ ] **Step 5: Commit only Tranche 3 files**

Stage the new plan and exact implementation/test files. Do not stage existing Pen/library/capture-page changes. Commit as:

```text
feat(theme-v2): unify legacy session chat pipeline
```
