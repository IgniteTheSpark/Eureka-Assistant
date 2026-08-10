# Theme V2 Capture Agent Parity Hardening Design

**Date:** 2026-08-10

**Status:** Approved in design discussion; pending written-spec review

## 1. Goal

Complete the Theme V2 Capture Agent migration without returning to the legacy
backend or Google ADK runtime.

The work must restore the mature Flash Pipeline's capture semantics while
preserving Theme V2's stronger runtime boundaries:

- one hardware or explicit Flash input increments the daily Flash count once;
- one Capture may produce multiple atomic intents and multiple entities;
- create, query, update, delete, and direct answer are first-class operations;
- a successful read may never be reported as a successful mutation;
- a failed mutation may never be hidden by a successful prerequisite query;
- trusted tenant, provenance, idempotency, timezone, and capture-time values are
  supplied by the server rather than model output;
- enabled custom Skills receive high-priority semantic routing over Notes;
- time and domain placement are normalized consistently before persistence;
- only one production Capture execution path remains;
- baseline Skill provisioning is concurrency safe.

Contact ambiguity hardening is intentionally implemented after the other
Capture contracts are stable. Report, Morning Brief, external Task/Connected
Apps, and third-party MCP behavior remain outside this work.

## 2. Incident That Motivates the Work

The 2026-08-10 connected-device capture correctly dispatched three intents:

1. create a Todo for taking medicine;
2. create a Todo for a factory meeting;
3. create an Expense for a barbecue meal.

The Expense persisted. Both Todo calls were rejected before domain execution.
`SessionToolExecutor` injected a trusted `reference_datetime`, but the FastMCP
`tool_create_todo` transport function did not accept that argument. FastMCP
therefore rejected the calls before `AgentToolExecution` or asset persistence.

This is a contract-drift failure, not an ASR or semantic-classification failure.
The immediate signature mismatch has a regression test and local fix, but the
system still needs a general guard so a similar mismatch cannot recur for a
different tool or trusted field.

## 3. Fixed Product Semantics

### 3.1 Capture count

Every accepted hardware or explicit Flash input counts as one Flash, including
read-only questions, updates, and deletes.

The count is independent of the number of derived entities:

```text
one recording
  -> expense/create: breakfast, CNY 8
  -> expense/create: groceries, CNY 20
  -> two Expense entities
  -> Flash count +1
```

Typed Chat messages inside the Session remain normal Chat turns and do not
increment the Flash count.

### 3.2 Atomic intent and root entity

An atomic intent represents one user-requested operation against one root
entity. One Capture may contain any number of atomic intents.

Each `create` intent may create at most one root entity. Event attendees are
children of one Event and do not count as additional root entities.

The restriction prevents duplicate tool firing for one intent; it does not
limit a multi-intent recording to one Asset.

### 3.3 Read-only capture

For input such as "帮我看看最近花了多少钱":

- the Capture count increments once;
- the normalized intent is `expense/query`;
- only owner-scoped query tools may run;
- deterministic aggregation computes totals from returned records;
- the Agent produces a concise answer or read-only result card;
- no Asset, Event, or Contact is created;
- the result copy does not say "已完成 1 项".

## 4. Operation Is a First-Class Contract

`FlashIntent` is extended to contain:

```text
type
operation: create | query | update | delete | answer
source_text
domain
ordinal
custom_skill_id (only for a custom Skill)
```

Examples:

| Input | Type | Operation |
|---|---|---|
| 花了 10 元买咖啡 | expense | create |
| 最近花了多少钱 | expense | query |
| 把刚刚那笔从 10 元改成 8 元 | expense | update |
| 删除刚才的打车记录 | expense | delete |
| 地球为什么是圆的 | qa | answer |

The Dispatcher proposes `type + operation`. A deterministic normalizer then
validates aliases, explicit mutation language, built-in/custom precedence,
multi-expense splitting, and Event range rules. An absent operation defaults to
`create` only for record-shaped statements; questions default to `query` or
`answer`.

Result resolution uses an operation policy rather than treating any successful
tool result as success:

- `create` requires an allowed successful create result and a root entity ID;
- `update` requires an allowed successful update result for a resolved target;
- `delete` requires an allowed successful delete result for a resolved target;
- `query` accepts only successful reads and produces a reply/read result;
- `answer` permits no mutation;
- a prerequisite query cannot satisfy a mutation operation;
- a fluent final Agent message cannot substitute for a missing mutation result.

### 4.1 Deterministic target resolution

Update and delete resolve one target before mutation. Resolution priority is:

1. an explicit entity ID from a selected card/action;
2. for "刚刚那个/刚才那笔", the root entity produced by the latest prior
   completed InputTurn in the same physical Session;
3. an entity reference from the latest prior Session result card;
4. one unique exact title/name/typed-field match;
5. a safe owner-scoped candidate query.

An incomplete prior Agent turn is not a valid "刚刚那个" target. Zero or
multiple safe candidates cause an isolated no-mutation result. Update never
silently falls back to create, and delete never chooses the first broad contains
match. Query operations may aggregate multiple returned entities and therefore
do not require a unique mutation target.

## 5. Trusted Execution Context

All Capture tool executions receive one server-owned context:

```text
InternalMCPTrustedContext
  user_id
  session_id
  input_turn_id
  tool_call_id
  reference_datetime
  timezone_name
```

The values have distinct responsibilities:

- `user_id` enforces tenant isolation;
- `session_id` and `input_turn_id` preserve provenance;
- `tool_call_id` supplies stable mutation idempotency;
- `reference_datetime` is the actual capture time used to interpret relative
  language and product defaults;
- `timezone_name` determines local-day and deadline behavior.

Every tool receives the context object. Individual handlers consume only the
fields they need. Queries normally use tenant information but not capture time;
Todo, Event, Expense, and custom-Asset creation may use capture time.

Trusted values are never accepted from model output. They are passed as runtime
context, not manually copied into model-generated JSON in multiple layers.

## 6. Lightweight MCP Contract Guard

This design does not add a runtime `ToolContractRegistry` or dynamically
generate all FastMCP functions.

FastMCP function signatures remain the transport source of truth. A small
`TRUSTED_ARGS_BY_TOOL` declaration identifies which trusted context fields a
transport tool consumes. The MCP runtime owns all trusted injection.

Automated conformance tests enumerate every registered tool and assert:

1. every declared trusted argument exists in the transport function signature;
2. trusted arguments are excluded from the model-visible tool schema;
3. every non-trusted function argument appears in the model-visible schema;
4. a synthetic call with trusted context passes FastMCP validation;
5. operation/effect metadata references only registered tools;
6. mutation tools preserve the trusted idempotency key.

API and Worker startup perform the schema-only portion of this audit after the
local MCP process exposes its tool list. A mismatch fails readiness before any
Capture is accepted. Synthetic execution remains test-only, so normal startup
does not call an external model or mutate the database.

## 7. Typed Domain Tools and Asset Persistence

The Agent-facing creation tools are semantic facades:

```text
tool_create_todo
  -> Todo normalization
  -> generic persistence kernel

tool_create_note
  -> Note normalization
  -> generic persistence kernel

tool_create_asset (Expense and enabled custom Skills)
  -> Agent-write payload validation
  -> generic persistence kernel
```

The generic persistence kernel owns only shared storage behavior:

- owner and Skill lookup;
- payload validation under the selected write profile;
- provenance validation;
- Asset insertion;
- typed field indexing;
- triggers and outbox events.

It contains no Todo deadline rules and no Notes-specific shaping.

`tool_create_asset(user_skill_name="todo")` and
`tool_create_asset(user_skill_name="notes")` are rejected so typed creation
cannot be bypassed. The Todo MCP handler normalizes the deadline exactly once
and then calls the storage kernel rather than the semantically rich public
`create_asset` path.

Existing generic update/query/delete tool names may remain for compatibility.
When their resolved target is a typed built-in, the domain service applies that
type's update invariants before invoking the storage kernel.

## 8. Custom Skill Routing

The current user's enabled custom Skills form a request-time routing catalog.
Each catalog entry includes:

- stable `UserSkill.id`;
- machine name and display name;
- description;
- localized field names and descriptions;
- capture-enabled state;
- safe render metadata needed for source-text fallback.

The Dispatcher selects a stable custom Skill ID from the supplied catalog rather
than inventing a machine name. The resolver supports, in order:

1. exact Skill ID;
2. exact machine name;
3. normalized case-insensitive machine name;
4. normalized display name;
5. a unique machine-name/display-name prefix.

Semantic catalog matching may select a custom Skill even when its name does not
appear literally in the transcript, for example routing "刚跑完五公里" to an
enabled "跑步训练" Skill using its description and fields.

Built-in structural semantics remain stronger than custom routing:

- Todo/Event/Expense/Contact cannot be stolen by a custom Skill;
- a future scheduled run is Todo or Event, not a completed running record;
- custom Skill matching has priority over Notes only;
- disabled Skills are never candidates;
- unresolved or ambiguous custom routing falls back to Notes rather than
  guessing a wrong Skill.

## 9. Deterministic Time and Domain Alignment

No second temporal context protocol is introduced. The existing pure
`extract_temporal_hints(source_text, reference_datetime)` function is the shared
boundary and returns the existing compact `CaptureTemporalHints` values:

```text
anchor_date
period
occurred_at
```

The duplicate pipeline-local `_temporal_hints()` implementation is removed.

The parser is extended only to the product-supported temporal language required
by legacy parity: relative days, explicit month/day and ISO dates, weekdays,
fuzzy periods, exact clocks including half hours, and bounded durations/ranges.

Precedence is fixed:

```text
explicit clock
  > explicit date plus fuzzy period
  > explicit date
  > fuzzy period only
  > no semantic time
```

Examples:

- "昨天早上花了 8 元" -> yesterday + `period=上午`, no invented clock;
- "昨天下午 3 点花了 8 元" -> exact `occurred_at`;
- "昨天花了 8 元" -> yesterday date anchor, no invented clock;
- "花了 8 元" -> no semantic time; presentation falls back to capture time.

Unsupported temporal wording does not permit the model to invent an exact
clock. Generic/custom records retain no semantic time, Todo uses its product
default deadline, and Event falls back to Todo unless a complete range is
safely resolved.

Todo consumes the same hints plus trusted reference time to produce one concrete
deadline:

- exact due datetime wins;
- date plus period uses the configured period end;
- date only uses 18:00;
- period only uses today's period end, or tomorrow when already passed;
- no time uses today 18:00, or tomorrow 18:00 when already past 18:00.

Event creation requires a deterministically resolved complete range. An unsafe
or incomplete Event candidate becomes Todo rather than receiving an invented
end time.

Domain classification remains semantic and is proposed by the Dispatcher. Its
application is deterministic:

1. normalize to the supported domain enumeration;
2. use bounded keyword fallback when the proposal is absent or invalid;
3. use `生活` as the product fallback domain when still unresolved;
4. inject the final domain at the execution boundary;
5. prevent a Skill Agent from omitting or overriding it.

This replaces legacy write-after-the-fact database correction with one
pre-persistence normalization path.

## 10. Duplicate Root-Mutation Prevention

Stable MCP idempotency continues to replay identical calls across retries.

In addition, the Agent runner tracks successful root mutations per atomic
intent:

- one `create` intent may complete one successful root create;
- after that success, a distinct second root create for the same intent is
  rejected before MCP execution;
- failed calls do not consume the successful-write budget;
- Event attendee calls remain allowed after one Event create;
- sibling intents have independent budgets and may each create an entity.

A read-only diagnostic detects abnormal root-entity counts by InputTurn. This
phase does not automatically delete user data. A provenance-bounded repair
command may be added only after prevention is verified against real provider
behavior.

Contact multi-field mutation is exempt from generalized root-mutation changes
until the final Contact ambiguity slice defines its atomic behavior.

## 11. Concurrency-Safe Baseline Skill Provisioning

Baseline Skills are provisioned at account creation. Lazy provisioning remains
as an idempotent compatibility path for existing users and historical data.

Lazy provisioning uses the existing unique key `(user_id, machine_name)` with
one consistently ordered MySQL bulk upsert followed by one authoritative
select. It does not perform a query-then-row-by-row-insert race.

Existing user presentation, schema, and render settings are preserved. The
provisioner may add missing baseline fields required by the product contract but
may not overwrite user-owned custom fields or presentation choices.

Concurrent tests start Asset Library loading and Capture processing for the same
new user and require:

- one row per baseline Skill;
- no duplicate-key error;
- no deadlock;
- stable global-skill linkage;
- unchanged custom schema/render configuration.

## 12. Remove Redundant Runtime Paths

The only production Capture path becomes:

```text
Capture Job
  -> LiteLLM legacy-compatible Flash provider
  -> Dispatcher and operation normalizer
  -> Skill Agent
  -> trusted internal MCP
  -> domain service and persistence kernel
  -> result resolver and presenter
```

After replacement tests cover the production provider, remove or retire:

- the obsolete strict-JSON `LiteLLMCaptureAgentProvider`;
- the non-production `LegacyFlashPipeline` facade;
- the unused separate `FlashChatProvider` implementation;
- stale command-document validation models used only by removed paths;
- tests that pass only against those non-production paths;
- duplicate temporal helpers and duplicate Todo normalization.

Reusable types and deterministic fallback functions move into explicitly named
contract/fallback modules. The date-based Flash Chat compatibility API may
remain, but it must continue delegating to the unified Session Chat service and
must not own a provider or message execution path.

## 13. Contact Ambiguity Final Slice

Contact handling is deliberately last so it uses the stabilized operation and
result contracts.

The final slice must make zero/one/multiple exact-name behavior deterministic
for both create-or-update and delete, preserve the requested operation in a
pending action, support multiple field updates without false whole-intent
success, and keep Event attendee binding limited to one exact Contact.

Until that slice is complete, ambiguous Contact operations remain safe-fail:
they may request confirmation but may not guess or mutate a candidate.

## 14. Error Semantics and Observability

Errors are classified at their real boundary:

- provider transport/timeout -> retryable job failure;
- internal MCP unavailable -> retryable job failure;
- dispatcher formatting -> Notes fallback;
- FastMCP argument-contract violation -> internal contract error, never a
  user-content validation error;
- domain validation rejection -> isolated intent failure;
- successful sibling plus failed sibling -> completed Capture with warnings;
- no safe result after retryable attempts -> failed Agent turn.

Structured telemetry records operation, intent type, selected Skill ID, tool,
effect class, contract/fallback reason, and correlation IDs without storing raw
user transcripts in ordinary logs.

## 15. Implementation Order

1. Introduce first-class operation and operation-grounded result resolution.
2. Centralize trusted context injection and add all-tool MCP conformance tests.
3. Split typed Todo/Notes normalization from the generic persistence kernel.
4. Restore high-priority custom Skill catalog routing.
5. Consolidate deterministic time and domain handling.
6. Make baseline Skill provisioning concurrency safe.
7. Prevent duplicate root mutations and add diagnostics.
8. Remove obsolete providers, facades, helpers, and stale-path tests.
9. Complete Contact ambiguity behavior.
10. Run deterministic, real-provider, isolated-stack, and connected-device
    acceptance.

Each implementation slice uses red-green-refactor tests and leaves the
production path runnable. Report and Reka work are not modified by these
changes.

## 16. Acceptance Matrix

The final backend and device acceptance includes at least:

- one Expense create;
- two Expenses in one recording, yielding two entities and Flash count +1;
- Todo with exact time;
- Todo with date plus period;
- Todo with no time before and after 18:00;
- read-only Expense aggregation with no new entity;
- update "刚刚那个" using Session/InputTurn/entity provenance;
- delete with a unique safe target;
- general QA with no mutation;
- enabled custom Skill semantic match without literal Skill name;
- custom Skill partial payload;
- scheduled future activity not stolen by a custom record Skill;
- fuzzy-period and explicit-clock Timeline placement;
- dispatcher domain applied even when the Skill omits it;
- identical retry creates no duplicate;
- distinct duplicate create within one atomic intent is blocked;
- concurrent first-use Skill provisioning has no deadlock;
- partial multi-intent success preserves successful cards;
- ring and card recordings reach the correct physical daily Session;
- leaving and returning preserves running and terminal Agent states.

## 17. Completion Definition

This hardening is complete when:

- the Worker registers only one Capture execution provider;
- operation-specific success cannot be confused with prerequisite tool success;
- all MCP trusted/model-visible arguments pass the conformance audit;
- typed Todo creation normalizes once and never calls the public generic Asset
  creation path;
- enabled custom Skills route by stable identity and semantic metadata;
- time/domain placement is consistent across built-in and custom Assets;
- baseline Skill provisioning is concurrency safe;
- one atomic intent cannot create duplicate root entities;
- obsolete runtime paths and stale-path tests are removed;
- Contact ambiguity acceptance passes;
- the full deterministic suite, synthetic real-provider suite, and connected
  ring/card acceptance pass on the isolated Theme V2 stack.
