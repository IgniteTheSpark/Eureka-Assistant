# Theme V2 Legacy Agent Migration Design

**Date:** 2026-08-05

**Status:** Approved for implementation

## 1. Goal

Restore the complete mature interactive Agent architecture inside Theme V2
without reverting the Theme V2 product shell, runtime reliability work, or card
presentation.

The legacy interactive Agent behavior is the behavioral source of truth:

- the Flash Capture pipeline;
- the unified Chat pipeline used by every Session type;
- the Flash dispatcher, intent normalizer, built-in skills, and dynamic custom
  skill factory;
- the internal Eureka CRUD MCP server and its tool contracts;
- the legacy Asset, Event, Contact, InputTurn, UserSkill, and provenance
  semantics;
- permissive custom-skill capture behavior;
- natural-language create, query, update, and delete;
- general QA that replies without creating an asset;
- contact disambiguation and pending confirmation.

Theme V2 remains the platform source of truth for:

- the isolated service and MySQL deployment;
- durable jobs, retry, idempotency, outbox, and SSE;
- persisted running/failed Agent message states;
- the physical daily Flash Session;
- the current Theme V2 card components and visual language;
- the current Theme V2 Report implementation.

This design supersedes the Agent, Chat-provider, Flash-chat, and strict
Agent-write schema-validation decisions in
`2026-08-05-theme-v2-core-workflow-parity-design.md`. Its time, Timeline,
Flash-count, Report-container, and unrelated presentation decisions remain
valid unless they conflict with this document.

## 2. Scope

### 2.1 In scope

- migrate the legacy normal Chat Assistant;
- migrate the legacy Flash Capture pipeline;
- migrate the Flash dispatcher and intent normalization;
- migrate the legacy built-in Flash skills;
- migrate the custom-skill runtime generated from `UserSkill` metadata;
- preserve the internal Eureka CRUD MCP server as a runtime dependency;
- adapt the internal MCP implementations to Theme V2 models and services;
- restore first-class Contact behavior;
- restore first-class Event behavior and attendee/contact matching;
- restore generic Asset and typed query-field behavior;
- restore Session/InputTurn provenance;
- restore contact `pending_confirmation` and make it durable;
- use one Chat pipeline for both ordinary Chat Sessions and daily Flash
  Sessions;
- keep Chat messages inside a Flash Session from incrementing the Flash count;
- make hardware captures appear live in an already-open daily Flash Session;
- preserve Agent work and loading state when the user leaves and returns;
- retain Theme V2 card presentation through an adapter/presenter layer;
- migrate current Theme V2 data needed by these contracts.

### 2.2 Out of scope

- external third-party MCP servers;
- Connected Apps and credential management;
- Task Skill and external action execution;
- Suggest Skill, which will be designed after parity is restored;
- Morning Briefing;
- migration of the legacy Report pipeline;
- replacement of the current Theme V2 Report implementation;
- partial or word-by-word ASR display;
- creation of an empty daily Flash Session before the first visible capture;
- reusing the legacy card widgets or visual system.

## 3. Authoritative Pipeline Boundary

There are two interactive Agent pipelines, not three.

### 3.1 Flash Capture pipeline

The Flash Capture pipeline handles a new capture initiated from hardware or
the product's explicit new-Flash surface.

```text
new capture
  -> ASR final
  -> Flash dispatcher
  -> normalized intent list
  -> built-in or dynamic Flash skills
  -> internal CRUD MCP
  -> Flash aggregation and reply
  -> Theme V2 card presenter
```

Each invocation represents one new Flash and increments the daily capture
count once, regardless of how many assets it derives.

The pipeline preserves the legacy behavior:

- one input may contain multiple independent intents;
- sibling intent skills may execute in parallel;
- create, query, update, and delete are all valid Flash operations;
- a general question routes to QA, returns a direct answer, and creates no
  Asset, Event, or Contact;
- a successful mutation is never claimed before its MCP result succeeds;
- the aggregator reports actual results and renders all resulting cards;
- custom-skill extraction is best effort and cannot fail only because optional
  data was not spoken.

Flash remains a capture surface. Open-ended research, long-form work, and
external actions do not belong to this pipeline.

### 3.2 Unified Chat pipeline

Every typed message sent inside a Session uses the same migrated legacy Chat
Assistant and `/api/chat` pipeline.

This is true for:

- a normal `session_type=chat` Session;
- a physical daily `session_type=flash` Session;
- a Session anchored to an Event, Contact, Asset, or other supported subject.

The Session type changes the context supplied to the Assistant; it does not
select a different Agent pipeline.

For an existing daily Flash Session, the Chat context includes:

- recent Session messages;
- the day's visible capture InputTurns;
- assets and events created from those captures;
- contacts created or updated from those captures;
- unresolved pending contact actions;
- normal attached/subject context supported by the legacy Assistant.

A Chat message inside a Flash Session:

- is persisted as a normal user message;
- creates an `InputTurn` for provenance;
- may query or mutate records through the same internal MCP tools;
- may answer a general question without creating an asset;
- does not create a `CaptureRecording`;
- does not increment the Flash count;
- does not run the Flash dispatcher merely because its Session type is Flash.

The legacy bulk-paste optimization remains allowed inside the Chat pipeline:
when the normal Assistant detects a true bulk import rather than a
conversation, it may delegate that single turn to the Flash extraction
pipeline for parallel record extraction. This is an internal Chat optimization,
not a third Session-chat pipeline, and it still does not increment the hardware
Flash count.

### 3.3 Removal of the Theme V2 Flash-chat fork

The current Theme V2 read-only `FlashChatProvider` and its separate behavioral
contract are not authoritative.

`POST /api/flash/sessions/{date}/chat` may remain temporarily as a mobile
compatibility route, but it must resolve the physical daily Session and delegate
to the same Chat service used by `POST /api/chat`. It must not maintain a
separate prompt, message table, provider, or read-only capability set.

New mobile code should send the physical Session ID to `/api/chat`.

## 4. Legacy Agent Components to Migrate

The migration preserves behavior and stable contracts from the following
legacy areas, while adapting imports and infrastructure to Theme V2:

- `agents/assistant.py`;
- `agents/flash_pipeline.py`;
- `agents/flash_reply.py`;
- `agents/skill_factory.py`;
- `agents/intent_normalizer.py`;
- `skills/flash-dispatcher`;
- `skills/flash-todo-skill`;
- `skills/flash-event-skill`;
- `skills/flash-expense-skill`;
- `skills/flash-contact-skill`;
- `skills/flash-idea-skill`;
- `skills/flash-notes-skill`;
- `skills/flash-misc-skill`;
- `skills/flash-qa-skill`;
- the internal portion of `agents/mcp_toolset.py`;
- the internal tool schemas in `mcp_server/server.py`;
- the CRUD behavior in `mcp_server/tools.py`;
- relevant legacy evaluation scenarios and regression tests.

The migrated code must not import or connect to the legacy service at runtime.
It lives within the Theme V2 deployment and uses Theme V2 configuration,
database access, jobs, and observability.

## 5. Internal Eureka CRUD MCP

### 5.1 Runtime role

The internal CRUD MCP server is a required part of the migrated architecture.
It is distinct from external third-party MCP connectivity.

The initial migration keeps the local stdio topology because it preserves the
legacy Agent/tool integration with the least behavioral change:

```text
Theme V2 Agent or worker
  -> ADK MCPToolset
  -> local Eureka MCP subprocess
  -> Theme V2 domain services
  -> Theme V2 MySQL database
```

Collapsing the internal MCP transport into in-process function tools may be
evaluated only after parity is proven. It is not part of this migration.

### 5.2 Tool surface

The migrated server preserves the legacy tool names and compatible argument
and result shapes, including:

- `tool_create_asset`;
- `tool_create_todo`;
- `tool_create_note`;
- `tool_query_asset`;
- `tool_query_digest`;
- `tool_update_asset`;
- `tool_delete_asset`;
- `tool_create_contact`;
- `tool_query_contact`;
- `tool_update_contact`;
- `tool_delete_contact`;
- `tool_create_event`;
- `tool_query_event`;
- `tool_get_event`;
- `tool_update_event`;
- `tool_delete_event`;
- attendee create/update/delete tools;
- `tool_query_input_turn`;
- `tool_get_input_turn`.

The implementation behind those tools is rewritten against Theme V2 domain
services. It must not import legacy `db.models` or `AsyncSessionLocal`.

### 5.3 User isolation

`user_id` is trusted only when injected by the Theme V2 server runtime. Model
output may not choose the effective user.

Every tool query and mutation must:

- scope by the authenticated user;
- reject or ignore a model-supplied conflicting user ID;
- verify ownership of referenced Session, Asset, Contact, Event, and InputTurn;
- avoid exposing another user's candidate records in ambiguous searches.

### 5.4 Transactions, idempotency, and lifecycle

Each MCP mutation owns a Theme V2 transaction and emits its domain outbox event
in that transaction.

Each tool execution receives or derives a stable idempotency key from the Agent
turn and tool-call index. Retrying a durable Agent job may replay a completed
tool result, but it may not create, update, or delete twice.

Each API/worker process that hosts an Agent manages one lazy internal MCP
subprocess. Startup readiness, unexpected-exit recovery, and shutdown cleanup
are required. If the internal MCP remains unavailable, the durable Agent
message reaches `failed`; it may not stay `running` indefinitely.

External MCP configurations are not loaded, and Task Skill is not attached to
any migrated Agent.

## 6. Domain and Asset Contracts

### 6.1 Skill registry

Theme V2 restores the mature skill-registry semantics:

- `GlobalSkill` defines built-in/system capabilities;
- `UserSkill` represents a user's enabled built-in or custom skill;
- a skill carries its machine name, display name, payload schema, render hints,
  queryable fields, ordering, and enabled state;
- QA is a system skill with no persisted asset payload;
- Contact and Event have skill/dispatch presence but are stored as first-class
  domain rows rather than generic assets;
- external-reference/task skills remain disabled in this phase.

The dispatcher receives the current user's enabled custom-skill catalog, so a
skill created in the wizard can be captured without adding a new Python skill
file.

### 6.2 Asset

Generic assets retain the legacy semantic facts:

- owning user and `UserSkill`;
- arbitrary partial payload;
- source Session and InputTurn provenance;
- domain;
- fuzzy `period`;
- exact `occurred_at`;
- effective/timeline date semantics;
- creation and update timestamps.

The current Theme V2 time and Timeline design remains authoritative where it
does not contradict the permissive payload rules below.

### 6.3 Queryable fields

Theme V2 restores `AssetField` or an equivalent typed projection for custom
asset search. It is rebuilt after an asset payload update and supports the
legacy `queryable_fields` contract.

The Assistant must be able to query custom skills without scanning every JSON
payload in model context.

### 6.4 InputTurn provenance

Every capture and every Chat user message creates an InputTurn.

The source is a modality/context fact, separate from Session type, for example:

- `voice` for a hardware transcript;
- `typed` for normal Chat;
- `typed` plus Flash Session ownership for Chat inside the daily Flash Session;
- `imported` for supported import paths.

Assets, Contacts, and Events created by an Agent carry the source InputTurn ID.
This enables source replay, “刚才那个” resolution, auditing, cards, and repair.

## 7. Permissive Skill Wizard and Agent Writes

### 7.1 Product rule

A user creates a custom Skill to capture a class of information. A Flash must
not fail merely because the user did not speak every field that the wizard or
designer once marked required.

The current Theme V2 hard-required-field behavior is removed for custom skills.

### 7.2 Wizard behavior

- the wizard no longer requires the user to choose mandatory capture fields;
- newly generated custom fields default to optional;
- `primary_field` remains presentation metadata, not a storage invariant;
- the wizard may describe important fields, but importance must not become a
  hard Agent-write prerequisite;
- existing custom-skill top-level `required` arrays are cleared during data
  migration, or ignored by the permissive Agent-write profile;
- legacy shorthand `field.required=true` may be retained only for compatibility
  display and may not block Agent capture.

### 7.3 Agent-write validation profile

Internal MCP Agent writes use a permissive profile:

- require a JSON object and a registered skill;
- accept a partial payload;
- omit facts the user did not state;
- best-effort normalize values that can be normalized without guessing;
- never invent a missing amount, date, clock, contact fact, or other material
  value;
- do not reject the whole capture only because a custom payload lacks a schema
  field;
- do not reject the whole capture only because the custom schema uses
  `additionalProperties: false`;
- preserve the source text/provenance needed for fallback presentation.

Manual editing may still validate the type of a value the user explicitly
entered. It may not retroactively make an already captured partial asset
invalid.

### 7.4 Custom-skill fallback

When a dynamic custom-skill Agent fails to extract a declared field but the
dispatcher confidently selected the custom skill:

- create the asset under that skill;
- keep the spoken source fragment through InputTurn/provenance;
- persist any grounded fields that were extracted;
- let the Theme V2 presenter use a source-text summary when the configured
  primary field is absent;
- optionally ask a short follow-up after successful creation;
- treat the user's later answer as an update to the existing asset, not a
  second create.

### 7.5 Built-in domain rules

Permissive custom-skill capture does not remove mature built-in invariants.
Rules owned by the legacy built-in skills remain authoritative, including:

- Contact needs an identifiable name;
- Contact facts may not be invented;
- Event/Todo routing follows the legacy time-range rules;
- Expense behavior follows the legacy Expense skill;
- fuzzy periods do not become invented clock times;
- QA creates no asset.

## 8. Natural-language CRUD and QA

The Flash Capture and unified Chat pipelines both support create, query,
update, and delete through their own legacy prompts and routing behavior.

Target resolution prioritizes:

1. an explicit entity/card ID;
2. a referenced result from recent Session history;
3. the source InputTurn and assets for “刚才那个”;
4. exact field/name/title matches;
5. safe candidate search.

Mutation is allowed only when the selected target is safe according to the
corresponding legacy skill. No Agent may claim success before a successful MCP
result.

A general knowledge question such as “地球为什么是圆的” produces an Agent
message only. A personal-data question queries the user's records and also
creates no new asset. A later explicit request such as “把刚才的回答存成随记”
creates a new asset using the previous Agent reply as source content.

## 9. Contact and Pending Confirmation

Contact is a first-class type with legacy-compatible fields and behavior:

- name;
- phone;
- company;
- title;
- email;
- append-only notes;
- mergeable supported social handles;
- source InputTurn provenance.

For create/update-style contact information, exact normalized name matching is
authoritative:

- zero exact matches: create a new Contact;
- one exact match: update that Contact;
- two or more exact matches: mutate nothing and return
  `pending_confirmation`.

For delete:

- zero exact matches: report not found;
- one exact match: delete that Contact;
- two or more exact matches: delete nothing and return
  `pending_confirmation`.

Theme V2 persists pending contact actions with:

- operation;
- candidate Contact IDs and distinguishing snapshots;
- the extracted patch or delete intent;
- owning user, Session, InputTurn, and Agent turn;
- pending/resolved/cancelled status;
- selected Contact and resolution source.

The user may resolve the same pending action by:

- tapping a Theme V2 candidate card;
- replying “第一个”, “字节的 Kevin”, or another unambiguous description;
- cancelling with natural language.

Resolution is limited to the stored candidate set and is idempotent. Leaving
and returning to the Session preserves the pending state.

Event attendee matching retains the legacy safety rule: bind only one exact
Contact match. Zero or multiple exact matches keep the spoken attendee name
unbound. Deleting a Contact detaches references while preserving readable
attendee name snapshots.

## 10. Physical Daily Flash Session

### 10.1 Identity and creation

Theme V2 stores a real `session_type=flash` Session with a stable UUID and a
user-local calendar date. A database unique constraint prevents two daily
Flash Sessions for the same user/date.

No Session is pre-created. If the user has no Flash for the day, there is no
daily Session row and no entry to open.

For a hardware recording, the Session becomes visible only when final ASR text
is ready to be shown. Recording receipt, upload, and in-progress ASR do not
create a visible transcript message.

The recording's capture timestamp, converted through the user's timezone,
determines the owning daily Session date. Agent completion time does not.

### 10.2 First visible capture transaction

At ASR final, one transaction:

1. gets or creates the daily Flash Session;
2. creates the voice InputTurn with the final ASR text;
3. creates the persisted user transcript message;
4. creates the persisted Agent `running` placeholder;
5. links the CaptureRecording to the real Session and InputTurn;
6. enqueues or exposes the durable Flash Agent job;
7. writes an outbox invalidation event.

This guarantees that an open Session first sees the ASR source text together
with the following Agent loading state. Partial ASR is never shown.

### 10.3 Counts and Chat

The Flash count counts capture recordings only.

Messages sent through `/api/chat` while the daily Session is open:

- append to that Session transcript;
- create typed InputTurns;
- may create or mutate records through the Chat Assistant;
- never create capture recordings;
- never increment the Flash count.

### 10.4 Leave and return

Agent execution is owned by a durable server task/job, not the SSE connection.
Leaving the Session or disconnecting the app does not cancel it.

On re-entry, the Session API returns persisted messages with their status,
cards, pending actions, and result snapshots. A still-running Agent remains
visibly loading; a completed Agent shows its result; a terminal failure shows a
retryable error.

## 11. Unified Session Message Model

Both capture output and Chat use the Theme V2 Session transcript model.

A message records at least:

- Session and user;
- role;
- InputTurn/Agent-turn linkage;
- text;
- `running`, `waiting_confirmation`, `done`, or `failed` status;
- elapsed/token metadata where available;
- persisted Theme V2 card DTOs/result blocks;
- stable ordering and timestamps.

The current separate `FlashChatMessage` storage path is migrated into the
unified Session message model and then retired.

Within one Session, turn ordering must preserve conversation semantics. A user
may send another message while prior work is visible as running, but dependent
Agent execution must not resolve “刚才那个” against an incomplete earlier turn.

## 12. Theme V2 Card Presentation

Legacy Agent and MCP results do not directly control the final UI.

```text
legacy-compatible MCP result
  -> normalized domain result
  -> Theme V2 Card Presenter
  -> persisted Theme V2 Card DTO
  -> existing Theme V2 card components
```

The presenter supports:

- Asset create/update/delete;
- Event results;
- Contact results;
- read-only query results;
- contact pending candidates;
- partial success and failure states.

Legacy `render_spec` and `UserSkill` metadata provide semantic field roles,
labels, ordering, and optional icon hints. They do not restore the legacy card
layout, colors, or components.

Each persisted Card DTO contains a minimum execution-time display snapshot plus
an optional live entity reference. This keeps historical receipts readable
after a record changes or is deleted while still allowing navigation to a live
detail page when the record exists.

Card rendering failure may not erase the Agent's textual answer or make the
Agent turn fail after a successful mutation.

## 13. Realtime Delivery and Recovery

Theme V2 outbox/SSE remains the realtime mechanism.

Relevant events include daily Session creation, message creation, Agent status
change, card/result availability, and pending-action resolution. Events carry
the Session ID and a monotonic revision/cursor.

When the mobile client is already viewing the matching Session, it applies the
delta or performs a debounced Session refetch. The database/API response is the
authority; SSE is an invalidation/live-delivery channel.

Reconnect performs cursor recovery where supported and then refetches the
active Session to close any gap. Duplicate events cannot create duplicate
messages or cards.

## 14. API Direction

The target public behavior includes:

- new Flash/capture APIs returning a recording/capture ID before ASR completes;
- daily Flash Session list/detail APIs returning a physical Session UUID;
- `/api/chat` accepting any owned Session ID, including a Flash Session;
- the existing Session history and message APIs returning unified persisted
  transcripts;
- contact pending resolve/cancel endpoints;
- notification/SSE delivery for Session invalidation.

The recording ID is never returned as if it were the daily Session ID.

The date-based Flash Session endpoint may remain as a compatibility lookup, but
new contracts and mobile state use the physical Session UUID.

## 15. Existing Theme V2 Data Migration

The migration is additive and idempotent.

It must:

- create one physical daily Flash Session for every user/date with an existing
  visible capture;
- link existing CaptureRecordings and CaptureTurns to those Sessions;
- convert existing Flash chat rows into unified Session messages;
- preserve chronological order and terminal/running state where recoverable;
- convert current Theme V2 contact-shaped assets into first-class Contacts;
- preserve a mapping from legacy contact-asset IDs to new Contact IDs while
  rewriting card references;
- restore/seed the legacy built-in skill catalog required by the Agent;
- relax existing custom-skill required constraints for Agent writes;
- build queryable AssetField projections for existing assets;
- leave current Theme V2 Report data and presentation untouched.

Same-name Contacts are not automatically merged during migration.

## 16. Rollout Strategy

Migration is implemented in vertical, reversible tranches:

1. port legacy eval fixtures and freeze behavioral contracts;
2. add/repair domain models and migration paths;
3. port the internal MCP server against Theme V2 services;
4. migrate the normal Chat Assistant and `/api/chat` durability;
5. migrate the Flash Capture dispatcher, skills, and aggregation;
6. unify daily Flash Session chat with `/api/chat`;
7. introduce the Theme V2 Card Presenter adapters;
8. connect ASR-final live Session insertion and SSE recovery;
9. migrate current Theme V2 data;
10. enable the migrated pipelines behind independent feature flags and remove
    the simplified/read-only Theme V2 Agent paths after parity passes.

No production shadow path may execute mutations twice. Comparison runs use
fixtures, read-only planning output, or isolated data.

## 17. Verification and Acceptance

### 17.1 Pipeline routing

- a new hardware/App Flash uses the Flash Capture pipeline;
- a typed message in an ordinary Chat Session uses the Chat pipeline;
- a typed message in a daily Flash Session uses the same Chat pipeline;
- Chat inside a Flash Session does not increment the Flash count;
- a normal Chat bulk import may use the legacy internal bulk-delegation branch
  without becoming a capture.

### 17.2 CRUD and QA

- Flash Capture and Chat both perform natural-language create, query, update,
  and delete according to their legacy rules;
- “刚才那个” resolves against persisted Session/tool provenance;
- a follow-up that supplies missing fields updates the existing asset;
- a general QA turn returns an answer and creates no record;
- “把刚才回答存成随记” creates only after that explicit instruction;
- successful text never claims a mutation that did not succeed.

### 17.3 Custom skills

- a custom Skill capture succeeds with only a subset of declared fields;
- a missing primary/previously-required field does not fail Flash processing;
- absent facts are not invented;
- the resulting Theme V2 card uses a safe source-text fallback;
- later supplied fields update the existing record;
- custom assets remain queryable through the internal MCP.

### 17.4 Contacts

- Contact is stored independently from Asset;
- zero/one/multiple exact-name cases follow the legacy rules;
- multiple candidates mutate nothing;
- candidate-card and natural-language resolution use the same pending action;
- pending survives leave/re-entry;
- notes append and socials merge;
- attendee binding uses a unique exact Contact only.

### 17.5 Daily Session and realtime

- no capture means no daily Session and no entry;
- ASR in progress creates no visible transcript text;
- ASR final inserts the source text and persisted Agent loading without manual
  refresh;
- multiple captures on the same local day use one physical Session;
- leaving and returning preserves running, completed, failed, and pending state;
- SSE reconnect/refetch creates no duplicates;
- recording IDs and Session IDs remain distinct.

### 17.6 Runtime boundaries

- every interactive Agent uses the internal CRUD MCP server;
- internal MCP tools operate on Theme V2 models and MySQL;
- authenticated user scope cannot be overridden by model output;
- external MCP, Task Skill, Connected Apps, and Morning Briefing do not start;
- Theme V2 Report behavior and data remain unchanged;
- Theme V2 card components remain the only shipped card presentation.

## 18. Completion Definition

The migration is complete when the legacy behavioral evaluation suite and the
Theme V2 durability/UI acceptance suite both pass against the Theme V2 stack,
with only the intentionally excluded external Task/MCP, Suggest, Morning
Briefing, and legacy Report behavior absent.

Code similarity to the legacy backend is not the success criterion. Pipeline
boundaries, tool contracts, asset semantics, user-visible behavior, and
reliability are.
