# Theme V2 Report App Layer Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the completed Theme V2 report backend usable from the app through a report container, manual report creation, durable run resume, and complete report notification routing.

**Architecture:** Keep reports outside the asset repository and expose them through an independent Report container launched from the Library hub. A dedicated repository/controller composes only `GET /api/report-generation-runs?active=true` and `GET /api/reports`; run decisions continue through the existing `ReportRunController`. The container follows the approved priority-layer layout: pending decisions first, generating/failed runs second, completed reports as a stable library.

**Tech Stack:** Flutter, Dart, ChangeNotifier, ApiClient, flutter_test, MockClient; existing FastAPI Report APIs remain unchanged.

## Global Constraints

- Do not add a `report_container` backend table or fold reports into `/api/assets`.
- Never read TriggerTracker, unconsumed TriggerExecution, or ordinary notifications to build the container.
- Opening the container alone must not create a run.
- Manual creation may send intent alone; skill, asset, and time-range inputs remain optional.
- Completed reports appear only in the completed library, not duplicated in active runs.
- Phase 1 excludes public share creation/revocation; the existing local HTML share remains unchanged until Phase 2.
- All actionable controls meet the 44 px Theme V2 target.
- Validate each slice with focused tests; run the complete Flutter suite only after the phase is integrated.

---

### Task 1: Add typed report App Layer models and repository

**Files:**

- Create: `mobile/lib/theme_v2/report/report_models.dart`
- Create: `mobile/lib/theme_v2/report/report_repository.dart`
- Create: `mobile/test/theme_v2/report/report_repository_test.dart`

- [x] **Step 1: Write failing repository contract tests**

Cover: active and completed requests execute once in parallel; list responses deserialize from top-level arrays; completed runs are not synthesized from the run endpoint; malformed rows are skipped; one failed source produces a partial snapshot while both failed sources produce a load failure.

- [x] **Step 2: Run and confirm RED**

Run: `cd mobile && flutter test test/theme_v2/report/report_repository_test.dart`

Expected: FAIL because the report read model and repository do not exist.

- [x] **Step 3: Implement the independent read model**

Define immutable `ReportRunSummary`, `CompletedReportSummary`, `ReportOverview`, and source failure models. `ApiReportRepository.loadOverview()` requests only:

```text
GET /api/report-generation-runs?active=true
GET /api/reports
```

Parse state, title/intent, active stage, failure, report ID, timestamps, and report HTML needed for navigation.

- [x] **Step 4: Run and confirm GREEN**

Run: `cd mobile && flutter test test/theme_v2/report/report_repository_test.dart`

Expected: PASS.

---

### Task 2: Build report container state and priority layout

**Files:**

- Create: `mobile/lib/theme_v2/report/report_container_controller.dart`
- Create: `mobile/lib/theme_v2/report/report_container_page.dart`
- Create: `mobile/test/theme_v2/report/report_container_controller_test.dart`
- Create: `mobile/test/theme_v2/report/report_container_page_test.dart`

- [x] **Step 1: Write failing controller tests**

Cover initial load, retry, refresh with retained content, partial state, and no API call from construction before `load()`.

- [x] **Step 2: Write failing widget tests for the approved hierarchy**

Assert `等待你确认` appears before `生成中/需要处理`, completed reports live under `报告库`, the empty state offers `创建报告`, and tapping active/completed rows invokes distinct callbacks.

- [x] **Step 3: Implement the controller and page**

Use a Theme V2 page title `报告`. Render pending-decision runs first, then generating/planning/failed runs, then completed reports. Include loading, offline/error, partial, empty, and pull-to-refresh states. Use stable keys for every row and action.

- [x] **Step 4: Run focused tests**

Run: `cd mobile && flutter test test/theme_v2/report/report_container_controller_test.dart test/theme_v2/report/report_container_page_test.dart`

Expected: PASS.

---

### Task 3: Add manual report creation and generic run copy

**Files:**

- Modify: `mobile/lib/theme_v2/report/report_run_controller.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Create: `mobile/lib/theme_v2/report/report_create_sheet.dart`
- Modify: `mobile/test/theme_v2/report/report_notification_target_test.dart`
- Create: `mobile/test/theme_v2/report/report_create_sheet_test.dart`
- Create: `mobile/test/theme_v2/report/report_run_page_test.dart`

- [x] **Step 1: Write the failing manual-create controller test**

Call `startUserInitiated('总结最近的跑步训练')` and assert:

```json
{"origin":"user_initiated","intent":"总结最近的跑步训练"}
```

is posted to `/api/report-generation-runs` and the returned run is applied.

- [x] **Step 2: Write failing creation-sheet behavior tests**

Assert blank intent cannot submit, non-empty intent closes into a `ReportRunPage`, keyboard submit works, and a failed request remains retryable without losing text.

- [x] **Step 3: Implement manual creation**

Add `ReportRunController.startUserInitiated`, allow `ReportRunPage` to start from an intent, and add a bottom sheet with a multiline intent field. Do not require skill/asset/time-range fields in Phase 1 because the backend Planner can clarify them.

- [x] **Step 4: Generalize the run UI**

Replace hard-coded `会前调研/调研` copy with `报告/生成` defaults while continuing to display backend option titles. Add cancel for non-terminal active states using `POST /api/report-generation-runs/{id}/cancel`; cancelled runs return to the report container.

- [x] **Step 5: Run focused tests**

Run: `cd mobile && flutter test test/theme_v2/report/report_notification_target_test.dart test/theme_v2/report/report_create_sheet_test.dart test/theme_v2/report/report_run_page_test.dart`

Expected: PASS.

---

### Task 4: Wire the Report container into the Theme V2 Library hub

**Files:**

- Modify: `mobile/lib/theme_v2/library/library_hub.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`

- [x] **Step 1: Write the failing navigation test**

Pump the Theme V2 Library hub, tap the first-class `报告` entry, and assert that `ReportContainerPage` opens without adding `/api/reports` to `ApiLibraryRepository.loadOverview()`.

- [x] **Step 2: Implement an independent report entry**

Add a dedicated report action card to the hub, separate from pinned/custom asset containers. `ThemeV2LibraryPage` pushes the report page, injects the existing shared API where appropriate, and refreshes the report container after returning from a run.

- [x] **Step 3: Wire active and completed navigation**

Active row → `ReportRunPage(runId: ...)`; completed row → `ReportViewerPage(enableLegacyEnhancements: false)`. `创建报告` → manual creation sheet → new `ReportRunPage`.

- [x] **Step 4: Run the focused library and report suites**

Run: `cd mobile && flutter test test/theme_v2/library/library_navigation_test.dart test/theme_v2/report`

Expected: PASS.

---

### Task 5: Complete report notification routing

**Files:**

- Modify: `mobile/lib/theme_v2/report/report_notification_target.dart`
- Modify: `mobile/lib/pages/notifications_page.dart`
- Modify: `mobile/lib/app_events.dart`
- Modify: `mobile/test/theme_v2/report/report_notification_target_test.dart`
- Create: `mobile/test/theme_v2/report/report_notification_routing_test.dart`

- [x] **Step 1: Write failing link parser and target tests**

Cover:

- `report_available` + `report-start:<execution-id>:<revision>` → trigger run.
- `report_plan_ready` + `report-run:<run-id>` → existing run.
- `report_done` + `report:<report-id>` → completed viewer.
- `report_failed` + `report-run:<run-id>` → failed run page.

- [x] **Step 2: Implement one shared target resolver**

Keep link parsing and target construction in `report_notification_target.dart`. Make both notification-list taps and live event toasts delegate to the same resolver so historical and live routing cannot diverge.

- [x] **Step 3: Run focused routing tests**

Run: `cd mobile && flutter test test/theme_v2/report/report_notification_target_test.dart test/theme_v2/report/report_notification_routing_test.dart`

Expected: PASS.

---

### Task 6: Phase verification

- [x] **Step 1: Format all changed Dart files**

Run: `dart format mobile/lib/theme_v2/report mobile/lib/theme_v2/library/library_hub.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/pages/notifications_page.dart mobile/lib/app_events.dart mobile/test/theme_v2/report mobile/test/theme_v2/library/library_navigation_test.dart`

- [x] **Step 2: Run affected suites once**

Run: `cd mobile && flutter test test/theme_v2/report test/theme_v2/library test/theme_v2/inbox`

Expected: PASS.

- [x] **Step 3: Analyze changed production files**

Run: `cd mobile && flutter analyze lib/theme_v2/report lib/theme_v2/library/library_hub.dart lib/theme_v2/library/theme_v2_library_page.dart lib/pages/notifications_page.dart lib/app_events.dart`

Expected: no new issues.

- [x] **Step 4: Run one stage-end full mobile test**

Run: `cd mobile && flutter test`

Expected: all tests PASS. Do not rerun the full backend suite because Phase 1 does not modify backend code; retain the previously verified 344-test backend baseline.

- [x] **Step 5: Perform one device smoke acceptance**

Verify only these paths on the connected phone: Library → Report container; create report from intent; reopen active run after leaving; tap done/failed notification. Hardware connection and ring recording do not need to be repeated because no hardware path changed.
