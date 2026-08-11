# Theme V2 Report Reliability, Scope-First Planning, and Async Illustration Design

**Date:** 2026-08-11

**Status:** Design approved in conversation; written spec awaiting user review

**Scope:** Theme V2 manual and Reka-initiated Report scope confirmation, pre-event and period-summary adapters, local-time grounding, Report generation reliability, and Seedream continuation after the 30-second foreground wait

## 1. Context

The current Theme V2 Report implementation has the right high-level pieces but
several boundaries are connected in the wrong order.

Production evidence from the `1@1.com` acceptance account showed three concrete
failures around one manually created 21:00 meeting:

1. The pre-event trigger fired and created a `report_available` notification,
   but the Theme V2 home Reka surface did not show it because that surface reads
   only overdue and rhythm candidates.
2. A manual request for `会前调研` queued Planner before the user selected the
   meeting. The generated plan was therefore generic. Selecting the meeting
   later added it to generation evidence but did not rerun scope resolution, so
   the Event notes did not shape public-research questions.
3. Content generation rejected the meeting time with
   `unreferenced numeric claim: 13`. The Event started at 21:00 in
   `Asia/Shanghai`, while its stored UTC value contained 13:00. Trusted datetime
   evidence and the numeric-claim validator did not share a typed local-time
   contract.

Seedream also currently runs inside the synchronous Report pipeline. A
30-second timeout cancels the image request, so it cannot satisfy the approved
product behavior: wait at most 30 seconds for the initial Report, then continue
the image generation and backfill it into an already-open Report.

These are contract failures across entry, scope, planning, Reka aggregation,
temporal grounding, and optional media. They must be fixed as one Report
reliability slice rather than as scenario-specific exceptions.

## 2. Relationship to Existing Designs

This specification preserves the architecture and presentation decisions in:

- `2026-08-07-theme-v2-unified-report-planning-research-design.md`;
- `2026-08-05-theme-v2-reka-signals-and-rhythm-design.md`;
- `2026-08-04-theme-v2-report-presentation-seedream-design.md`;
- `2026-08-04-theme-v2-report-readability-presentation-actions-design.md`.

It intentionally supersedes the following narrower decisions where they
conflict:

- user-initiated Reports confirm a type-specific base scope **before** Planner
  generates a plan;
- a period-summary adapter may default-select all aggregatable records in its
  explicit period, even though the general Asset Picker still has no global
  `select the entire library` action;
- Event notes are a first-class input to research-scope derivation;
- optional Seedream work may continue in a durable child job after the text
  Report is already readable;
- Report rows may be rerendered once to attach that illustration, while public
  share snapshots remain immutable.

The existing trusted renderer, presentation families, Report-to-Todo behavior,
object-storage abstraction, Web Search quality gates, and one-Report-per-Run
ownership remain authoritative.

## 3. Decision Summary

Every Report still uses one resumable `ReportGenerationRun`, but the user-facing
order becomes scope-first:

```text
entry intent / Reka offer
  -> identify Report adapter
  -> Step 1: confirm type-specific base scope
  -> Step 2: generate and confirm one recommended plan
  -> freeze a scope-bound execution plan
  -> Step 3: generate Report content
  -> start at most one durable illustration job when applicable
       -> finish within 30 seconds: return the illustrated Report
       -> still pending at 30 seconds: return readable Report + fixed placeholder
            -> child job continues
            -> atomically rerender Report when the image is ready
            -> open mobile viewer patches only the illustration slot
```

The first scope screen is adapter-driven. It does not ask users to restate a
purpose already explicit in their request.

The approved initial adapters are:

- **Pre-event briefing:** select one primary upcoming Event, then optionally
  add multiple supporting evidence references and focus questions.
- **Period summary:** confirm one resolved period and multi-select the record
  types or individual records to aggregate.
- **Generic research/report:** retain the existing typed focus, evidence, and
  public-research controls when no more specific adapter applies.

## 4. Goals

1. Make Report planning specific before the first model-generated plan.
2. Surface pre-event Report offers in both Reka and Notifications without
   duplicating business ownership.
3. Make Event notes influence research questions and final content.
4. Ground Event dates and times in the user's local timezone and validate them
   as typed trusted facts.
5. Ensure optional illustration latency or failure never invalidates a readable
   Report.
6. Continue Seedream safely after 30 seconds, including across worker restarts,
   without duplicate paid calls or duplicate images.
7. Preserve one-tap generation when all recommended defaults are acceptable.
8. Keep the interaction extensible to additional Report intents without
   hardcoding individual phrases in the UI.

## 5. Non-goals

This slice does not:

- redesign Report templates, palette families, citations, or Report-to-Todo;
- add multiple illustrations to one Report;
- move media to OSS/S3 in this delivery;
- use a minute-precise Reka rhythm model;
- convert Notifications into Reka workflow receipts;
- generate one combined pre-event Report for multiple primary meetings;
- make Web Search mandatory for period summaries that only aggregate owned
  records;
- bulk-select the entire Asset library outside an explicit adapter-owned period;
- mutate an already-created public share snapshot when a later image arrives.

## 6. Product Flow

### 6.1 Entry and adapter selection

Creating a Run first classifies the bounded user intent and selects a
`ReportScopeAdapter`. It does **not** enqueue the general Planner until the base
scope is confirmed.

Examples:

- `会前调研` selects `pre_event_briefing` immediately. The UI does not ask for
  `报告目的` again.
- `帮我汇总一下这周我的几个记录的数据` selects `period_summary`, resolves
  `这周` in the user's timezone, and does not ask for a generic purpose.
- a broad request such as `帮我做一份报告` uses the generic adapter and may ask
  the smallest necessary clarification.

An offer launched from an Event or Reka trigger already owns a primary target.
The scope page opens with that Event selected instead of showing unrelated
candidate selection first.

### 6.2 Step 1: pre-event base scope

For a manual `会前调研` request, the service returns the next three eligible
Events:

- `start_at` is later than `now` in the user's local-time interpretation;
- status is active/scheduled;
- cancelled, deleted, ended, and otherwise unavailable Events are excluded;
- candidates are sorted by start time ascending;
- at most three are returned.

The user selects exactly one primary Event. This primary Event is single-select
because the Report is preparation for one meeting. The screen then shows:

- selected Event title, local date/time, location, and bounded notes preview;
- recommended focus pills derived from the Event;
- optional free-form additional focus;
- optional supporting evidence through the existing typed Asset Picker.

Supporting Events, Contacts, generic Assets, and custom-skill records remain
multi-select. They never replace the single primary Event.

When no future Event exists, the screen shows a stable empty state and permits
the user to find another Event through the picker or leave the flow. It does not
silently select a past Event.

### 6.3 Event notes

`Notes` means the Event notes/remarks field presented by the product and stored
primarily as the Event `description` in the current service.

The complete owned notes value is available to the Scope Resolver, Planner, and
Generator. It is used to derive:

- public entities;
- comparison targets;
- research questions;
- additional focus areas;
- people or organizations explicitly requested for research.

The Web Search provider still receives bounded search queries rather than an
arbitrary application payload because its contract is query-based. The query
builder may use all relevant content from Event notes; it does not suppress the
notes on an assumption that they are private. Existing validation for person
identity and prohibited search categories remains in force.

For the accepted example:

```text
Event: 球队建设会议
Notes: 讨论中国足球的建设和发展，主要对比欧美足球体系
```

the Report scope must include Chinese, European, and American football-system
comparison questions. A generic `meeting preparation` scope is not valid.

### 6.4 Step 1: period-summary base scope

For a request such as `汇总这周我的几个记录`, the adapter resolves the
Report period using the user's timezone. This period is an internal evidence
range, not a public-search freshness filter.

The scope page displays record groups that actually contain aggregatable data
in the resolved period, for example:

- 喝水记录 · 8 条;
- 跑步记录 · 3 条;
- 跳舞记录 · 2 条;
- 消费记录 · 12 条.

Both levels support multi-select:

1. record/Skill type groups are multi-select;
2. individual records inside a group are multi-select.

The default selects all aggregatable records inside the explicit period. The
user can remove types or individual records and add other owned evidence. This
is not a general `select every Asset` action: Contacts, unrelated Events,
unstructured records without a useful aggregation contract, and records
outside the period are not implicitly selected.

The adapter derives a recommended plan around totals, trends, anomalies,
cross-record relationships, and next-period suggestions when supported by the
selected fields. Web Search defaults to off. It activates only when the user
requests an external comparison, professional standard, or other public
research.

### 6.5 Step 2: plan generation and confirmation

After Step 1 is confirmed, the service freezes a bounded `ReportScopeDraft` and
queues Planner. Planner receives the selected primary target, supporting
references, attention focus, applicable period, and Event notes before it
produces a recommendation.

Planner returns one recommended plan and at most two meaningful alternatives.
The recommended plan is preselected. The user can:

- `按推荐方案生成`;
- edit the plan's focus and evidence;
- return to Step 1 and change the base scope.

Changing the primary Event, selected records, supporting evidence, period, or
focus changes the scope revision and invalidates every plan generated for the
older scope. The client must not present or execute a stale plan.

### 6.6 Step 3: generation

Generation freezes one immutable `ReportExecutionPlan`. Repeated taps reuse the
same active generation attempt.

The progress UI distinguishes at least:

- collecting owned evidence;
- public research when applicable;
- organizing Report content;
- preparing illustration when applicable.

The Report becomes readable when trusted content and presentation are persisted.
Illustration readiness is an optional, independently observable capability.

## 7. Scope Adapter Architecture

Introduce a bounded adapter protocol equivalent to:

```python
class ReportScopeAdapter(Protocol):
    kind: str

    def resolve_initial_scope(context) -> ReportScopeDraft: ...
    def list_candidates(context) -> list[ScopeCandidate]: ...
    def validate_scope(draft, context) -> ScopeValidation: ...
    def build_planner_context(draft, context) -> PlannerContext: ...
```

Initial implementations are `PreEventScopeAdapter`,
`PeriodSummaryScopeAdapter`, and `GenericScopeAdapter`.

The adapter selects and validates scope. It does not call Web Search, generate
Report prose, or render HTML. Scope resolution remains a planning component and
uses existing typed `EvidenceReference(kind, id)` ownership checks.

### 7.1 Scope identity and invalidation

Each persisted scope draft contains:

```text
adapter_kind
primary_reference optional
supporting_references[]
report_period optional
attention_focus[]
additional_focus optional
revision
scope_hash
status
```

`scope_hash` is computed from normalized owner-scoped reference IDs, the
resolved period, focus values, and the current version of the primary Event
fields that affect planning, including notes. It excludes display-only
ordering.

Each generated plan records `generated_for_scope_hash`. Generation requires the
current draft revision and matching hash. A mismatch returns the latest scope
instead of creating a Report.

An Event edited after plan generation therefore invalidates the plan when its
title, time, location, participants, or notes changed materially.

### 7.2 API shape

The existing Run detail resource is extended rather than creating a parallel
workflow:

```text
scope_adapter
scope_draft
scope_revision
scope_status
scope_candidates
plan_generated_for_scope_hash
```

The interaction uses owner-scoped endpoints equivalent to:

```http
GET /api/report-generation-runs/{run_id}/scope-candidates
PUT /api/report-generation-runs/{run_id}/scope-draft
POST /api/report-generation-runs/{run_id}/prepare-plan
```

`prepare-plan` is idempotent for the same scope hash. The existing plan-draft
and generate endpoints retain optimistic revision checks.

## 8. Reka and Notification Integration

The pre-event trigger remains the source of truth. The production incident
proved that trigger execution and notification delivery already worked; the
missing boundary is Reka aggregation.

The Report source adapter for `GET /api/reka/signals` reads eligible current
trigger/report executions and upserts the existing nudge identity:

```text
report:<trigger_execution_id>
```

The same trigger execution may have both:

- a Notification delivery/history row;
- one active Reka Report insight.

These are two surfaces, not two business offers. Opening, dismissing, starting,
expiring, or completing the offer updates or derives from the same underlying
trigger/execution state. The system must not generate a duplicate Report or a
second paid research run when the user enters from the other surface.

The Reka card action opens the unified Report flow with the Event preselected.
It does not bypass scope confirmation or create a separate Report path.

Workflow receipts such as generic completion notifications remain excluded from
Reka.

## 9. Trusted Local Temporal Facts

### 9.1 Normalization

Every Event entering Planner or Generator is accompanied by typed temporal
facts derived from the stored UTC datetime and the Run's resolved user
timezone:

```text
timezone: Asia/Shanghai
local_date: 2026-08-11
local_start_time: 21:00
local_end_time: 22:00
local_interval_text: 21:00–22:00
duration_minutes: 60
source_kind: event
source_id: ...
```

The original UTC timestamp may remain available for internal ordering, but it
is not the display fact given to Report prose.

### 9.2 Claim validation

Numeric validation consumes a typed temporal allowlist derived from these
facts. It may approve the exact local date, start/end times, and duration with
the Event citation. It must not broadly trust every number embedded in an
arbitrary string.

The fix is therefore not `allow 13`. It aligns evidence normalization,
generation context, citations, and validation around the same local temporal
fact.

## 10. Durable Seedream Continuation

### 10.1 Chosen approach

Illustration is moved into a durable Workflow Job named equivalently to
`report_illustration`. It runs in a worker lane that can progress while the
parent Report content job waits. A detached in-process coroutine is explicitly
rejected because it is lost on worker restart and cannot reliably deduplicate a
paid provider call.

The content pipeline may wait for the child illustration result for at most 30
seconds:

- if ready, it persists the initially illustrated Report;
- if still running, it persists a readable Report with a trusted fixed-height
  placeholder and marks illustration `pending`;
- it does not cancel the child job at the 30-second boundary.

### 10.2 Job identity and execution

The illustration job uses a stable idempotency identity derived from the Report
generation attempt. One Report attempt may create at most one paid Seedream
generation.

The job performs:

1. load the immutable Report summary and approved illustration policy;
2. call Seedream outside a database transaction;
3. validate and normalize the image;
4. write through the existing object-storage abstraction;
5. acquire a short Report update transaction;
6. verify that the Report still expects this job and is `pending`;
7. rerender trusted HTML with the owned illustration URL;
8. update file references, illustration status, and generation metadata;
9. increment Report revision atomically.

Provider retries are bounded and occur only where the job system can prove that
another active attempt does not own the same idempotency key. A worker crash
after an ambiguous paid request must not blindly issue a second request without
the existing lease/recovery policy resolving ownership.

### 10.3 Report state

Report persistence gains explicit fields or equivalent indexed state:

```text
illustration_status: not_required | pending | ready | failed
illustration_job_id optional
revision integer
updated_at datetime
```

Provider/model/duration/error-category metadata remains under the bounded
generation context. Generated file IDs remain in the existing trusted Report
specification.

Report Run presentation states are:

```text
planning
generating_content
illustration_pending
completed
failed
```

`illustration_pending` means the Report is readable and may be opened. It is
not a failed or incomplete content result. Once the image job succeeds, the
Run/Report becomes `completed`. A terminal optional image failure also leaves a
readable completed Report with `illustration_status=failed`.

### 10.4 Placeholder and mobile refresh

The trusted renderer emits a stable illustration slot with a fixed reserved
height only when an image is requested and still pending. Light and dark
palettes provide a subtle placeholder without layout shift.

`GET /api/reports/{report_id}` returns at least the current Report revision and
illustration status. The mobile viewer:

1. polls only while the Report is open and illustration is pending;
2. pauses polling when the app is backgrounded and stops it on dispose;
3. detects a newer revision;
4. replaces only the trusted illustration slot in the WebView;
5. preserves scroll position and Report action state;
6. stops on `ready` or terminal `failed`.

If slot patching fails, the viewer may reload the stored HTML only after saving
and restoring the current scroll position. A visible full-page refresh is not
the normal path.

### 10.5 Sharing

Private Report HTML is revisioned and may receive the later image. Public share
pages remain immutable snapshots:

- a share created before the image arrives stays text-only;
- a share created after the image arrives contains the image;
- later Report rerendering does not silently mutate an already-issued share.

## 11. Failure and Recovery

- Candidate loading failure leaves the scope screen retryable and does not
  invoke Planner with an empty target.
- Planner failure preserves the confirmed scope and offers retry.
- Editing scope invalidates stale plans but does not discard the user's
  selections.
- Web Search partial failure exposes the affected scope and follows the
  existing required/optional research policy.
- Content generation failure creates no Report but preserves scope and plan for
  a retry.
- Repeated generation requests reuse the same active attempt.
- Illustration disabled or not applicable uses `not_required` and creates no
  placeholder.
- Illustration still running at 30 seconds remains `pending`; the parent does
  not cancel it.
- Terminal illustration failure removes the loading state and permits a
  separately idempotent retry without failing Report content.
- Failure of the Report source adapter in Reka does not hide valid overdue or
  rhythm signals.
- Deleted, cancelled, or no-longer-owned Events are filtered before plan
  execution and produce a specific scope blocker.

## 12. Observability and Performance

The existing stage timing contract is extended with bounded metrics for:

- scope-candidate query;
- scope resolution;
- Planner;
- evidence loading;
- Web Search;
- content generation;
- Seedream queue delay and provider duration;
- 30-second foreground wait outcome;
- Report rerender and mobile revision pickup.

Candidate recommendation is a database-only path and must not wait for a model.
Planner is called only after scope confirmation and is reused for an unchanged
scope hash. Deterministic selection edits do not start duplicate planning jobs.

Logs and metrics include Run, Report, trigger, and job correlation IDs and safe
categories. They exclude credentials, binary images, full provider responses,
and unbounded Event/Asset payloads.

## 13. Verification

### 13.1 Backend contract tests

Cover:

- manual `会前调研` selects the pre-event adapter without asking Report purpose;
- only the next three future active Events are returned, ordered by local start;
- past, cancelled, deleted, and ended Events are excluded;
- one primary Event plus multiple supporting references validates;
- Event notes influence entities, questions, and query generation;
- changing Event notes or selection invalidates a stale plan;
- period-summary local range resolution;
- multi-select record groups and individual records;
- default selection includes all and only aggregatable in-period records;
- period summary leaves Web Search off unless external research is requested;
- scope-hash idempotency and stale revision rejection;
- Report offer aggregation into Reka without duplicate execution;
- typed 21:00 local-time grounding and numeric claim validation;
- no broad numeric allowlisting from arbitrary evidence text.

### 13.2 Illustration job tests

Use fake providers and controllable clocks for:

- image ready inside 30 seconds;
- image still pending at 30 seconds without cancellation;
- later atomic Report rerender and revision increment;
- fixed placeholder only while pending;
- worker restart and lease recovery;
- duplicate enqueue and double-click idempotency;
- provider, image-validation, storage, and rerender failures;
- terminal image retry;
- existing share immutability and later share inclusion;
- exactly one generated file reference after success.

### 13.3 Mobile tests

Cover:

- scope-first three-step stepper;
- next-three Event recommendation and single primary selection;
- multi-select supporting Asset Picker;
- period-summary group and record multi-select with default selection;
- plan invalidation when returning to edit scope;
- Reka and Notification entry routes resolving the same offer;
- fixed-height pending illustration in light and dark themes;
- polling lifecycle, slot-only patch, preserved scroll, and terminal stop;
- retry UI for scope, Planner, content, research, and illustration failures.

### 13.4 Production-equivalent real-device acceptance

Using the Theme V2 build and the `1@1.com` acceptance account:

1. Create a future Event at 21:00 with football-system comparison notes.
2. Confirm one pre-event trigger, one Notification, and one active Reka insight.
3. Open from Reka and verify the Event is preselected.
4. Start manually with `会前调研` and verify only the next three future Events.
5. Select the football Event and verify its notes shape the plan and Web Search.
6. Generate a Report and verify 21:00 remains 21:00 with no numeric-claim error.
7. Generate one illustration within 30 seconds.
8. Force one illustration beyond 30 seconds, open the readable Report, and
   observe automatic slot-only backfill without a scroll jump.
9. Force a worker restart during pending illustration and verify recovery
   without duplicate images.
10. Request `汇总这周我的几个记录`, verify multi-select defaults, and generate
    a record-backed period summary without unnecessary Web Search.

## 14. Rollout and Completion

Delivery order is:

1. scope data contracts, adapters, and temporal facts;
2. scope-first mobile stepper and candidate selection;
3. Reka Report adapter and shared offer lifecycle;
4. durable illustration job and dedicated worker lane;
5. Report revision API and viewer slot refresh;
6. deterministic integration tests;
7. Theme V2 local-device acceptance;
8. production-equivalent canary with bounded real provider calls.

Rollback switches the new scope adapters, Reka Report aggregation, and async
illustration worker independently. Existing Reports and share snapshots remain
readable.

This slice is complete only when:

- manual Report plans are generated after, not before, type-specific scope;
- pre-event recommendations use only the next three future Events;
- Event notes materially shape research and Report content;
- period-summary types and records are multi-select with safe defaults;
- Reka and Notifications expose the same pre-event offer without duplication;
- local Event time is grounded and validated consistently;
- a readable Report is available after at most the 30-second illustration wait;
- pending Seedream work continues durably and backfills an open Report;
- all automated and real-device acceptance scenarios above pass.
