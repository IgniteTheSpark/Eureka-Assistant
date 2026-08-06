# Theme V2 Flash Agent Systematic Recovery Design

**Date:** 2026-08-06

**Status:** Approved for implementation

## 1. Goal

Repair the Theme V2 Flash Capture migration at its architectural boundary,
rather than masking the current DeepSeek `json_object` failure with a prompt or
parser hotfix.

The repaired flow restores the mature legacy execution contract inside the
Theme V2 service:

```text
ASR final
  -> tolerant Flash dispatcher
  -> deterministic intent normalization
  -> independent built-in or dynamic Skill agents
  -> Theme V2 internal CRUD MCP
  -> tool-result-grounded aggregation
  -> Theme V2 presenter, Session state, outbox, and notification
```

Theme V2 remains the only deployed product service. The repair does not route
requests to the legacy backend and does not replace Theme V2 persistence,
durable jobs, Session models, realtime delivery, or cards.

This document is a corrective supplement to
`2026-08-05-theme-v2-legacy-agent-migration-design.md`. It restores that
document's intended Flash execution architecture after the first Tranche 4
implementation replaced the legacy Skill/tool loop with strict JSON command
extraction.

## 2. Incident and Root Cause

### 2.1 Observed failure

Real ring captures complete Tencent ASR and persist their transcript, recording,
daily Session, and input turn. The `capture_process` job then exhausts all
retries with:

```text
capture provider returned incompatible JSON
```

The failure is repeatable across ordinary multi-intent content. It is not
specific to one custom Skill or one malformed transcript.

### 2.2 First breaking change

Commit `c83e59f` changed the registered capture provider from the prior direct
`LiteLLMCaptureAgentProvider` to `LiteLLMLegacyFlashProvider`.

The new provider introduced two model stages:

1. `FlashDispatchResult` generation;
2. one `CaptureAgentResult` generation per dispatched intent.

For DeepSeek, both stages request only `response_format={"type":"json_object"}`.
The dispatcher prompt does not contain the `FlashDispatchResult` schema, and
the Skill prompt contains only the asset payload schema rather than the outer
`CaptureAgentResult` schema. The returned JSON is then passed through strict
Pydantic validation. Any valid but differently shaped JSON becomes a retryable
whole-recording failure.

### 2.3 Architectural regression

The missing schema is only the first visible break. The migration also omitted
the mature behavior that previously made model formatting non-fatal:

- tolerant extraction from Markdown fences, preambles, or surrounding text;
- dispatcher failure falling back to `notes`;
- per-intent failure isolation;
- Skill agents invoking CRUD tools directly;
- tool events acting as ground truth when final Agent text is malformed;
- deterministic custom-Skill creation when extraction is incomplete;
- deterministic built-in fallbacks such as incomplete Event to Todo;
- aggregation from actual successful mutations rather than proposed commands.

The current Theme V2 implementation instead asks the model to propose a fully
validated command document before any Skill or MCP call can execute. This is a
different failure boundary from the approved migration design and from the
legacy product.

### 2.4 Why tests did not catch it

The Tranche 4 unit tests inject completions containing perfectly shaped JSON.
They validate the happy-path Pydantic contract but not actual DeepSeek
`json_object` behavior or the legacy fallback rules.

The tranche acceptance checklist also still has two incomplete gates:

- legacy-parity evaluation fixtures;
- real connected-device acceptance.

The migration therefore must not be considered complete until those gates pass.

## 3. Fixed Constraints

- Do not fix the incident by adding only a JSON schema to the prompt.
- Do not add retries that repeat the same structurally fragile request.
- Do not route Theme V2 traffic to the legacy backend.
- Do not duplicate model-triggered mutations in a shadow comparison path.
- Do not change the Theme V2 database, durable job, outbox, SSE, Session, or
  card ownership boundaries.
- Do not allow model output to choose `user_id`, `session_id`,
  `source_input_turn_id`, or an idempotency key.
- Do not let one failed sibling intent erase successful sibling mutations.
- Do not expose provider, schema, stack, or MCP errors as the Agent's visible
  Session reply.
- Keep Report and Morning Brief outside this repair.
- Preserve the temporal rules in
  `2026-08-05-theme-v2-core-workflow-parity-design.md`; no new invented times
  are introduced here.

## 4. Chosen Architecture

### 4.1 Theme V2 legacy-compatibility kernel

Theme V2 receives a self-contained Flash compatibility kernel ported from the
mature legacy implementation. It contains:

- a Theme V2 Agent runner based on the legacy ADK one-shot runner;
- the legacy Flash dispatcher instruction;
- the deterministic intent normalizer;
- built-in Flash Skill instructions;
- dynamic custom-Skill Agent construction;
- tool-event capture and result reconstruction;
- Python aggregation and deterministic fallback replies.

The ported code lives under `theme_v2_service`. It must not import the legacy
`backend` package at runtime. Legacy `SKILL.md` content is copied or adapted as
versioned Theme V2 runtime material so a future change is reviewed explicitly.
Theme V2 pins `google-adk` as an explicit service dependency rather than relying
on the legacy backend environment or an incidental transitive version.

### 4.2 Internal MCP topology

The runtime topology remains local stdio MCP:

```text
Theme V2 ADK Skill Agent
  -> Theme V2 trusted MCP tool adapter
  -> lifecycle-managed InternalMCPRuntime
  -> local FastMCP stdio subprocess
  -> Theme V2 domain services
  -> Theme V2 MySQL
```

The trusted adapter exposes the MCP tool contracts to the Agent but overwrites
all provenance fields immediately before execution. The model can neither
select nor override tenant or provenance scope.

This adapts the legacy ADK/MCP integration to Theme V2's existing secure MCP
runtime without collapsing the MCP transport into direct database functions.

### 4.3 Theme V2 infrastructure retained

The following remain unchanged in ownership:

- `capture_process` durable jobs and leases;
- physical daily Flash Session materialization;
- `CaptureRecording`, `InputTurn`, and persisted Agent message state;
- internal MCP domain implementations and `AgentToolExecution` records;
- outbox/SSE events and notifications;
- Theme V2 card presenter and navigation references;
- timeline derivation and Flash counter contracts.

The compatibility kernel returns execution facts. It does not become a second
persistence service.

## 5. Flash Execution Contract

### 5.1 Capture context

Each run receives trusted context assembled by the job handler:

- recording ID;
- authenticated user ID;
- physical Session ID;
- source InputTurn ID;
- final transcript;
- original capture reference datetime in `Asia/Shanghai`;
- enabled built-in and custom Skill registry entries.

The original capture datetime is used for relative-language interpretation.
Processing time and offline reconnect time are not valid substitutes when a
more accurate hardware capture timestamp exists.

### 5.2 Dispatcher

The dispatcher uses the legacy dispatcher instruction and a bounded model call.
Its output parser accepts:

- a plain JSON object;
- fenced JSON;
- explanatory text surrounding one JSON object;
- legacy aliases that the deterministic normalizer understands.

The parser never interprets arbitrary text as executable tool arguments. It
only extracts the bounded intent list and source fragments.

If the dispatcher has no usable intent list, the entire transcript becomes one
`notes` intent. A formatting failure at this stage is therefore not a terminal
capture failure.

### 5.3 Deterministic intent normalization

The existing mature normalizer owns aliases and fallback behavior. In
particular:

- free text defaults to `notes`;
- `idea`, `misc`, and `other` do not become default user-facing Skills;
- enabled custom Skill machine names remain routable;
- unknown or disabled names fall back safely;
- each normalized intent retains its source fragment and stable ordinal.

### 5.4 Independent Skill execution

Normalized sibling intents may execute concurrently, but each has an isolated
result boundary. One Skill exception is captured as that intent's failure and
does not cancel or roll back successful siblings.

Each built-in or dynamic Skill Agent receives only:

- its atomic source fragment;
- the full transcript as supporting context;
- the trusted reference datetime;
- the applicable Skill schema and instruction;
- the allowed internal MCP tools.

The Agent performs create, query, update, or delete through MCP. It does not
return a command document for a second executor to replay.

### 5.5 Tool results are ground truth

The Theme V2 Agent runner captures every tool call and response in order.

Result resolution follows this order:

1. successful mutation or query results captured from MCP tool events;
2. a valid final Agent result that is consistent with those tool events;
3. a deterministic domain fallback when the legacy rule allows one;
4. an isolated per-intent failure.

A malformed final answer cannot hide a successful tool mutation, and a fluent
final answer cannot claim a mutation for which no successful tool result exists.

The current `CaptureAgentResult -> LegacyFlashPipeline -> SessionToolExecutor`
double-step is removed from the production Flash path. The presenter consumes
actual tool results and never executes the proposed mutation a second time.

### 5.6 Custom-Skill fallback

When the dispatcher confidently selects an enabled custom Skill but the Skill
Agent returns but does not complete a successful tool call because extraction
or final-output formatting failed, the compatibility kernel uses the legacy
deterministic fallback:

- create one asset for that custom Skill;
- persist only fields grounded in the transcript;
- allow a partial or empty optional payload;
- retain the source InputTurn provenance;
- preserve the source fragment for safe card-title fallback;
- apply the existing deterministic temporal hints;
- never invent a required field merely to satisfy a schema.

This fallback still writes through the internal MCP and therefore retains
ownership, validation, idempotency, and audit behavior.

The fallback does not run when the model provider was unavailable, the MCP
runtime was unavailable, or the job lost its lease. Infrastructure failure must
remain retryable rather than being disguised as a low-quality asset.

### 5.7 Built-in fallback rules

Existing mature domain rules remain authoritative, including:

- an Event without a safe complete interval falls back to Todo rather than
  creating a fake calendar range;
- Contact exact-name zero/one/multiple behavior remains deterministic;
- QA returns a reply and creates no record;
- Notes is the default free-text store;
- fuzzy periods remain periods and are not converted to invented clock times.

## 6. DeepSeek and Structured Output Policy

`response_format={"type":"json_object"}` is a provider capability hint, not a
correctness or transaction boundary.

Provider-specific response behavior is centralized in one model adapter:

- providers with native strict JSON Schema may receive it for dispatcher-only
  structured output;
- DeepSeek may continue to receive `json_object` where supported;
- the relevant bounded schema or examples are included in the dispatcher
  instruction;
- tolerant parsing and deterministic normalization remain required even when a
  strict schema mode is requested;
- Skill correctness is established by successful MCP tool results, not by an
  outer Pydantic response document.

Pydantic remains authoritative at internal Python and MCP/domain boundaries.
It is not used to turn harmless model presentation differences into a failed
recording.

Raw user transcripts and full provider responses are not added to normal logs.
Diagnostics store stage, error class, model/provider, attempt, and correlation
IDs. Opt-in synthetic provider-contract tests use invented content only.

## 7. Idempotency and Retry

### 7.1 Stable tool identity

Every mutation receives a trusted deterministic tool-call key derived from:

```text
recording ID
+ normalized intent ordinal
+ tool name
+ canonical argument hash
```

The callback overwrites any model-supplied key. The existing
`AgentToolExecution` idempotency record then returns the prior result on a job
retry and rejects a reused key with different arguments.

### 7.2 Error classification

Errors are classified at the stage where they occur:

- provider transport, timeout, or availability failure: retryable job error;
- internal MCP process unavailable: retryable job error;
- dispatcher formatting failure after a provider response: local `notes`
  fallback, no job retry;
- Skill final-text formatting failure after a successful tool call: success
  reconstructed from the tool event;
- custom-Skill extraction miss: deterministic custom-asset fallback;
- one rejected tool call: isolated intent failure unless its legacy fallback is
  safe;
- invalid trusted domain input: permanent isolated intent failure;
- loss of job lease or database availability: retryable infrastructure error.

Retries resume against the same recording and provenance. They do not create a
second Session turn, increment the Flash count again, or duplicate a prior MCP
mutation.

### 7.3 Partial and terminal outcomes

The aggregate outcome is:

- `done` when all intents succeed;
- `done_with_warnings` internally when at least one intent succeeds and at
  least one fails;
- `failed` only when no safe result or reply can be produced after retryable
  infrastructure/provider attempts are exhausted.

If the existing recording status enum cannot add `done_with_warnings` safely,
the database status remains `done` and warnings are stored in structured
execution metadata. The user sees successful cards plus a concise per-turn
warning, not a session-wide failure banner.

The visible failure copy is stable product language such as “这条闪念暂时没有
整理完成，可以重试”。Technical messages such as `incompatible JSON` remain
internal.

## 8. Session Realtime Behavior

The approved realtime contract remains:

- no transcript text is inserted while ASR is incomplete;
- at ASR final, the user turn appears immediately in an already-open physical
  daily Flash Session;
- one persisted Agent message enters the loading state immediately afterward;
- SSE updates that same message to completed, partial-warning, or failed;
- leaving and returning refetches the persisted state without duplicates.

This repair does not introduce word-by-word ASR or pretend that offline card
audio is being heard live.

## 9. Hardware Recording Visual Boundary

The legacy full-screen hardware recording animations are temporarily removed
from the shipped app:

- do not mount `GlobalListeningOverlay`;
- do not mount `BleFlashOverlay`.

Only their presentation is removed. The following remain active:

- BLE managers and device callbacks;
- card and ring recording state machines;
- reconnect and offline-file discovery;
- ASR, upload, durable recording creation, and retry;
- `listeningNotifier` and `isFlashing` where non-visual lifecycle code still
  depends on them;
- post-record sync/transcription status and per-turn Agent loading/failure.

Removing the overlays must not alter start/stop acknowledgements, create extra
network requests, or suppress the final transcript and notification.

## 10. Capture-Time Parity

Online card, ring, and phone-microphone captures use their actual capture start
time as the Agent reference datetime.

For card recordings discovered after reconnect, the client first uses device
metadata. If that metadata lacks a capture timestamp, it parses the mature
`FYYYYMMDD-HHMMSS` filename convention. Only when neither source is valid may it
fall back to discovery time.

This timestamp is provenance and reference context. Asset occurrence remains
governed by the existing rules:

- exact stated time -> `occurred_at` and visible clock;
- fuzzy stated period -> `period` without invented `HH:mm`;
- no stated semantic time -> capture/creation time as display fallback;
- unscheduled Todo remains in the no-time section.

## 11. Observability

Every Flash run records structured stage telemetry without user content:

- recording and job correlation IDs;
- dispatcher parse mode and normalized intent count;
- per-intent Skill name, operation class, status, and duration;
- tool name, idempotency hit/miss, and success/rejection class;
- fallback reason code;
- aggregate success/partial/failure state;
- provider and model identifier.

Recommended stable reason codes include:

- `dispatcher_parse_fallback`;
- `skill_tool_result_recovered`;
- `custom_skill_deterministic_fallback`;
- `intent_tool_rejected`;
- `provider_transport_retry`;
- `internal_mcp_retry`;
- `capture_no_safe_result`.

These reason codes replace string matching on provider exception text.

## 12. Verification Strategy

### 12.1 Characterization before replacement

Before changing the provider registry, port legacy behavior fixtures for:

- fenced and prefaced dispatcher JSON;
- malformed dispatcher output falling back to Notes;
- multi-intent expense plus hydration/custom record;
- correction and delete operations;
- Contact create, exact-name update, and same-name ambiguity;
- Event attendee exact/zero/multiple binding;
- incomplete Event fallback;
- QA with no mutation;
- custom Skill with partial fields;
- successful tool call followed by malformed Agent final text;
- one sibling intent failing while another succeeds;
- relative date, fuzzy period, and no-time fallback.

The existing two real failure shapes are represented with anonymized synthetic
fixtures. Real user transcript content is not sent to an external provider for
debugging.

### 12.2 Unit and contract tests

Tests cover:

- tolerant JSON extraction and normalization;
- provider capability selection;
- trusted provenance and tool-call-key override;
- tool-event result reconstruction;
- custom and built-in deterministic fallbacks;
- partial aggregation and user-visible error sanitization;
- retry idempotency;
- overlay absence without lifecycle disposal;
- offline filename timestamp parsing;
- Session SSE insertion and recovery.

Mocks must include malformed-but-plausible provider outputs, not only perfect
Pydantic documents.

### 12.3 Synthetic provider smoke test

An explicit, opt-in test may call the configured DeepSeek model with invented
Chinese captures. It performs mutations only against isolated test data and
must cover:

- one simple built-in record;
- one multi-intent record;
- one custom Skill with incomplete fields;
- one QA intent.

This smoke test is not part of ordinary unit tests and never uses copied user
transcripts.

### 12.4 Real-device acceptance

The connected-device gate covers both ring and card:

1. start and stop recording with no full-screen legacy animation;
2. confirm ASR text reaches the correct daily Session without refresh;
3. confirm one persisted Agent loading state appears;
4. confirm multi-intent cards and assets are created once;
5. confirm a custom Skill partial capture succeeds;
6. confirm Contact update does not create an unintended duplicate;
7. confirm notification opens the physical Session;
8. confirm Flash count increments once per hardware capture only;
9. confirm leaving and returning preserves the final state;
10. reconnect a card with an offline file and verify its original timestamp.

## 13. Rollout and Removal

Implementation is delivered in reversible internal slices:

1. freeze legacy-parity fixtures;
2. port the Theme V2 Agent runner and trusted MCP adapter;
3. port dispatcher, normalizer, built-in Skills, and dynamic custom Skills;
4. restore tool-result aggregation and deterministic fallbacks;
5. connect the compatibility kernel to `capture_process` behind a single
   Theme V2 configuration flag;
6. run backend, synthetic provider, and real-device acceptance;
7. make the compatibility kernel the only production Flash path;
8. remove the strict JSON command-extraction provider and obsolete tests;
9. remove the two full-screen hardware overlays;
10. complete and record the previously unchecked Tranche 4 acceptance gates.

The fallback flag may switch between two implementations only before release.
It must not execute both mutation paths and is removed after acceptance.

## 14. Completion Definition

The repair is complete only when:

- the legacy behavioral fixtures pass against Theme V2;
- malformed model presentation cannot erase successful tool mutations;
- DeepSeek `json_object` is no longer a whole-pipeline schema boundary;
- custom Skill partial capture works;
- multi-intent partial failure is isolated;
- retries create no duplicate records or turns;
- technical exceptions are not shown as Session replies;
- ring and card real-device acceptance passes on the Theme V2 build;
- the legacy recording overlays are absent while capture remains functional;
- offline capture time and Timeline placement match the mature rules;
- the Tranche 4 legacy-eval and phone acceptance checklist items are closed;
- no Theme V2 runtime import or network dependency on the legacy backend exists.
