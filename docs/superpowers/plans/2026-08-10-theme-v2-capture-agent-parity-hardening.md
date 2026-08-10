# Theme V2 Capture Agent Parity Hardening Implementation Plan

> **For Codex:** Execute this plan with the `executing-plans` skill and use test-driven development for every behavior change.

**Goal:** Make Theme V2 capture reliably understand, query, create, update, and delete user information while preserving one Flash count per hardware input and one root asset per atomic mutation intent.

**Architecture:** Keep the current LiteLLM agent loop and FastMCP boundary. Add first-class operation semantics before routing, inject identity and temporal data only through a small trusted runtime context, and move deterministic validation/canonicalization to the MCP execution boundary. Typed domain tools normalize once and share a generic persistence kernel. Avoid a general contract registry and avoid a second temporal protocol.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy async, FastMCP, LiteLLM, MySQL, Redis/RQ, pytest, Docker Compose.

**Design source:** `docs/superpowers/specs/2026-08-10-theme-v2-capture-agent-parity-hardening-design.md`

---

## Guardrails

- Work only on the isolated Theme V2 service and app; do not start or modify the legacy shared Docker stack.
- Preserve the current dirty changes in `tool_results.py`, session tool execution, MCP Todo signature, and their tests; reconcile them into the final architecture rather than overwriting them.
- Do not introduce a global `ToolContractRegistry` or a new `TemporalFacts` model.
- Do not make generic `create_asset` the normal route for Todo or Notes.
- Never let update/delete fall back to create.
- Never report a read-only query as “completed one item.”
- Do not auto-delete historical duplicate assets in this implementation; prevent new duplicates and emit diagnostics.
- Do not merge to `main` or push unless the user separately asks.

## Verification cadence

For each task:

1. Add or change the narrowest test first.
2. Run it and confirm the intended failure.
3. Implement the minimum complete behavior.
4. Run the narrow test, then its containing unit/integration suite.
5. Commit the coherent task only when the worktree can be staged without including unrelated user changes.

---

### Task 1: Introduce first-class operation and atomic-intent identity

**Files:**

- Modify: `theme_v2_service/app/domains/capture/dispatcher.py`
- Modify: `theme_v2_service/app/domains/capture/intent_normalizer.py`
- Modify: `theme_v2_service/app/domains/capture/execution.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Test: `theme_v2_service/tests/unit/test_flash_dispatcher.py`
- Test: `theme_v2_service/tests/unit/test_flash_intent_normalizer.py`
- Test: `theme_v2_service/tests/unit/test_legacy_flash_provider.py`

**Steps:**

1. Add failing dispatcher tests for `create`, `query`, `update`, and `delete`, including:
   - “明天提醒我吃药” -> Todo/create.
   - “帮我看看最近花了多少钱” -> Expense/query.
   - “把刚刚账单从 10 块改成 8 块” -> Expense/update.
   - “删除刚刚那个代办” -> Todo/delete.
2. Extend `FlashIntent` with `operation`, stable `intent_id`, and deterministic `ordinal`; default missing model output to create only when the source text is genuinely mutating and not query/update/delete.
3. Update the dispatcher schema and prompt so operation is part of the model contract, while retaining tolerant parsing.
4. Preserve operation and identity through normalization, custom-skill routing, fallbacks, and `FlashExecutionItem`.
5. Add a regression test proving one recording containing two expenses yields two create intents with distinct IDs/ordinals while the provider still owns one Flash input turn.
6. Run:
   - `pytest theme_v2_service/tests/unit/test_flash_dispatcher.py -q`
   - `pytest theme_v2_service/tests/unit/test_flash_intent_normalizer.py -q`
   - `pytest theme_v2_service/tests/unit/test_legacy_flash_provider.py -q`

**Acceptance:** Downstream code never has to infer operation from whether a tool happened to mutate.

### Task 2: Make result semantics operation-aware

**Files:**

- Modify: `theme_v2_service/app/domains/capture/tool_results.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/capture/skill_factory.py`
- Modify: `theme_v2_service/app/domains/capture/agent_runner.py`
- Test: `theme_v2_service/tests/unit/test_flash_tool_results.py`
- Test: `theme_v2_service/tests/unit/test_flash_agent_runner.py`
- Test: `theme_v2_service/tests/unit/test_legacy_flash_provider.py`

**Steps:**

1. Add failing tests that assert:
   - query succeeds only with a grounded read result and returns a reply, not a mutation receipt;
   - create/update/delete succeeds only when the corresponding tool effect is observed;
   - an update response produced without an update effect is an error;
   - partial multi-intent execution reports exact successes/failures.
2. Define a small operation-effect policy next to result resolution; map operations to allowed tool effects rather than creating a general registry.
3. Carry structured tool effect metadata from `SessionToolExecutor`/agent runner into result resolution.
4. Allow read tools in query agents and require the final answer to be grounded in returned results.
5. Generate the user summary from execution items:
   - query-only -> answer only;
   - mutations -> completed/failed counts;
   - mixed -> answer plus exact mutation summary.
6. Run the three focused test files, then `pytest theme_v2_service/tests/unit/test_flash_*.py -q`.

**Acceptance:** “看看最近花了多少钱” creates no asset and never says “已完成 1 项”.

### Task 3: Resolve mutation targets deterministically

**Files:**

- Create: `theme_v2_service/app/domains/capture/target_resolver.py`
- Modify: `theme_v2_service/app/domains/capture/skill_factory.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/internal_mcp/server.py`
- Modify: `theme_v2_service/app/internal_mcp/tools.py`
- Test: `theme_v2_service/tests/unit/test_capture_target_resolver.py`
- Test: `theme_v2_service/tests/unit/test_session_tools.py`
- Test: `theme_v2_service/tests/integration/test_internal_mcp_tools.py`

**Steps:**

1. Add target-resolution tests for the ordered policy:
   - explicit asset ID;
   - latest root entity from the prior completed InputTurn in the same physical session;
   - latest prior result card;
   - unique exact title/field match;
   - one safe owner-scoped candidate;
   - ambiguous/no match -> clarification/error, never create.
2. Implement a read-only resolver that returns a typed resolution outcome and records the resolution source.
3. Resolve target IDs before the mutation agent invokes MCP; pass the resolved ID as an ordinary model-visible mutation argument while user/session identity remains trusted.
4. Add/update typed MCP mutation tools as needed so expense, Todo, Note, Event, and custom assets can update/delete by resolved ID.
5. Reject any mutation whose target is outside the trusted user scope.
6. Add an end-to-end test: create Expense 10 -> next Flash “改成8” -> same asset ID now 8, one new InputTurn, zero new assets.

**Acceptance:** Correction is a new Flash turn but modifies exactly one existing root asset.

### Task 4: Centralize trusted MCP context and audit contracts

**Files:**

- Modify: `theme_v2_service/app/internal_mcp/runtime.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/internal_mcp/server.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/app/internal_mcp/contracts.py`
- Test: `theme_v2_service/tests/unit/test_session_tools.py`
- Test: `theme_v2_service/tests/unit/test_internal_mcp_server.py`
- Test: `theme_v2_service/tests/unit/test_internal_mcp_contracts.py`

**Steps:**

1. Add failing tests for a common trusted context containing:
   - `user_id`, `session_id`, `input_turn_id`, `tool_call_id`;
   - `reference_datetime`, `timezone_name`.
2. Move all trusted injection into the internal MCP runtime; remove per-tool/session-executor special cases, including the temporary Todo-only reference-time injection.
3. Add a small `TRUSTED_ARGS_BY_TOOL` mapping only for exceptional tool subsets; common trusted fields remain centralized.
4. Build a read-only contract audit from FastMCP function signatures and exposed tool schemas. Check at startup/readiness that:
   - every trusted argument exists in the callable signature;
   - trusted arguments are hidden from the model schema;
   - every visible required schema field maps to the callable;
   - no unexpected required callable field is omitted.
5. Add test-only synthetic invocations for each registered tool to catch runtime/signature drift without mutating production data.
6. Fail readiness with an actionable contract error rather than waiting for a user capture.
7. Run focused unit tests and `pytest theme_v2_service/tests/integration/test_internal_mcp_tools.py -q`.

**Acceptance:** Adding a trusted argument can no longer make FastMCP reject an otherwise valid user capture at runtime.

### Task 5: Split typed domain creation from generic persistence

**Files:**

- Modify: `theme_v2_service/app/internal_mcp/tools.py`
- Modify: `theme_v2_service/app/internal_mcp/server.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Create: `theme_v2_service/app/domains/assets/persistence.py`
- Modify: `theme_v2_service/app/domains/capture/skill_factory.py`
- Test: `theme_v2_service/tests/unit/test_internal_mcp_server.py`
- Test: `theme_v2_service/tests/integration/test_internal_mcp_tools.py`
- Test: `theme_v2_service/tests/unit/test_asset_service.py`

**Steps:**

1. Add tests proving:
   - Todo creation uses `tool_create_todo` and is normalized once;
   - Notes creation uses `tool_create_note`;
   - Expense and custom Skill creation may use generic `tool_create_asset`;
   - generic creation rejects Todo and Notes machine types.
2. Extract a persistence kernel responsible only for validation, provenance, insertion, indexing, triggers, and outbox work.
3. Keep domain normalization in typed tools, then pass canonical fields to the persistence kernel.
4. Remove the current Todo path that normalizes at `_create_todo` and again inside `asset_service.create_asset` using a different clock.
5. Update built-in agent tool allowlists and prompts to use typed tools.
6. Run internal MCP integration tests and asset-service tests.

**Acceptance:** A Todo has one canonical normalization pass and one persistence pass.

### Task 6: Make custom Skill routing stable and user-specific

**Files:**

- Modify: `theme_v2_service/app/domains/capture/execution.py`
- Modify: `theme_v2_service/app/domains/capture/intent_normalizer.py`
- Modify: `theme_v2_service/app/domains/capture/skill_factory.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Test: `theme_v2_service/tests/unit/test_flash_intent_normalizer.py`
- Test: `theme_v2_service/tests/unit/test_flash_skill_factory.py`
- Test: `theme_v2_service/tests/unit/test_legacy_flash_provider.py`

**Steps:**

1. Extend `CaptureSkill` with the stable `UserSkill.id` and matching metadata.
2. Add routing tests for exact machine name, case-insensitive machine name, exact display name, unique prefix, and semantic catalog match.
3. Add a collision test proving built-ins stay reserved while a confident custom Skill match wins over the generic Notes fallback.
4. Supply the dispatcher a compact user Skill catalog containing stable ID, machine name, display name, description, and field hints.
5. Preserve the stable Skill ID through the intent and generic custom-asset creation call.
6. On ambiguity, return a clear unresolved item rather than silently creating Notes.

**Acceptance:** A user’s “跑步训练” input routes to that custom Skill even when the spoken label is not its exact machine name.

### Task 7: Apply one temporal/domain normalization path to all successful mutations

**Files:**

- Modify: `theme_v2_service/app/domains/capture/temporal.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/capture/pipeline.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/internal_mcp/tools.py`
- Test: `theme_v2_service/tests/unit/test_capture_temporal.py`
- Test: `theme_v2_service/tests/unit/test_legacy_flash_provider.py`
- Test: `theme_v2_service/tests/integration/test_internal_mcp_tools.py`

**Steps:**

1. Add table-driven tests using the trusted Asia/Shanghai reference time for:
   - exact datetime;
   - “昨天早上” -> anchor date + morning period, without invented exact spoken time;
   - “明天晚上9点” -> exact deadline;
   - “明天上午” Todo -> configured period-end deadline;
   - “明天” Todo -> 18:00;
   - “今天” Todo after 18:00 -> tomorrow 18:00;
   - historical Todo -> immediately overdue.
2. Make `extract_temporal_hints(source_text, reference_datetime)` the only capture-level temporal extractor and keep the existing `CaptureTemporalHints` value object.
3. Remove `LegacyFlashPipeline._temporal_hints` and route fallbacks through the shared pure function.
4. Pass source text plus trusted reference/timezone to typed domain tools; canonicalize/fallback/force temporal fields at the execution boundary for both model-success and deterministic fallback paths.
5. Apply the same rule to non-Todo assets: explicit time > date+period > period > creation/reference fallback according to the legacy timeline contract.
6. Verify timeline ordering for Contact creation, yesterday-morning Expense, and timeless Note.

**Acceptance:** The same phrase produces the same stored/timeline time regardless of whether the model supplied a partial datetime.

### Task 8: Make baseline Skill provisioning concurrency-safe

**Files:**

- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/auth/api.py`
- Test: `theme_v2_service/tests/unit/test_asset_service.py`
- Test: `theme_v2_service/tests/integration/test_auth_api.py`
- Test: `theme_v2_service/tests/integration/test_capture_concurrency.py`

**Steps:**

1. Add a concurrency test that launches multiple first-use requests for a new user and asserts one row per baseline `(user_id, machine_name)` without deadlock.
2. Replace query-then-row-insert initialization with one bulk MySQL upsert using the existing unique constraint.
3. Provision baseline Skills immediately after account creation in the same controlled transaction boundary.
4. Retain lazy provisioning for old/test accounts, using the same idempotent bulk operation.
5. Retry only recognized transient deadlock errors with a small bounded backoff; do not hide arbitrary database errors.

**Acceptance:** Concurrent capture/home/assets requests for a new account do not deadlock and never create duplicate Skills.

### Task 9: Prevent duplicate root mutations per atomic intent

**Files:**

- Modify: `theme_v2_service/app/domains/capture/agent_runner.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/internal_mcp/tools.py`
- Modify: `theme_v2_service/app/domains/assets/models.py`
- Add migration under: `theme_v2_service/alembic/versions/`
- Test: `theme_v2_service/tests/unit/test_flash_agent_runner.py`
- Test: `theme_v2_service/tests/integration/test_capture_idempotency.py`

**Steps:**

1. Add tests proving retries of the same tool call and sibling agent mistakes cannot create more than one successful root mutation for one `intent_id`.
2. Persist an intent-level idempotency/provenance key derived from `input_turn_id + intent_id + operation` on root mutations and enforce uniqueness for the user scope.
3. Give each sibling intent an isolated `SessionToolExecutor` context; do not share mutable tool-effect state.
4. Let multi-entity semantic structures create child records under one root without violating the root guard.
5. Emit diagnostics for pre-existing duplicate roots but do not delete them.

**Acceptance:** Two expenses in one recording create two roots; one expense intent retried twice creates one root.

### Task 10: Remove redundant production paths after parity tests pass

**Files:**

- Modify/delete as proven unused: `theme_v2_service/app/domains/capture/providers_litellm.py`
- Modify/delete as proven unused: strict JSON sections of `theme_v2_service/app/domains/capture/agent.py`
- Modify: `theme_v2_service/app/domains/capture/pipeline.py`
- Modify/delete as proven unused: `theme_v2_service/app/domains/capture/chat.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Test: `theme_v2_service/tests/unit/test_capture_provider_registry.py`
- Test: `theme_v2_service/tests/unit/test_capture_import_boundaries.py`

**Steps:**

1. Add registry/import tests that identify the single production capture provider and unified session chat route.
2. Use `rg` to prove obsolete providers/facades have no runtime references.
3. Remove the strict JSON-command provider, duplicated deterministic facade functions, and separate Flash chat provider only where tests prove them dead.
4. Keep small pure helpers only when they are used by the production provider or MCP boundary.
5. Update imports and module documentation so future fixes cannot accidentally land in a test-only path.

**Acceptance:** There is one discoverable production provider path and one session chat path.

### Task 11: Resolve Contact ambiguity without weakening routing

**Files:**

- Modify: `theme_v2_service/app/domains/capture/contact_skill.py`
- Modify: `theme_v2_service/app/domains/capture/tool_results.py`
- Modify: `theme_v2_service/app/internal_mcp/tools.py`
- Test: `theme_v2_service/tests/unit/test_contact_skill.py`
- Test: `theme_v2_service/tests/unit/test_flash_tool_results.py`
- Test: `theme_v2_service/tests/integration/test_internal_mcp_tools.py`

**Steps:**

1. Add tests for:
   - new named contact -> create;
   - “Alex 改成产品经理” with one exact owner-scoped match -> update;
   - multiple Alex matches -> pending clarification;
   - meeting attendee mention -> linked/unlinked attendee child, not an unintended new contact root unless product rules require it.
2. Route Contact through the same first-class operation and target-resolution semantics.
3. Remove any model-final-JSON assumption that hardcodes contact `create_or_update` success.
4. Preserve user scope and provenance for all contact lookup/update operations.

**Acceptance:** Updating Alex cannot silently create a second Alex when one exact unambiguous contact exists.

### Task 12: Full acceptance, isolated service restart, and real-device verification

**Files:**

- Add/modify: `theme_v2_service/tests/e2e/test_capture_acceptance.py`
- Update if needed: `docs/superpowers/specs/2026-08-10-theme-v2-capture-agent-parity-hardening-design.md`

**Steps:**

1. Run static and automated verification:
   - `python -m compileall theme_v2_service/app`
   - focused unit suites from Tasks 1–11;
   - `pytest theme_v2_service/tests/unit -q`;
   - `pytest theme_v2_service/tests/integration -q`;
   - `git diff --check`.
2. Rebuild/restart only the isolated Theme V2 service and worker; verify readiness includes the MCP contract audit.
3. Use the connected Android device with the Theme V2 package/build and local port reverse. Confirm it is not the legacy app before testing.
4. For account `1@1.com`, perform and inspect these captures:
   - two Todo items in one recording -> two Todo roots and one Flash count;
   - two expenses in one recording -> two Expense roots/balls and one Flash count;
   - “最近花了多少钱” -> grounded reply, no new asset;
   - “把刚刚账单从10改成8” -> same asset updated, Flash count +1;
   - custom “跑步训练” -> user custom Skill;
   - “昨天早上花了8块” -> yesterday/morning timeline placement;
   - exact named Contact create then occupation update -> one contact.
5. Verify live session behavior for a hardware capture: transcript appears without refresh, agent work state appears on the corresponding turn, and any failure is turn-scoped rather than session-global.
6. Inspect DB provenance, InputTurn counts, execution items, assets, and tool calls after every scenario.
7. Record any environmental-only blocker separately; do not mark the product behavior complete without the real-device evidence.

**Acceptance:** The core capture scenarios close end-to-end on the connected phone and every visible receipt matches the persisted effects.

---

## Final completion checklist

- [ ] Operations are explicit end to end.
- [ ] Query is read-only and grounded.
- [ ] Update/delete target resolution is deterministic and owner-scoped.
- [ ] One Flash hardware input increments the Flash count once.
- [ ] One atomic mutation intent produces at most one root entity.
- [ ] Multiple independent intents in one recording each produce their own root entity.
- [ ] Trusted identity/time context is injected centrally and hidden from the model.
- [ ] FastMCP callable/schema drift fails readiness and tests.
- [ ] Todo and Notes use typed creation tools and normalize once.
- [ ] Custom Skills route by stable ID with deterministic aliases and semantic fallback.
- [ ] Timeline time follows the legacy explicit/date/period/fallback hierarchy.
- [ ] Baseline Skill initialization is idempotent and concurrency-safe.
- [ ] Production Capture and Session Chat each have one runtime path.
- [ ] Contact correction does not duplicate an unambiguous contact.
- [ ] Automated suites and connected-device acceptance pass.

