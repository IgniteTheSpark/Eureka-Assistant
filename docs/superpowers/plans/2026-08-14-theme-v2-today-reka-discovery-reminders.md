# Theme V2 Today Reka Discovery & Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

**Goal:** Ship the approved Today living surface and the complete Reka discovery/reminder lifecycle: Dither-produced signals and assets, configurable Todo/Event advance reminders, overdue Todo snooze without changing its deadline, Rhythm detail, and the three-stage Report signal chain.

**Architecture:** Keep the existing Theme V2 records, report workflow, Nudge persistence, notification outbox, draggable 3D Reka, and asset physics engine. Add reminder preferences and idempotent reminder dispatch to the Theme V2 worker, extend Reka candidates with phase metadata and snooze state, expose those contracts through focused mobile sheets, then compose the current Today data into one borderless scene with a small production coordinator that withholds only actively animating IDs.

**Tech Stack:** Flutter/Dart, Python 3.12, FastAPI, Pydantic, SQLAlchemy async, Alembic/MySQL, pytest, Flutter widget/golden tests.

---

## Contract decisions

- `reminder_offsets_minutes` is an ordered, unique array of non-negative integers. Missing future Todo/Event data reads as `[15]`; `[]` means no advance reminders.
- Todo reminders live in the Todo asset `payload_json`; Event reminders live in `events.reminder_offsets_json`.
- Timed reminders anchor to Todo `due_at` or Event `start_at`. All-day Events anchor to 09:00 in the request timezone.
- Reminder delivery is idempotent per `(record kind, record id, anchor instant, offset)` and appears in Notifications only as delivery/history.
- Overdue snooze persists on the existing Nudge as `remind_again_at`; `due_at` never changes. “不再提醒” dismisses only the natural key for the current Todo occurrence (`todo id + due_at`).
- Report Reka phases are `opportunity`, `plan_ready`, and `report_ready`. `planning` and `generating` are deliberately invisible. A chain exposes at most one phase, and its natural key never includes `plan_revision`.
- Home production animations are presentation state only. IDs already present on initial load, refresh, route return, or scene rebuild do not replay.

## Task 1: Add reminder preference primitives and database columns

**Files:**
- Create: `theme_v2_service/app/domains/reminders/__init__.py`
- Create: `theme_v2_service/app/domains/reminders/preferences.py`
- Modify: `theme_v2_service/app/db/models.py`
- Modify: `theme_v2_service/app/domains/assets/schemas.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/domains/assets/todo_deadline.py`
- Create: `theme_v2_service/migrations/versions/0024_reka_reminders.py`
- Test: `theme_v2_service/tests/unit/test_reminder_preferences.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`
- Test: `theme_v2_service/tests/integration/test_migrations.py`

- [x] Write failing unit tests for normalization: missing → `[15]`, duplicates sort/dedupe, `[]` stays empty, negative/non-integer values reject.
- [x] Add a pure helper with one canonical default and serializer:

```python
DEFAULT_REMINDER_OFFSETS_MINUTES = (15,)

def normalize_reminder_offsets(value: object, *, missing_uses_default: bool) -> list[int]:
    ...
```

- [x] Add nullable `Event.reminder_offsets_json` and expose `reminder_offsets_minutes` on `EventCreate`, `EventUpdate`, and `EventRead` using a default-at-read compatibility rule.
- [x] Normalize new and updated Todo payloads so `reminder_offsets_minutes` is accepted by the built-in Todo schema and stored canonically.
- [x] Add Alembic revision `0024_reka_reminders` after `0023_report_async_illustration`; include `events.reminder_offsets_json` and nullable `nudges.remind_again_at` plus an index used by maintenance.
- [x] Run:

```bash
cd theme_v2_service
pytest tests/unit/test_reminder_preferences.py tests/contract/test_asset_api.py tests/integration/test_migrations.py -q
```

Expected: all selected tests pass; migration head is `0024_reka_reminders`.

## Task 2: Dispatch advance reminders idempotently

**Files:**
- Create: `theme_v2_service/app/domains/reminders/service.py`
- Create: `theme_v2_service/app/domains/reminders/maintenance.py`
- Modify: `theme_v2_service/app/worker.py`
- Modify: `theme_v2_service/app/domains/notifications/models.py`
- Modify: `theme_v2_service/migrations/versions/0024_reka_reminders.py`
- Test: `theme_v2_service/tests/integration/test_reminder_maintenance.py`

- [x] Write failing integration tests for Todo, timed Event, all-day Event at local 09:00, multiple offsets, disabled reminders, and repeated maintenance cycles.
- [x] Add a small `reminder_deliveries` ledger keyed by natural key, rather than deduplicating on notification text.
- [x] Collect only reminders whose fire time is in `(last window, now]`, whose source is active, and whose anchor has not changed.
- [x] Create Notification rows through `create_notification()` and write the ledger in the same transaction.
- [x] Add `run_reminder_maintenance_scheduler()` to the existing worker with a one-minute default interval and per-cycle transaction.
- [x] Run:

```bash
cd theme_v2_service
pytest tests/integration/test_reminder_maintenance.py tests/integration/test_notification_outbox.py -q
```

Expected: one Notification/outbox pair per due offset even when the cycle repeats.

## Task 3: Implement overdue Todo snooze semantics

**Files:**
- Modify: `theme_v2_service/app/domains/reka/models.py`
- Modify: `theme_v2_service/app/domains/reka/schemas.py`
- Modify: `theme_v2_service/app/domains/reka/service.py`
- Modify: `theme_v2_service/app/domains/reka/api.py`
- Modify: `theme_v2_service/app/domains/reka/overdue.py`
- Test: `theme_v2_service/tests/contract/test_reka_signals_api.py`
- Test: `theme_v2_service/tests/integration/test_reka_overdue_lifecycle.py`

- [x] Write failing tests for 15m/1h/3h/tomorrow-09:00/custom snooze, reappearance at `remind_again_at`, and “no more” dismissal.
- [x] Add `RekaSnoozeRequest` with a concrete UTC `remind_again_at`; resolve presets only on mobile so the server contract is unambiguous.
- [x] Add `POST /api/reka/signals/{signal_id}/snooze`, restricted to an active overdue Nudge.
- [x] Suppress an overdue candidate while `remind_again_at > now`; expose the same signal/Nudge identity when it becomes due again.
- [x] Ensure completion, due-time change, or occurrence replacement expires the old Nudge and clears any obsolete snooze naturally through the occurrence natural key.
- [x] Change overdue actions to `open`, `snooze`, `dismiss`; remove the misleading deadline-reschedule action.
- [x] Run:

```bash
cd theme_v2_service
pytest tests/contract/test_reka_signals_api.py tests/integration/test_reka_overdue_lifecycle.py -q
```

Expected: snoozing never mutates Todo `due_at`, and the same occurrence returns only after its snooze timestamp.

## Task 4: Promote Reports to a three-stage Reka chain

**Files:**
- Modify: `theme_v2_service/app/domains/reka/schemas.py`
- Modify: `theme_v2_service/app/domains/reka/service.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Test: `theme_v2_service/tests/integration/test_reka_signal_service.py`
- Test: `theme_v2_service/tests/e2e/test_report_generation_flow.py`

- [x] Write failing tests for opportunity → hidden planning → plan-ready → hidden generating → report-ready.
- [x] Extend signal payload with optional `phase`, `chain_id`, `evidence`, and `report_run_id`/`report_id` metadata.
- [x] Collect opportunity from an available `TriggerExecution`, plan-ready from `ReportGenerationRun.state == awaiting_selection`, and report-ready from the completed run/report.
- [x] Group candidates by stable chain and retain only the latest actionable phase; do not include `plan_revision` in natural keys.
- [x] Mark or supersede earlier active phase Nudges once a later phase becomes authoritative.
- [x] Keep existing report plan confirmation and generation APIs as the state-changing source of truth.
- [x] Run:

```bash
cd theme_v2_service
pytest tests/integration/test_reka_signal_service.py tests/e2e/test_report_generation_flow.py -q
```

Expected: exactly one actionable Report signal per chain at every persisted workflow state.

## Task 5: Extend the mobile Reka contract and repository

**Files:**
- Modify: `mobile/lib/theme_v2/reka/reka_signal.dart`
- Modify: `mobile/lib/theme_v2/reka/reka_signal_repository.dart`
- Modify: `mobile/lib/theme_v2/home/home_repository.dart`
- Modify: `mobile/lib/today/today_data.dart`
- Test: `mobile/test/theme_v2/reka/reka_signal_repository_test.dart`
- Test: `mobile/test/theme_v2/home/home_repository_test.dart`

- [x] Add mobile enums for `snooze` and Report phases and parse optional chain/evidence/report IDs without breaking older payloads.
- [x] Add `snooze(signalId, remindAgainAt)` to the repository and map all metadata into `TodayRekaItem`.
- [x] Keep unknown future actions/phases forward-compatible by ignoring only the unknown value, not the whole signal.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/reka/reka_signal_repository_test.dart test/theme_v2/home/home_repository_test.dart
```

Expected: old payload fixtures and new phased/snooze fixtures both parse.

## Task 6: Build the reusable reminder configuration sheet

**Files:**
- Create: `mobile/lib/theme_v2/reminders/reminder_preferences.dart`
- Create: `mobile/lib/theme_v2/reminders/reminder_configuration_sheet.dart`
- Test: `mobile/test/theme_v2/reminders/reminder_configuration_sheet_test.dart`

- [x] Write widget tests for defaults, multi-select, none, custom minutes, summary formatting, and save/cancel behavior.
- [x] Model options as values, not localized labels: `0, 5, 15, 30, 60, 1440` plus custom.
- [x] Render a compact Theme V2 bottom sheet with multiple checked rows and a single save action; selecting “不提醒” clears all offsets.
- [x] Preserve accessibility labels and 44px minimum hit targets.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/reminders/reminder_configuration_sheet_test.dart
```

Expected: the returned list is sorted, unique, and uses `[15]` when opening a missing legacy value.

## Task 7: Integrate reminders and overdue snooze into Todo/Event detail

**Files:**
- Modify: `mobile/lib/pages/create_asset.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editors.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Modify: `mobile/lib/theme_v2/asset_detail/asset_detail_model.dart`
- Modify: `mobile/lib/theme_v2/reka/reka_signal_actions.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_editor_test.dart`
- Test: `mobile/test/theme_v2/calendar/theme_v2_event_editor_test.dart`

- [x] Write failing tests for a future Todo/Event reminder summary, Event save payload, overdue Todo hiding advance reminders, snooze presets, and “不再提醒”.
- [x] Add the reminder row to Todo and Event forms/details and persist `reminder_offsets_minutes` through their existing APIs.
- [x] Add an optional `RekaOverdueContext` when opening the canonical Todo detail; it supplies signal ID and snooze/dismiss callbacks without creating a second detail sheet.
- [x] Show only snooze controls for an overdue occurrence. Resolve “明天 09:00” in local time and send a concrete timestamp.
- [x] Refresh Today after returning from any action sheet.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/library/asset/asset_detail_test.dart test/theme_v2/library/asset/asset_editor_test.dart test/theme_v2/calendar/theme_v2_event_editor_test.dart
```

Expected: detail semantics match future versus overdue state, and deadline edits remain separate from snooze.

## Task 8: Add Rhythm and phase-aware Report bottom sheets

**Files:**
- Create: `mobile/lib/theme_v2/reka/reka_rhythm_detail_sheet.dart`
- Create: `mobile/lib/theme_v2/reka/reka_report_detail_sheet.dart`
- Modify: `mobile/lib/theme_v2/reka/reka_signal_actions.dart`
- Modify: `mobile/lib/theme_v2/reka/reka_signals_page.dart`
- Test: `mobile/test/theme_v2/reka/reka_signal_detail_sheets_test.dart`

- [x] Write failing tests for Period-only Rhythm language, evidence/gap display, immediate record, rhythm dismissal, and all three Report phases.
- [x] Route Rhythm signals to their own sheet and open the existing skill capture path only from “立即记录”.
- [x] Route Report opportunity to “生成报告方案”, plan-ready to existing plan review/confirm, and report-ready to the existing report viewer.
- [x] Dismissal closes only the signal; it never deletes a plan draft or generated report.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/reka/reka_signal_detail_sheets_test.dart test/theme_v2/reka/reka_signals_page_test.dart
```

Expected: each Reka kind opens one canonical action surface with no report-completion-only legacy behavior.

## Task 9: Compose Today into the borderless 1/3 + 2/3 living surface

**Files:**
- Create: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Create: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Test: `mobile/test/theme_v2/home/today_reka_scene_test.dart`

- [x] Write failing tests proving initial data renders, refresh retains stale data on failure, Today header conditionally shows one next schedule, signal band takes the upper region, and Asset chamber takes the lower region.
- [x] Store `TodayData` in `TodayDotExperimentPage`; load once on init and replace it only after a successful refresh.
- [x] Move heading/next-schedule into `TodayLivingSurface` and keep Reka in the scene’s final Stack layer so it floats above band/chamber content.
- [x] Make the signal band borderless, horizontally pageable, and limited to one stable card per page. Render no empty copy when absent.
- [x] Make the Asset chamber borderless while preserving invisible physics walls and removing the current empty-state sentence.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_reka_scene_test.dart
```

Expected: Today works with 0/1/many signals and assets, and Reka remains draggable across both zones.

## Task 10: Add shared Dither material for Reka outputs

**Files:**
- Create: `mobile/lib/theme_v2/home/today_dither_material.dart`
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_gravity_chamber.dart`
- Test: `mobile/test/theme_v2/home/today_dither_material_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

- [x] Write painter/widget tests for deterministic Bayer output, circle versus strip masks, readable overlays, borderless chamber, and no interactions on the faint field.
- [x] Implement one reusable Bayer/Dither painter with shape, seed, density, edge fade, and strength parameters.
- [x] Use stronger Dither on signal strips and Asset balls; keep their icon/text overlay crisp and semantic.
- [x] Add only an extremely faint local zone material behind the signal/chamber areas; no global page dot field.
- [x] Remove the ball outline/gloss treatment while preserving hit targets and physics rotation.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dither_material_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: the visuals share a deterministic Dither language without changing bubble collision results.

## Task 11: Animate production from Reka without replay or duplication

**Files:**
- Create: `mobile/lib/theme_v2/home/today_output_coordinator.dart`
- Create: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Test: `mobile/test/theme_v2/home/today_output_coordinator_test.dart`
- Test: `mobile/test/theme_v2/home/today_output_overlay_test.dart`

- [x] Write pure coordinator tests for first-load suppression, one-time new-ID production, refresh/route-return suppression, queue order, Reka source snapshots, cancellation, capacity fallback, and Reduce Motion.
- [x] Track `known`, `queued`, and `producing` IDs separately. Expose stable lists as `all - queued - producing` so a semantic object never appears twice.
- [x] Snapshot Reka center when production begins. Asset: radial points condense → Dither ball → vertical fall → insert the same asset into physics at the handoff point. Signal: points align horizontally → Dither strip → vertical rise with a short downward trail → insert into the band.
- [x] If an animation cannot run, immediately release the ID to its stable destination. Do not perform pathfinding or chase a moving Reka.
- [x] Under Reduce Motion, replace movement/trails with a brief threshold reveal and immediate stable placement.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_output_coordinator_test.dart test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: every new semantic object has exactly one visual owner throughout its transition.

## Task 12: Integrate actions, refresh, navigation, and lifecycle

**Files:**
- Modify: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

- [x] Route signal taps through the new detail sheets and overdue context, then reload successful mutations.
- [x] Pause Reka, trails, and physics when Today is inactive or the app is backgrounded; resume without replay.
- [x] Keep the floating top dock and bottom dock above the content scene and preserve all chrome insets.
- [x] Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_page_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: navigation and lifecycle changes do not create duplicate outputs or stale signals.

## Task 13: Full verification and real-device handoff

**Files:**
- Modify goldens only after visual review: `mobile/test/goldens/theme_v2/today_dot_experiment*.png`
- Update tests as required, not product behavior.

- [x] Run backend focused and full suites (38 focused and 799 full tests passed):

```bash
cd theme_v2_service
pytest tests/unit/test_reminder_preferences.py tests/contract/test_asset_api.py tests/contract/test_reka_signals_api.py tests/integration/test_reminder_maintenance.py tests/integration/test_reka_overdue_lifecycle.py tests/integration/test_reka_signal_service.py tests/e2e/test_report_generation_flow.py -q
pytest -q
```

- [x] Run Flutter formatting, changed-file analysis, focused tests, and the full non-golden logic suite. The seven intentionally changed Today goldens remain deferred until real-device visual review; full repository analysis also retains two unrelated `chiplet_ring/example` errors already present on `main`:

```bash
dart format mobile/lib mobile/test
cd mobile
flutter analyze
flutter test test/theme_v2/home test/theme_v2/reka test/theme_v2/reminders test/theme_v2/library/asset test/theme_v2/calendar
flutter test
```

- [ ] Debug APK installed and launched on SM F9660; basic Today rendering and Reka drag are verified. Still verify one signal rise, one Asset fall/collision, reminder editing, overdue snooze, Rhythm detail, all three Report phases, background/resume, and Reduce Motion after review data is available.
- [ ] Capture one Today screenshot and one screen recording of each production direction for user review.
- [ ] Confirm `git status --short` contains only intended files, then commit in coherent slices (backend contracts, mobile details, Today visuals/motion).

Expected: all automated checks pass and the user can review the complete minimum loop on a real device.

## Self-review checklist

- [ ] Every requirement in both 2026-08-14 design specs maps to at least one task and test.
- [ ] No placeholder API names, TODO implementation notes, or unresolved model fields remain.
- [ ] Server JSON keys and Dart parser keys match exactly.
- [ ] Timezone behavior is explicit for timed records, all-day Events, snooze, and serialization.
- [ ] Nudge, Notification, and Report workflow ownership do not overlap.
- [ ] Home animations never become a second source of semantic state.
