# Theme V2 Flash Agent Systematic Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the mature tool-grounded Flash Agent pipeline inside Theme V2, remove the fragile DeepSeek outer-JSON boundary, and remove the legacy recording overlays without breaking hardware capture.

**Architecture:** A Theme V2 compatibility kernel ports the legacy dispatcher, intent normalization, one-shot tool-grounded Skill agents, trusted local MCP execution, tool-event recovery, and deterministic fallbacks. It reuses Theme V2's existing LiteLLM and `InternalMCPRuntime` boundaries rather than adding Google ADK. Theme V2 continues to own durable jobs, MySQL, Session state, SSE, notifications, cards, and idempotency. Mobile keeps all hardware lifecycle code but no longer mounts the two full-screen recording overlays, and offline card files derive capture time from their filename when device metadata is absent.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Pydantic 2, LiteLLM/DeepSeek, FastMCP stdio, pytest, Flutter/Dart, Riverpod.

## Global Constraints

- Work only on `codex/theme-v2-ui-refactor`; do not merge to `main`.
- Preserve unrelated dirty files, including `spec/design/redesignureka.pen`, Theme V2 rollout defaults, and visual failure artifacts.
- Do not import or call the legacy backend at Theme V2 runtime.
- Do not execute old and new mutation paths in parallel.
- Model output cannot choose user, Session, InputTurn, or idempotency scope.
- Tool results are the mutation source of truth; model final text is presentation only.
- A malformed dispatcher response falls back to Notes only after the provider returned; provider/MCP unavailability remains retryable.
- One failed intent cannot cancel successful siblings.
- Custom-Skill fallback cannot run for provider, MCP, database, or lease failures.
- Exact stated time becomes `occurred_at`; fuzzy periods never receive invented clock values.
- No transcript text appears before ASR final.
- Remove only `GlobalListeningOverlay` and `BleFlashOverlay`; keep BLE, ASR, upload, post-record status, and Session loading.
- Do not send real user transcripts to an external model during debugging or automated provider smoke tests.
- Use TDD for every behavioral change and run the focused test before the broad suite.

## File Structure

### New backend files

- `theme_v2_service/app/domains/capture/execution.py`: trusted Flash execution input/output types and error taxonomy.
- `theme_v2_service/app/domains/capture/agent_runner.py`: one-shot LiteLLM tool loop, stable capture call IDs, and defensive tool-event mapping.
- `theme_v2_service/app/domains/capture/skill_factory.py`: built-in and dynamic custom-Skill Agent construction.
- `theme_v2_service/app/domains/capture/json_output.py`: bounded tolerant JSON-object extraction shared by dispatcher and Skill result parsing.
- `theme_v2_service/app/domains/capture/tool_results.py`: tolerant JSON parsing, MCP response unwrapping, tool-ground-truth resolution, and reference normalization.
- `theme_v2_service/skills/flash-*/SKILL.md`: versioned Theme V2 copies of the approved legacy dispatcher and built-in Skill instructions.
- `theme_v2_service/tests/unit/test_flash_agent_runner.py`: event collection and provider-error characterization.
- `theme_v2_service/tests/unit/test_flash_tool_results.py`: parser, tool-result recovery, and fallback characterization.
- `theme_v2_service/tests/evals/test_flash_legacy_parity.py`: frozen cross-skill behavior fixtures.
- `theme_v2_service/scripts/smoke_flash_provider.py`: opt-in synthetic DeepSeek contract smoke test.

### Existing backend files to modify

- `theme_v2_service/app/domains/capture/providers_legacy_flash.py`: replace strict command extraction with the compatibility kernel.
- `theme_v2_service/app/domains/capture/dispatcher.py`: expose tolerant dispatcher decoding and include the bounded output contract.
- `theme_v2_service/app/domains/capture/intent_normalizer.py`: retain stable ordinals/source fragments and safe fallback aliases.
- `theme_v2_service/app/domains/capture/jobs.py`: execute and persist tool-grounded results, sanitize terminal user copy, and keep durable retry semantics.
- `theme_v2_service/app/domains/capture/presenter.py`: present normalized actual MCP references and partial warnings.
- `theme_v2_service/app/jobs/registry.py`: register only the compatibility-kernel provider.
- `theme_v2_service/app/observability.py`: register content-free Flash metrics and safe structured log fields.
- Existing Flash unit/integration/e2e tests: update from command-document fakes to execution-result fakes.

### Mobile files to modify

- `mobile/lib/main.dart`: remove the two overlay imports and mounts only.
- `mobile/lib/ble_flash/flash_file_task.dart`: own parsing of `FYYYYMMDD-HHMMSS.opus` capture time.
- `mobile/lib/ble_flash/flash_file_workflow.dart`: populate missing `createTime` for offline/realtime tasks.
- `mobile/lib/ble_flash/flash_file_status_controller.dart`: reuse the shared filename parser.
- `mobile/lib/timeline/timeline.dart`: retain backend `created_at` for stable mature ordering.
- `mobile/lib/theme_v2/calendar/calendar_models.dart`: restore mature non-Todo capture-time and period-band classification.
- `mobile/test/widget_test.dart`: prove overlay not mounted even while hardware notifiers are on.
- `mobile/test/flash_file_task_test.dart`: prove filename timestamp parsing and serialization.

---

### Task 1: Freeze the real regression and legacy behavior boundaries

**Files:**
- Create: `theme_v2_service/app/domains/capture/json_output.py`
- Create: `theme_v2_service/tests/evals/test_flash_legacy_parity.py`
- Modify: `theme_v2_service/tests/unit/test_flash_dispatcher.py`
- Modify: `theme_v2_service/tests/unit/test_flash_intent_normalizer.py`

**Interfaces:**
- Consumes: current `FlashIntent`, `FlashDispatchResult`, and `normalize_intents()`.
- Produces: `extract_json_object()`, `decode_dispatcher_output()`, and deterministic fixtures used by Tasks 3–6.

- [x] **Step 1: Add failing tolerant-dispatcher characterization tests**

```python
@pytest.mark.parametrize(
    ("content", "expected"),
    [
        ('```json\n{"intents":[{"type":"expense","source_text":"午饭8元"}]}\n```', "expense"),
        ('结果如下：{"intents":[{"type":"contact","source_text":"Alex在Acme"}]}', "contact"),
        ('{"intent_list":[{"type":"notes","source_text":"继续观察"}]}', "notes"),
    ],
)
def test_decode_dispatcher_output_accepts_legacy_deepseek_shapes(content, expected):
    assert decode_dispatcher_output(content, fallback_text="原文")[0].type == expected


def test_decode_dispatcher_output_falls_back_to_notes_after_model_response():
    intents = decode_dispatcher_output("这不是JSON", fallback_text="保留这段原文")
    assert intents == [FlashIntent(type="notes", source_text="保留这段原文")]
```

- [x] **Step 2: Run the dispatcher tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_flash_dispatcher.py
```

Expected: FAIL because `decode_dispatcher_output` does not exist and current parsing rejects prefaced JSON.

- [x] **Step 3: Implement the minimal tolerant dispatcher decoder**

Add `extract_json_object()` to `json_output.py` and
`decode_dispatcher_output()` to `dispatcher.py`. The shared extractor removes
Markdown fences, tries the complete string, then scans balanced JSON-object
candidates from the end. The dispatcher decoder accepts `intents` or the legacy
`intent_list`, validates each item independently, and falls back to one Notes
intent when no usable item remains.

- [x] **Step 4: Add the legacy-parity fixture table**

```python
LEGACY_FLASH_CASES = [
    {"id": "multi_expense_hydration", "text": "昨天早上吃饭8块，昨晚喝水200毫升", "types": ["expense", "hydration"]},
    {"id": "contact_create", "text": "保存Alex，他在Acme做产品", "types": ["contact"]},
    {"id": "contact_update", "text": "Alex的职业改成设计师", "types": ["contact"]},
    {"id": "event_attendee", "text": "明天下午三点到四点和冯总开会", "types": ["event"]},
    {"id": "single_point_todo", "text": "明天下午三点和冯总开会", "types": ["todo"]},
    {"id": "notes_default", "text": "今天突然想到产品应该更安静一点", "types": ["notes"]},
    {"id": "qa_no_write", "text": "拿铁和美式有什么区别", "types": ["qa"]},
]
```

Tests assert normalized types, minimal source fragments, and that `idea`, `misc`, and `other` normalize to `notes`.

- [x] **Step 5: Run the characterization tests and require GREEN**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_flash_dispatcher.py \
  tests/unit/test_flash_intent_normalizer.py \
  tests/evals/test_flash_legacy_parity.py
```

Expected: PASS.

- [x] **Step 6: Commit the characterization boundary**

```bash
git add theme_v2_service/app/domains/capture/json_output.py \
  theme_v2_service/app/domains/capture/dispatcher.py \
  theme_v2_service/tests/evals/test_flash_legacy_parity.py \
  theme_v2_service/tests/unit/test_flash_dispatcher.py \
  theme_v2_service/tests/unit/test_flash_intent_normalizer.py
git commit -m "test(theme-v2): freeze flash legacy parity regressions"
```

### Task 2: Add the one-shot Agent runner and trusted MCP boundary

**Files:**
- Create: `theme_v2_service/app/domains/capture/execution.py`
- Create: `theme_v2_service/app/domains/capture/agent_runner.py`
- Create: `theme_v2_service/tests/unit/test_flash_agent_runner.py`

**Interfaces:**
- Produces: `FlashExecutionContext`, `FlashExecutionItem`, `FlashExecutionResult`, `FlashAgentDefinition`, `AgentRunResult`, `stable_capture_tool_call_id()`, and `run_agent_once()`.
- Consumes: the existing `SessionToolExecutor` and `InternalMCPRuntime` trusted execution boundary.
- Consumes later: Tasks 3–6.

- [x] **Step 1: Add the execution types**

Create exact public types:

```python
@dataclass(frozen=True)
class FlashExecutionContext:
    recording_id: str
    user_id: str
    session_id: str
    input_turn_id: str
    transcript: str
    reference_datetime: datetime
    skills: tuple[CaptureSkill, ...]


@dataclass(frozen=True)
class FlashExecutionItem:
    intent: FlashIntent
    status: Literal["success", "pending_confirmation", "error", "reply"]
    result: dict[str, Any] = field(default_factory=dict)
    tool_events: tuple[dict[str, Any], ...] = ()
    error_code: str | None = None


@dataclass(frozen=True)
class FlashExecutionResult:
    summary: str
    items: tuple[FlashExecutionItem, ...]
    warnings: tuple[str, ...] = ()
    usage_tokens: int = 0
```

Also define `RetryableFlashExecutionError` and `PermanentFlashExecutionError`; only infrastructure/provider exceptions use them.

- [x] **Step 2: Write failing runner and trusted-executor tests**

```python
def test_stable_call_id_ignores_model_generated_call_id():
    first = stable_capture_tool_call_id(
        recording_id="rec-1", intent_ordinal=2,
        tool_name="tool_create_asset", arguments={"payload": "{}"},
    )
    second = stable_capture_tool_call_id(
        recording_id="rec-1", intent_ordinal=2,
        tool_name="tool_create_asset", arguments={"payload": "{}"},
    )
    assert first == second
    assert first.startswith("capture:rec-1:2:tool_create_asset:")


async def test_runner_keeps_all_parallel_tool_results(fake_completion, fake_executor):
    result = await run_agent_once(
        FlashAgentDefinition(name="asset", instruction="create assets"),
        "input", fake_executor, completion=fake_completion,
        model="test", api_key=None, timeout_seconds=10,
        recording_id="rec-1", intent_ordinal=2,
    )
    assert [event["name"] for event in result.tool_events] == [
        "tool_create_asset", "tool_create_contact"
    ]
```

- [x] **Step 3: Run focused tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_flash_agent_runner.py
```

Expected: tests FAIL because the direct runner contract is not implemented.

- [x] **Step 4: Implement the defensive one-shot LiteLLM tool runner**

Implement `FlashAgentDefinition`, `AgentRunResult(text, tool_events, usage_tokens)`, and a bounded LiteLLM tool loop. Filter the existing MCP OpenAI tool definitions by the Agent allowlist, execute each round's tool calls concurrently through `SessionToolExecutor`, preserve request order when recording results, and keep all tool request/response events. Provider or MCP-runtime unavailability is retryable; ordinary domain rejections remain tool results.

Ignore the model-generated call ID for mutation idempotency. Canonicalize the tool's model arguments with sorted JSON and derive:

```python
digest = sha256(
    json.dumps(args_without_trusted_fields, sort_keys=True, ensure_ascii=False).encode()
).hexdigest()[:20]
tool_call_id = f"capture:{recording_id}:{intent_ordinal}:{tool_name}:{digest}"
```

`SessionToolExecutor` continues to inject trusted `user_id`, `session_id`, and `source_input_turn_id` when it calls `InternalMCPRuntime`; none of those fields are exposed in model-controlled tool arguments.

- [x] **Step 5: Keep the existing local MCP lifecycle**

Use the current app-owned `InternalMCPRuntime` and `SessionToolExecutor`. Do not create a second subprocess manager, do not add Google ADK, and do not alter FastAPI lifespan ownership.

- [x] **Step 6: Run focused tests and require GREEN**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_flash_agent_runner.py \
  tests/unit/test_session_tools.py \
  tests/integration/test_internal_mcp_stdio.py
```

Expected: PASS.

- [x] **Step 7: Commit the runner boundary**

```bash
git add theme_v2_service/app/domains/capture/execution.py \
  theme_v2_service/app/domains/capture/agent_runner.py \
  theme_v2_service/tests/unit/test_flash_agent_runner.py \
  docs/superpowers/specs/2026-08-06-theme-v2-flash-agent-systematic-recovery-design.md \
  docs/superpowers/plans/2026-08-06-theme-v2-flash-agent-systematic-recovery.md
git commit -m "feat(theme-v2): restore tool-grounded flash agent runner"
```

### Task 3: Port the dispatcher and built-in/dynamic Skill factory

**Files:**
- Create: `theme_v2_service/app/domains/capture/skill_factory.py`
- Create: `theme_v2_service/skills/flash-dispatcher/SKILL.md`
- Create: `theme_v2_service/skills/flash-todo-skill/SKILL.md`
- Create: `theme_v2_service/skills/flash-event-skill/SKILL.md`
- Create: `theme_v2_service/skills/flash-expense-skill/SKILL.md`
- Create: `theme_v2_service/skills/flash-contact-skill/SKILL.md`
- Create: `theme_v2_service/skills/flash-notes-skill/SKILL.md`
- Create: `theme_v2_service/skills/flash-qa-skill/SKILL.md`
- Modify: `theme_v2_service/app/domains/capture/dispatcher.py`
- Modify: `theme_v2_service/app/domains/capture/intent_normalizer.py`
- Modify: `theme_v2_service/tests/unit/test_flash_dispatcher.py`
- Modify: `theme_v2_service/tests/unit/test_flash_intent_normalizer.py`

**Interfaces:**
- Consumes: `FlashAgentDefinition` and `run_agent_once()` from Task 2.
- Produces: `make_dispatcher_agent()`, `make_builtin_skill_agent()`, `make_custom_skill_agent()`, and `decode_dispatcher_output()`.

- [x] **Step 1: Copy the approved runtime instructions**

Port the exact current content from these legacy source files into the matching Theme V2 paths:

```text
backend/skills/flash-dispatcher/SKILL.md
backend/skills/flash-todo-skill/SKILL.md
backend/skills/flash-event-skill/SKILL.md
backend/skills/flash-expense-skill/SKILL.md
backend/skills/flash-contact-skill/SKILL.md
backend/skills/flash-notes-skill/SKILL.md
backend/skills/flash-qa-skill/SKILL.md
```

Do not port `idea` or `misc`. Adapt only obsolete product references: external Task execution stays out, and Report guidance must match the current Theme V2 Report container.

- [x] **Step 2: Complete the dispatcher contract around the Task 1 decoder**

Retain the Task 1 bounded decoder as the only parsing path:

```python
def decode_dispatcher_output(content: str, *, fallback_text: str) -> list[FlashIntent]:
    payload = extract_json_object(content)
    raw = payload.get("intents") if payload else None
    if raw is None and payload:
        raw = payload.get("intent_list")
    if not isinstance(raw, list):
        return [FlashIntent(type="notes", source_text=fallback_text)]
    intents = []
    for item in raw[:20]:
        try:
            intents.append(FlashIntent.model_validate(item))
        except Exception:
            continue
    return intents or [FlashIntent(type="notes", source_text=fallback_text)]
```

The dispatcher prompt also includes `FlashDispatchResult.model_json_schema()` as guidance, while tolerant parsing remains mandatory.

- [x] **Step 3: Implement the factory**

`make_builtin_skill_agent()` loads only the six supported built-in Skill documents and returns a `FlashAgentDefinition` with an explicit MCP tool allowlist. `make_custom_skill_agent()` builds the old best-effort extraction prompt from `CaptureSkill.schema_definition`, with all fields optional at Agent-write time and no invented values.

`run_agent_once()` owns the LiteLLM model/API configuration so DeepSeek keeps native tool calling. Dispatcher returns a tool-less `FlashAgentDefinition`.

- [x] **Step 4: Run characterization tests and require GREEN**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_flash_dispatcher.py \
  tests/unit/test_flash_intent_normalizer.py
```

Expected: all plain, fenced, prefaced, alias, unknown-type, scheduled-custom, and multi-expense cases PASS.

- [x] **Step 5: Commit the Skill runtime**

```bash
git add theme_v2_service/app/domains/capture/skill_factory.py \
  theme_v2_service/app/domains/capture/dispatcher.py \
  theme_v2_service/app/domains/capture/intent_normalizer.py \
  theme_v2_service/skills \
  theme_v2_service/tests/unit/test_flash_dispatcher.py \
  theme_v2_service/tests/unit/test_flash_intent_normalizer.py
git commit -m "feat(theme-v2): port legacy flash skills"
```

### Task 4: Restore tool-ground-truth resolution and safe fallbacks

**Files:**
- Create: `theme_v2_service/app/domains/capture/tool_results.py`
- Create: `theme_v2_service/tests/unit/test_flash_tool_results.py`
- Modify: `theme_v2_service/app/domains/capture/pipeline.py`
- Modify: `theme_v2_service/tests/unit/test_flash_pipeline.py`

**Interfaces:**
- Consumes: `AgentRunResult`, `FlashExecutionItem`, `FlashIntent`, and `SessionToolExecutor`.
- Produces: `resolve_agent_result()`, `run_custom_skill_fallback()`, `run_event_to_todo_fallback()`, and `aggregate_execution()`.

- [x] **Step 1: Write failing ground-truth and partial-success tests**

```python
def test_successful_tool_result_wins_over_malformed_final_text():
    resolved = resolve_agent_result(
        intent=FlashIntent(type="expense", source_text="午饭8元"),
        final_text="not json",
        tool_events=[{"name": "tool_create_asset", "args": {}, "response": {"ok": True, "asset_id": "a1", "user_skill_name": "expense", "payload": {"amount": 8}}}],
    )
    assert resolved.status == "success"
    assert resolved.result["asset_id"] == "a1"


def test_rejected_sibling_does_not_erase_success():
    aggregate = aggregate_execution([success_item, rejected_item])
    assert aggregate.summary == "已完成 1 项，另有 1 项未完成。"
    assert aggregate.warnings == ("intent_tool_rejected",)
```

Also cover FastMCP `structuredContent.result`, `content[0].text`, query snapshots, QA reply, contact candidates, and Event-to-Todo fallback.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_flash_tool_results.py tests/unit/test_flash_pipeline.py
```

Expected: FAIL because tool-ground-truth resolver does not exist.

- [x] **Step 3: Implement tolerant result extraction**

Reuse Task 1 `extract_json_object()` for final Agent text.
`unwrap_mcp_response()` prefers `structuredContent.result`, then JSON
`content[].text`, then an already-normalized dict.

`resolve_agent_result()` checks successful tool events first. It accepts a valid final JSON only when it does not claim an unobserved mutation. Contact multiple-candidate final JSON becomes `pending_confirmation`; QA final JSON becomes `reply` with no write.

- [x] **Step 4: Implement deterministic fallbacks through MCP**

Custom fallback creates one `CaptureRecordCommand(kind="asset", operation="create")` from grounded fields/source text and calls the existing trusted `execute_capture_command()` once. It runs only for an Agent response/extraction miss.

Event fallback calls Todo only when the Event Agent returned without a real `event_id`; provider/MCP exceptions propagate instead.

- [x] **Step 5: Implement stable partial aggregation**

Aggregation preserves normalized intent order, emits cards only from actual results, joins QA replies separately, and returns generic warning codes rather than provider strings. It never calls an LLM.

- [x] **Step 6: Run focused tests and require GREEN**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_flash_tool_results.py \
  tests/unit/test_flash_pipeline.py \
  tests/unit/test_flash_skills.py \
  tests/unit/test_contact_flash_skill.py
```

Expected: PASS.

- [x] **Step 7: Commit tool-ground-truth recovery**

```bash
git add theme_v2_service/app/domains/capture/tool_results.py \
  theme_v2_service/app/domains/capture/pipeline.py \
  theme_v2_service/tests/unit/test_flash_tool_results.py \
  theme_v2_service/tests/unit/test_flash_pipeline.py
git commit -m "fix(theme-v2): ground flash results in MCP execution"
```

### Task 5: Replace strict provider execution and persist safe Session outcomes

**Files:**
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `theme_v2_service/app/domains/capture/presenter.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Modify: `theme_v2_service/app/main.py`
- Modify: `theme_v2_service/app/observability.py`
- Modify: `theme_v2_service/tests/unit/test_flash_dispatcher.py`
- Modify: `theme_v2_service/tests/unit/test_capture_presenter.py`
- Modify: `theme_v2_service/tests/unit/test_job_registry.py`
- Modify: `theme_v2_service/tests/unit/test_observability.py`
- Modify: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Modify: `theme_v2_service/tests/integration/test_capture_session_materialization.py`
- Modify: `theme_v2_service/tests/e2e/test_hardware_capture_flow.py`

**Interfaces:**
- Consumes: all Task 2–4 interfaces.
- Produces: `LiteLLMLegacyFlashProvider.execute(context) -> FlashExecutionResult` and `capture_process_handler()` persistence of already-executed MCP results.

- [x] **Step 1: Add failing job integration cases**

Add tests proving:

```python
assert recording.process_status == "done"
assert recording.result_records_json[0]["asset_id"] == "expense-1"
assert agent_message.status == "done"
assert "incompatible JSON" not in agent_message.text
assert asset_count == 1  # retry/idempotency
```

Add a partial case with one success and one error card/warning, and an exhausted provider transport case where `recording.error_message` retains an internal code but `agent_message.text == "这条闪念暂时没有整理完成，可以重试"`.

- [x] **Step 2: Run focused integration tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/integration/test_capture_jobs.py \
  tests/integration/test_capture_session_materialization.py
```

Expected: FAIL because the job still requires `CaptureAgentResult` commands and exposes raw exception text.

- [x] **Step 3: Replace provider orchestration**

`LiteLLMLegacyFlashProvider.execute()` performs:

```text
run dispatcher -> decode/normalize -> gather(return_exceptions=True) Skill runs
-> resolve tool events -> run only safe deterministic fallbacks -> aggregate
```

`asyncio.gather(return_exceptions=True)` is required so a sibling exception is classified rather than cancelling completed siblings. Infrastructure exceptions remain retryable when no complete safe aggregate can be persisted.

- [x] **Step 4: Persist execution facts without replaying tools**

Replace `_persist_capture_result()` with `_persist_flash_execution()` that converts each `FlashExecutionItem.result` into asset/event/contact/pending/error references, passes them through `present_capture_references()`, and updates the existing Agent message.

Do not call `LegacyFlashPipeline` or `SessionToolExecutor` for successful items: their MCP tools have already executed.

- [x] **Step 5: Sanitize terminal Session failure**

Persist the internal error code/message on `CaptureRecording.error_message`, but always set failed Agent message text to:

```text
这条闪念暂时没有整理完成，可以重试
```

Keep the failure on that turn only; do not append a session-wide bottom banner.

- [x] **Step 6: Close runtime and remove obsolete provider path**

Register only the new `LiteLLMLegacyFlashProvider` execution contract. Keep the existing app-owned `InternalMCPRuntime` lifespan unchanged. Delete the obsolete strict `_complete_model(... schema=CaptureAgentResult)` path and tests that assert perfect outer JSON.

- [x] **Step 7: Add content-free Flash observability**

Register these metrics in `observability.py`:

```python
"flash_dispatch_fallback_total",
"flash_intent_total",
"flash_intent_failed_total",
"flash_tool_recovered_total",
"flash_custom_fallback_total",
"flash_capture_partial_total",
"flash_capture_failed_total",
```

Permit only `recording_id`, `job_id`, `stage`, `status`, `error_code`,
`reason_code`, `intent_type`, `provider`, `model`, and `attempt` as safe Flash
log fields. Provider/kernel logs must never contain transcript, source text,
messages, raw response, prompt, or tool payload. Extend
`test_observability.py` to prove those fields are stripped.

- [x] **Step 8: Run backend Flash suites and require GREEN**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/unit/test_flash_agent_runner.py \
  tests/unit/test_flash_dispatcher.py \
  tests/unit/test_flash_intent_normalizer.py \
  tests/unit/test_flash_tool_results.py \
  tests/unit/test_flash_pipeline.py \
  tests/unit/test_flash_skills.py \
  tests/unit/test_contact_flash_skill.py \
  tests/unit/test_capture_presenter.py \
  tests/unit/test_job_registry.py \
  tests/unit/test_observability.py \
  tests/integration/test_internal_mcp_stdio.py \
  tests/integration/test_internal_mcp_tools.py \
  tests/integration/test_capture_jobs.py \
  tests/integration/test_capture_session_materialization.py \
  tests/e2e/test_hardware_capture_flow.py
```

Expected: PASS.

- [x] **Step 9: Commit the job cutover**

```bash
git add theme_v2_service/app theme_v2_service/tests
git commit -m "fix(theme-v2): complete legacy flash agent cutover"
```

### Task 6: Close legacy-parity evals and add the synthetic provider smoke test

**Files:**
- Modify: `theme_v2_service/tests/evals/test_flash_legacy_parity.py`
- Create: `theme_v2_service/scripts/smoke_flash_provider.py`
- Modify: `docs/superpowers/plans/2026-08-06-theme-v2-legacy-agent-migration-tranche-4.md`

**Interfaces:**
- Consumes: production compatibility kernel.
- Produces: explicit non-production DeepSeek smoke command and checked legacy-eval gate.

- [x] **Step 1: Make parity fixtures execute the production kernel with fake Agent runs**

Each case supplies dispatcher and Skill responses/tool events, then asserts exact normalized types, persisted reference kinds, no duplicate IDs, correct period/occurred-at behavior, and generic failure copy.

- [x] **Step 2: Add an opt-in synthetic provider script**

The script requires both `CAPTURE_AGENT_MODEL` and `CAPTURE_AGENT_API_KEY`, creates an isolated test user/Session, and uses only these invented inputs:

```python
SYNTHETIC_INPUTS = (
    "今天午饭花了28元",
    "昨天早上吃饭8元，昨晚喝水200毫升",
    "刚跑完两公里，配速六分半",
    "拿铁和美式有什么区别",
)
```

It prints stage/status/reference kinds only, never provider raw output or transcript content. It exits non-zero on any failed input or duplicate entity ID.

- [x] **Step 3: Run deterministic parity tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/evals/test_flash_legacy_parity.py
```

Expected: PASS.

- [x] **Step 4: Run the opt-in provider smoke only with configured test credentials**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app api \
  python scripts/smoke_flash_provider.py
```

Expected: four synthetic cases report success or safe reply, with no raw content output. If credentials are unavailable, record the gate as pending rather than weakening it.

Verified on 2026-08-06 against the configured Theme V2 provider: four synthetic
cases completed as asset; asset+asset; asset; reply. The script cleaned the
isolated smoke user after execution and emitted no provider response content.

- [x] **Step 5: Mark only the legacy-parity checklist step complete**

Change Tranche 4 Task 5 Step 2 to checked only after Step 3 passes. Leave phone acceptance unchecked until Task 8.

- [x] **Step 6: Commit eval acceptance**

```bash
git add theme_v2_service/tests/evals/test_flash_legacy_parity.py \
  theme_v2_service/scripts/smoke_flash_provider.py \
  docs/superpowers/plans/2026-08-06-theme-v2-legacy-agent-migration-tranche-4.md
git commit -m "test(theme-v2): close flash legacy parity gate"
```

### Task 7: Remove recording overlays and restore offline capture time

**Files:**
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/ble_flash/flash_file_task.dart`
- Modify: `mobile/lib/ble_flash/flash_file_workflow.dart`
- Modify: `mobile/lib/ble_flash/flash_file_status_controller.dart`
- Modify: `mobile/lib/timeline/timeline.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_models.dart`
- Modify: `mobile/test/widget_test.dart`
- Modify: `mobile/test/flash_file_task_test.dart`
- Modify: `mobile/test/timeline_theme_v2_service_regression_test.dart`
- Modify: `mobile/test/theme_v2/calendar/calendar_time_layout_test.dart`

**Interfaces:**
- Produces: `DateTime? captureDateTimeFromFlashFileName(String)`, `int? captureEpochSecondsFromFlashFileName(String)`, and stable Timeline ordering by `effectiveAt`, `createdAt`, then ID.
- Consumes: existing `FlashFileTask.createTime` and payload `capture_started_at`.

- [ ] **Step 1: Add failing filename and overlay tests**

```dart
test('flash filename preserves original local capture second', () {
  final value = captureDateTimeFromFlashFileName('F20260805-231407.opus');
  expect(value, DateTime(2026, 8, 5, 23, 14, 7));
  expect(captureEpochSecondsFromFlashFileName('invalid.opus'), isNull);
});

testWidgets('hardware flags do not mount legacy full-screen overlays', (tester) async {
  listeningNotifier.value = true;
  BleFlashManager.instance.isFlashing.value = true;
  addTearDown(() {
    listeningNotifier.value = false;
    BleFlashManager.instance.isFlashing.value = false;
  });
  await tester.pumpWidget(const ProviderScope(child: EurekaApp()));
  await tester.pump();
  expect(find.byType(GlobalListeningOverlay), findsNothing);
  expect(find.byType(BleFlashOverlay), findsNothing);
});

test('contact capture fallback stays in the clock flow', () {
  final contact = record(
    kind: 'contact',
    at: DateTime(2026, 8, 6, 9, 42),
    hasClockTime: false,
  );
  expect(contact.timing, CalendarRecordTiming.timed);
});

test('fuzzy period wins over capture fallback clock', () {
  final expense = record(
    skillName: 'expense',
    at: DateTime(2026, 8, 6, 9, 42),
    period: '晚上',
    hasClockTime: false,
  );
  expect(expense.timing, CalendarRecordTiming.untimed);
});
```

- [ ] **Step 2: Run focused Flutter tests and verify RED**

Run:

```bash
cd mobile && flutter test \
  test/flash_file_task_test.dart \
  test/widget_test.dart \
  test/timeline_theme_v2_service_regression_test.dart \
  test/theme_v2/calendar/calendar_time_layout_test.dart
```

Expected: filename helper is missing and overlays are found.

- [ ] **Step 3: Implement one shared strict filename parser**

```dart
DateTime? captureDateTimeFromFlashFileName(String fileName) {
  final match = RegExp(
    r'^F(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.opus$',
    caseSensitive: false,
  ).firstMatch(fileName.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.tryParse(match.group(i)! )];
  if (parts.any((value) => value == null)) return null;
  final parsed = DateTime(parts[0]!, parts[1]!, parts[2]!, parts[3]!, parts[4]!, parts[5]!);
  return parsed.year == parts[0] &&
          parsed.month == parts[1] &&
          parsed.day == parts[2] &&
          parsed.hour == parts[3] &&
          parsed.minute == parts[4] &&
          parsed.second == parts[5]
      ? parsed
      : null;
}

int? captureEpochSecondsFromFlashFileName(String fileName) =>
    captureDateTimeFromFlashFileName(fileName)?.millisecondsSinceEpoch ~/ 1000;
```

Use the helper in `FlashFileStatusController` and initialize `_newTask(...).createTime`. An explicit device `createTime` continues to win through `copyWith`.

- [ ] **Step 4: Restore mature Timeline classification and stable ordering**

Add `DateTime? createdAt` as an optional constructor parameter and store
`this.createdAt = createdAt ?? effectiveAt`, so existing fixtures remain source
compatible. Parse backend `created_at` when present. Sort with:

```dart
final effective = a.effectiveAt.compareTo(b.effectiveAt);
if (effective != 0) return effective;
final created = a.createdAt.compareTo(b.createdAt);
if (created != 0) return created;
return a.id.compareTo(b.id);
```

For Calendar classification, keep Event and Todo rules unchanged. Input turns
remain untimed. For other records, `period` wins and stays in its fuzzy band;
otherwise an explicit clock or a non-midnight effective/capture fallback is
timed. A date-only local midnight remains untimed.

- [ ] **Step 5: Remove only overlay presentation**

Remove the two overlay imports and their two `ValueListenableBuilder<bool>` branches from `EurekaApp.builder`. Keep `BleFlashManager.instance.start()`, `FlashFileWorkflow`, `listeningNotifier`, and all post-record status code unchanged.

- [ ] **Step 6: Run focused tests and analyze changed Dart**

Run:

```bash
cd mobile && flutter test \
  test/flash_file_task_test.dart \
  test/widget_test.dart \
  test/timeline_theme_v2_service_regression_test.dart \
  test/theme_v2/calendar/calendar_time_layout_test.dart
cd mobile && flutter analyze \
  lib/main.dart \
  lib/ble_flash/flash_file_task.dart \
  lib/ble_flash/flash_file_workflow.dart \
  lib/ble_flash/flash_file_status_controller.dart \
  lib/timeline/timeline.dart \
  lib/theme_v2/calendar/calendar_models.dart \
  test/widget_test.dart \
  test/flash_file_task_test.dart \
  test/timeline_theme_v2_service_regression_test.dart \
  test/theme_v2/calendar/calendar_time_layout_test.dart
```

Expected: tests PASS and analyzer reports no issues.

- [ ] **Step 7: Commit mobile capture parity**

```bash
git add mobile/lib/main.dart \
  mobile/lib/ble_flash/flash_file_task.dart \
  mobile/lib/ble_flash/flash_file_workflow.dart \
  mobile/lib/ble_flash/flash_file_status_controller.dart \
  mobile/lib/timeline/timeline.dart \
  mobile/lib/theme_v2/calendar/calendar_models.dart \
  mobile/test/widget_test.dart \
  mobile/test/flash_file_task_test.dart \
  mobile/test/timeline_theme_v2_service_regression_test.dart \
  mobile/test/theme_v2/calendar/calendar_time_layout_test.dart
git commit -m "fix(mobile): simplify hardware capture presentation"
```

### Task 8: Full acceptance, Theme V2 install, and branch handoff

**Files:**
- Modify: `docs/superpowers/plans/2026-08-06-theme-v2-legacy-agent-migration-tranche-4.md`
- Modify only if a real acceptance failure requires it: files from Tasks 1–7.

**Interfaces:**
- Consumes: complete Theme V2 backend/mobile repair.
- Produces: verified Theme V2 build on the connected phone and closed Tranche 4 phone gate.

- [ ] **Step 1: Run the complete focused backend acceptance**

Run the Task 5 Step 8 suite plus:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q \
  tests/contract/test_capture_api.py \
  tests/contract/test_capture_sse.py \
  tests/contract/test_session_api.py \
  tests/contract/test_timeline_api.py \
  tests/evals/test_flash_legacy_parity.py
```

Expected: PASS.

- [ ] **Step 2: Run the relevant complete Flutter acceptance**

Run:

```bash
cd mobile && flutter test \
  test/widget_test.dart \
  test/flash_file_task_test.dart \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_page_test.dart \
  test/timeline_theme_v2_service_regression_test.dart \
  test/theme_v2/calendar/calendar_time_layout_test.dart
```

Expected: PASS.

- [ ] **Step 3: Rebuild only the isolated Theme V2 stack**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml up -d --build mysql api worker
docker compose -f docker-compose.theme-v2.yml ps
```

Expected: Theme V2 MySQL, API, and worker are healthy; no legacy backend container is used.

- [ ] **Step 4: Build and install the Theme V2 app**

Run:

```bash
cd mobile && flutter build apk --debug
```

Install only `mobile/build/app/outputs/flutter-apk/app-debug.apk`, configure `adb reverse tcp:8000 tcp:8000`, force-stop `com.eureka.mindapp`, and launch that package. Confirm Theme V2 navigation before testing recording.

- [ ] **Step 5: Run ring real-device acceptance**

Record synthetic content that creates two distinct intents. Confirm:

- no full-screen listening animation;
- transcript appears in today's physical Flash Session after ASR final;
- one Agent loading state appears and resolves without refresh;
- two correct records/cards exist exactly once;
- notification opens the same Session;
- Flash count increases by one;
- leaving and returning preserves the result;
- no `incompatible JSON` or session-wide failure banner is visible.

- [ ] **Step 6: Run card realtime and offline acceptance**

Confirm realtime capture works once. Then reconnect with a test offline file named in `FYYYYMMDD-HHMMSS.opus` format and verify the backend receives its original capture time, relative language uses that reference, and Timeline placement matches the old rules.

- [ ] **Step 7: Close the phone acceptance gate**

Check Tranche 4 Task 5 Step 3 only after Steps 5–6 pass. Record device/package/build timestamp in the plan without storing transcript content.

- [ ] **Step 8: Review worktree and create the final repair commit if acceptance required changes**

```bash
git status --short
git diff --check
git diff --stat
```

Stage only files owned by this plan. Do not include `redesignureka.pen`, rollout defaults unless deliberately changed by this repair, or failure artifacts.

- [ ] **Step 9: Confirm remote before push**

Run:

```bash
git remote get-url origin
git branch --show-current
```

Expected: `https://github.com/IgniteTheSpark/Eureka-Assistant.git` and `codex/theme-v2-ui-refactor`. Push only this branch after explicit confirmation; do not merge `main`.
