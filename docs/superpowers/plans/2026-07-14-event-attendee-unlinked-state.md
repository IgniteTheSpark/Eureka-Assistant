# Event Attendee Unlinked State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Keep EventCards free of unresolved-state noise while making bare-name attendees visible and optionally linkable from Event detail/edit with an automatic name search.

**Architecture:** Preserve the existing `contact_id == null` attendee model and Flash exact-match rules. Extend the shared attendee selector with an initial query and contact-name handoff, reuse the enriched attendee model in Event detail, and PATCH the existing attendee when the user links a contact. Card summary rendering remains unchanged.

**Tech Stack:** Flutter/Dart, Riverpod, `http` MockClient, FastAPI contract documentation, Markdown specs.

## Global Constraints

- `contact_id == null` is a valid long-lived attendee state, not a required task.
- EventCards never display `?`, `?N`, pending counts, or an extra status line.
- Calendar stream/month event items stay single-line.
- User-facing copy is `未关联联系人` and `关联`.
- Linking is optional and never interrupts Flash creation.
- A zero or ambiguous exact contact match remains a bare-name attendee; Flash never creates contacts.

---

### Task 1: Prefilled attendee resolution flow

**Files:**
- Modify: `mobile/test/event_attendees_test.dart`
- Modify: `mobile/lib/pages/event_attendees.dart`
- Modify: `mobile/lib/pages/create_asset.dart`

**Interfaces:**
- Produces: `showEventAttendeeSelector(..., String initialQuery = '', required CreateContactCallback onCreateContact)`.
- Produces: `CreateContactCallback(BuildContext context, String initialName)`.
- Consumes: existing `ContactForm(existing: {'name': initialName})` prefill behavior.

- [x] **Step 1: Write failing widget tests**

Add tests that open an unresolved `Alex Raw` attendee, tap `关联`, and assert the selector search field already contains `Alex Raw` and the first request is `/api/contacts?q=Alex+Raw&limit=20`. Add a no-results selector test whose create callback captures `initialName` and assert it receives the current search query.

- [x] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/event_attendees_test.dart --plain-name "event form preloads an unresolved attendee name when linking"`

Expected: FAIL because the selector search field is empty and the query is not passed to contact creation.

- [x] **Step 3: Implement the minimal selector API**

Initialize `_searchController` with `widget.initialQuery`, call `_load(widget.initialQuery.trim(), ...)` from `initState`, and invoke `widget.onCreateContact(context, _searchController.text.trim())`. In `EventForm._bindAttendee`, pass `target.nameRaw ?? target.displayName` as `initialQuery`. Open `ContactForm(existing: {'name': initialName})` when the callback receives a non-empty name.

- [x] **Step 4: Update copy in EventForm**

Replace `未绑定名片` with `未关联联系人` and `绑定名片` with `关联`. Update existing widget assertions without changing EventCard summary behavior.

- [x] **Step 5: Run attendee tests and verify GREEN**

Run: `flutter test test/event_attendees_test.dart`

Expected: all attendee tests pass.

### Task 2: Link bare-name attendees from Event detail

**Files:**
- Modify: `mobile/test/event_attendees_test.dart`
- Modify: `mobile/lib/render/asset_detail_sheet.dart`
- Modify: `mobile/lib/pages/event_attendees.dart`

**Interfaces:**
- Consumes: `EventAttendeeDraft.fromJson`, `showEventAttendeeSelector(initialQuery: ...)`, and the detail sheet's canonical `GET /api/events/{id}` hydration.
- Produces: `showAssetDetail(..., ApiClient? api)` for deterministic widget testing while production callers keep the default client.
- Produces: an Event-detail attendee list with optional `onLink` behavior and no card-level status.

- [x] **Step 1: Write a failing Event detail test**

Open `showAssetDetail` for an event using an injected MockClient. Return an event with a bare-name attendee and assert the detail contains `Kevin`, `未关联联系人`, and `关联`. Tap `关联`, choose one of two Kevin contacts, save, and assert `PATCH /api/events/event-1/attendees/a1 {"contact_id":"c-google"}`.

- [x] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/event_attendees_test.dart --plain-name "event detail lists and links a bare-name attendee"`

Expected: FAIL because Event detail currently treats `attendees` as a generic list and has no link action.

- [x] **Step 3: Implement dedicated Event detail rendering**

Import attendee models/selectors into `asset_detail_sheet.dart`. Add an optional injected `ApiClient` to `showAssetDetail`/`_AssetView` and only close clients created internally. Render the `attendees` payload as named rows instead of generic chips. For unresolved rows show `未关联联系人` plus `关联`; for resolved rows show `contact_summary`. Do not render any unresolved indicator in `_hero` or `SkillCard`.

- [x] **Step 4: Implement direct binding and refresh**

On `关联`, open the single-select selector with the attendee's bare name. PATCH the existing attendee ID, then rehydrate `/api/events/{id}`, call `bumpData()`, and preserve the original row on failure. Allow ContactForm creation with the bare name prefilled.

- [x] **Step 5: Run focused and regression tests**

Run: `flutter test test/event_attendees_test.dart test/event_card_summary_test.dart test/timeline_event_summary_test.dart`

Expected: all tests pass; card summary tests remain unchanged.

### Task 3: Synchronize source-of-truth specifications

**Files:**
- Modify: `spec/02-data-model.md`
- Modify: `spec/03-api-reference.md`
- Modify: `spec/04-frontend.md`
- Modify: `spec/handoffs/handoff-event-attendees.md`

**Interfaces:**
- Documents the existing API shape and the UI behavior implemented by Tasks 1–2.

- [x] **Step 1: Update attendee semantics**

State explicitly that `contact_id == null` is a valid long-lived bare-name attendee, not an incomplete task. Keep the existing unique-exact-match Flash rule.

- [x] **Step 2: Update UI requirements**

Specify that cards show only the normal `First +N` summary, never unresolved markers. Specify `未关联联系人` / `关联` in Event detail/edit, automatic name search, optional contact creation, and no forced resolution.

- [x] **Step 3: Verify documentation consistency**

Run: `rg -n "未绑定名片|待确认|\\?N" spec/02-data-model.md spec/03-api-reference.md spec/04-frontend.md spec/handoffs/handoff-event-attendees.md`

Expected: no stale requirement that cards or Event UI use `未绑定名片`, `待确认`, or `?N`; historical/rejection wording is allowed only when explicitly negated.

### Task 4: Final verification and commit

**Files:**
- Verify all files changed by Tasks 1–3.

- [x] **Step 1: Format changed Dart files**

Run: `dart format mobile/lib/pages/event_attendees.dart mobile/lib/pages/create_asset.dart mobile/lib/render/asset_detail_sheet.dart mobile/test/event_attendees_test.dart`

- [x] **Step 2: Run static analysis**

Run: `cd mobile && flutter analyze lib/pages/event_attendees.dart lib/pages/create_asset.dart lib/render/asset_detail_sheet.dart test/event_attendees_test.dart`

Expected: `No issues found!`

- [x] **Step 3: Run the attendee/card regression suite**

Run: `cd mobile && flutter test test/event_attendees_test.dart test/event_card_summary_test.dart test/timeline_event_summary_test.dart`

Expected: all tests pass.

- [x] **Step 4: Check diff hygiene**

Run: `git diff --check`

Expected: no output.

- [x] **Step 5: Commit implementation**

```bash
git add mobile/lib/pages/event_attendees.dart mobile/lib/pages/create_asset.dart mobile/lib/render/asset_detail_sheet.dart mobile/test/event_attendees_test.dart spec/02-data-model.md spec/03-api-reference.md spec/04-frontend.md spec/handoffs/handoff-event-attendees.md docs/superpowers/plans/2026-07-14-event-attendee-unlinked-state.md
git commit -m "feat: make bare event attendees optionally linkable"
```
