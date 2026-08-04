# Theme V2 Core Workflow Parity Design

**Date:** 2026-08-05

**Status:** Approved for direct implementation

## Goal

Restore the mature legacy behavior that was lost when Theme V2 moved onto its
isolated service, while keeping the current Theme V2 service boundaries and UI
architecture intact.

The deliverable covers three independently testable areas:

1. asset time semantics, Timeline presentation, and Flash capture counts;
2. ordinary Session persistence and the Chat pipeline;
3. the Report container and schema-authoritative asset fields.

## Constraints

- Theme V2 remains an independent Docker stack. The legacy Docker service may
  stay stopped and must not be used as a runtime proxy.
- Do not redesign the global mobile or service architecture.
- Reuse the mature legacy contracts and behavior where they already exist.
- Flash counts include capture recordings only. Flash Session chat messages do
  not increment the count.
- Fuzzy periods must never be converted into invented clock times.
- Existing unrelated dirty worktree changes must be preserved.

## 1. Authoritative Asset Time

### 1.1 Stored facts

Theme V2 `assets` gains the two mature legacy facts:

- `occurred_at`: the exact user-stated occurrence time, including timezone at
  the API boundary and stored as UTC-naive in MySQL;
- `period`: one of `凌晨`, `上午`, `中午`, `下午`, `晚上` when the user stated a
  fuzzy period without an exact clock.

The existing `effective_at` remains for compatibility with manual and Report
mutations. It is not used as evidence that the user stated a clock unless the
write explicitly supplied a full timestamp.

`created_at` remains audit/capture time and is never overwritten to simulate a
different occurrence date.

### 1.2 Effective-time chain

The Theme V2 service becomes the only owner of Timeline derivation. For an
asset, its user-facing effective time is resolved in this order:

1. `asset.occurred_at`;
2. `asset.effective_at`;
3. `render_spec.timeline_anchor` if it names a parseable payload field;
4. a schema property with `format: date-time` or `format: date`;
5. built-in anchors (`todo.due_date`, `expense.at`, `expense.date`);
6. `asset.created_at`.

A date-only anchor is represented at local midnight for grouping, but
`has_clock_time` remains false. A fuzzy `period` places the record in the
correct band without a visible `HH:mm`. If the user said no time at all, the
capture time remains the display fallback, matching the mature flow.

### 1.3 Capture extraction

Each generated capture record includes an internal `source_text` fragment.
The fragment is not persisted into the asset payload. The LiteLLM prompt gets a
timezone-aware `reference_datetime`, not only a date.

After model extraction, a deterministic parser ports the legacy rules:

- `刚刚`, `刚才`, `现在`, `这会儿` -> exact reference time;
- relative days (`昨天`, `前天`, `明天`, `后天`) -> anchored local date;
- `晚上8点`, `下午3:20` -> exact local time;
- `早上`, `下午`, `晚上` without a clock -> `period` only;
- no temporal phrase -> no invented semantic time.

The deterministic result fills missing temporal metadata but does not replace a
valid, grounded model result.

### 1.4 Timeline API and presentation

Theme V2 adds `GET /api/timeline`. It returns the existing mobile
`TimelineItem` contract, including:

- `effective_at` serialized as UTC `Z`;
- `period`;
- `has_clock_time`;
- `has_scheduled_time`;
- `title` built from the skill render spec and `display_name`, never a raw
  machine name fallback;
- capture input entries used by the Flash counter.

The Theme V2 Calendar consumes this API instead of rebuilding the Timeline from
raw `/assets`, `/events`, and `/flash/recordings` responses.

## 2. Flash Counter Contract

The Flash counter counts `capture_recordings` for the local calendar day. It
does not count `flash_chat_messages`.

All capture and daily-session timestamps are serialized as timezone-qualified
UTC strings. This prevents a recording created at `2026-08-04T16:13Z` from
being parsed as local `2026-08-04 16:13`; it correctly lands on local
2026-08-05 00:13.

Acceptance example:

- three hardware captures on August 5;
- two user questions inside the August 5 Flash Session;
- Calendar shows `⚡ 3` beside August 5.

## 3. Ordinary Sessions and Chat

### 3.1 Persistence

Theme V2 adds focused `sessions` and `session_messages` tables. A Session owns
its transcript and optional context asset IDs. Assets created by a chat turn
carry Session and input-turn provenance so their source can reopen the correct
conversation.

The API implements the mobile contract already used by `ChatController`:

- `GET /api/sessions`;
- `POST /api/sessions`;
- `GET /api/sessions/{id}`;
- `GET /api/sessions/{id}/messages`;
- `PATCH /api/sessions/{id}/context`;
- `DELETE /api/sessions/{id}`;
- `GET /api/sessions/opening-hint`;
- `POST /api/chat` as SSE.

Deleting a Session deletes the transcript but detaches, rather than deletes,
its assets.

### 3.2 Chat provider

The Chat domain follows the current Theme V2 LiteLLM provider pattern and uses
the configured DeepSeek-compatible model. It does not import the legacy Google
ADK runtime.

The bounded tool loop supports the product-critical operations:

- query current-user skills and assets;
- create schema-valid assets;
- query and create events;
- answer grounded questions using Session history and attached context.

SSE frames preserve the existing client contract: `meta`, `token`,
`tool_call`, `tool_result`, `error`, and `done`. The user may leave while a
turn is running; persisted status and messages allow the Session to recover on
re-entry.

## 4. Report as a Normal Container

Report becomes `LibraryContainerType.report`, a normal system container in the
same collection as Todo, Notes, Event, and Contact.

- It is default-pinned and consumes one of the six pinned positions.
- It may be removed and added again through the existing pinned-container UI.
- Existing pinned preferences migrate once to include Report.
- The standalone full-width Report entry is removed.
- Opening the Report container continues to use `ReportContainerPage`.

## 5. Schema-authoritative Asset Fields

For a skill with an object schema and `additionalProperties: false`:

- create and update reject payload keys outside `properties`;
- mobile detail and editor surfaces expose declared fields only;
- service-owned provenance stays in typed columns, not payload fields.

Existing acceptance seed keys named `acceptance_marker` are removed from local
Theme V2 data. The running skill schema itself is not changed.

## 6. Existing Data Repair

The local Theme V2 database repair is deliberately narrow:

- remove `acceptance_marker` from existing asset payloads;
- set the 200 ml water record to the capture/reference time;
- set the 300 ml water record to August 4 at 20:00 local;
- keep 600 ml as August 4 `下午` without a fake clock;
- keep 400 ml as August 4 `上午` without a fake clock.

## 7. Verification

Automated coverage must prove:

- deterministic relative-time extraction and no fake fuzzy clocks;
- Timeline title uses display metadata, not machine names;
- UTC `Z` serialization keeps the Flash count on the correct local date;
- three captures plus two Flash chats produces a count of three;
- Session CRUD, owner scope, history replay, context updates, SSE chat, and
  leave/re-enter recovery;
- unknown schema fields are rejected and hidden;
- Report is a normal configurable pinned container;
- the current four water records render on the intended dates and bands.

Final acceptance includes rebuilding the isolated Docker stack, targeted
backend and Flutter suites, Flutter analysis, debug APK build, and real-device
verification on the connected Android phone.
