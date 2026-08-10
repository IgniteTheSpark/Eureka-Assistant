# Theme V2 Reka Mobile Signals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Theme V2 Home to the persisted Overdue/Rhythm signal API and make every advertised mobile action usable without mixing notification receipts back into Reka.

**Architecture:** Keep `/api/notifications` owned by the bell/notification center. Introduce a small Flutter Reka signal model and API repository for `/api/reka/signals`; Home consumes that repository while a dedicated full-list page owns refresh and signal actions. Target opening reuses canonical asset/container surfaces, and complete/dismiss mutations refresh Home through `bumpData()`.

**Tech Stack:** Flutter, Dart, Material 3, existing `ApiClient`, widget/unit tests, Android ADB true-device verification.

## Global Constraints

- Theme V2 must remain the default build and must be passed explicitly as `--dart-define=THEME_V2=true` for device acceptance.
- Home Reka reads only `/api/reka/signals`; report/capture workflow receipts remain in `/api/notifications` and the bell page.
- Support exactly the backend signal kinds `overdue` and `rhythm_gap` and only actions advertised by each signal.
- Overdue row tap opens the canonical asset detail; `complete` writes `status=done`; `reschedule` opens the same detail/edit surface; `dismiss` calls the signal dismiss endpoint.
- Rhythm row tap opens the matching skill asset container; `dismiss` calls the signal dismiss endpoint.
- A successful complete or dismiss removes the signal immediately and triggers the shared data revision refresh.
- Partial source failure must preserve healthy signals; total network failure may degrade Home Reka to empty without blanking Today.
- Reka empty state provides `查看历史报告` and `生成新报告` entry points into the same Report container/three-step flow.

---

### Task 1: Signal Contract and Repository

**Files:**
- Create: `mobile/lib/theme_v2/reka/reka_signal.dart`
- Create: `mobile/lib/theme_v2/reka/reka_signal_repository.dart`
- Create: `mobile/test/theme_v2/reka/reka_signal_repository_test.dart`
- Modify: `mobile/lib/theme_v2/home/home_repository.dart`
- Modify: `mobile/lib/today/today_data.dart`

**Interfaces:**
- Produces: `RekaSignal.tryParse(Map<String, dynamic>)` with id, kind, title, body, target, actions, delivery and expiry timestamps.
- Produces: `ApiRekaSignalRepository.load({timezoneName})`, `dismiss(signalId)`, and `completeTodo(assetId)`.
- Home maps the signal contract into `TodayRekaItem` without notification links.

- [x] **Step 1: Write failing model/repository tests** asserting parsing, action filtering, timezone query, dismiss path, complete payload, malformed-row exclusion, and partial-failure preservation.
- [x] **Step 2: Run RED:**

```bash
flutter test test/theme_v2/reka/reka_signal_repository_test.dart
```

Expected: import/type failures because the Reka signal client does not exist.

- [x] **Step 3: Implement the minimal immutable signal model and API repository.** The GET path is `/api/reka/signals` with `timezone=Asia/Shanghai`; dismiss is `POST /api/reka/signals/{id}/dismiss`; complete is `PUT /api/assets/{id}` with `{"payload_patch":{"status":"done"}}`.
- [x] **Step 4: Replace Home's `/api/notifications` fetch with the new repository and keep Today section failure isolation.**
- [x] **Step 5: Run GREEN** for the repository tests and existing Today data tests.

### Task 2: Home Cards, Actions, and Empty Report Entry

**Files:**
- Modify: `mobile/lib/theme_v2/home/home_today_panel.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Create: `mobile/lib/theme_v2/reka/reka_signal_actions.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**
- Consumes: `TodayRekaItem.actions`, `targetType`, and `targetId`.
- Produces: row tap target navigation, a 44px overflow action menu, optimistic complete/dismiss removal, and report empty-state callbacks.

- [x] **Step 1: Write failing widget tests** proving report receipts are absent, overdue/rhythm icons differ, action menus expose only advertised actions, successful dismiss removes the row, and empty state exposes `查看历史报告` / `生成新报告`.
- [x] **Step 2: Run RED** for the named Home tests and confirm failures describe missing controls/callbacks.
- [x] **Step 3: Implement signal row rendering and action dispatch.** Use `schedule_outlined` for overdue, `waves_outlined` for rhythm, and surface mutation errors in a SnackBar while retaining the row.
- [x] **Step 4: Implement target navigation.** Asset targets call `openAssetDetail`; skill targets push the existing Theme V2 asset-container surface; reschedule opens asset detail rather than duplicating deadline editing.
- [x] **Step 5: Run GREEN** for Home widget tests.

### Task 3: Full Reka List and Shell Routing

**Files:**
- Create: `mobile/lib/theme_v2/reka/reka_signals_page.dart`
- Create: `mobile/test/theme_v2/reka/reka_signals_page_test.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Produces: a refreshable Theme V2 Reka page using the same repository/actions as Home.
- Shell Home `查看全部` opens this page; the bell continues to open `NotificationsPage`.
- Empty-state report actions both open `ReportContainerPage`, with `生成报告` immediately opening its create flow.

- [x] **Step 1: Write failing page/shell tests** distinguishing Reka routing from bell routing and exercising empty, loaded, partial, mutation failure, and retry states.
- [x] **Step 2: Run RED.**
- [x] **Step 3: Implement the dedicated page and shell callbacks without changing notification unread-count behavior.**
- [x] **Step 4: Run GREEN** for page and shell tests.

### Task 4: Regression and True-device Acceptance

**Files:**
- Modify only files already listed if a regression is found.

- [x] **Step 1: Run focused Flutter tests:**

```bash
flutter test test/theme_v2/reka test/theme_v2/home/theme_v2_home_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

- [x] **Step 2: Run `flutter analyze` on all modified Dart files.**
- [x] **Step 3: Rebuild explicitly with Theme V2 and local API:**

```bash
flutter build apk --debug --dart-define=THEME_V2=true --dart-define=API_BASE=http://localhost:8000
```

- [x] **Step 4: Install on `RFCY71B21YK`, restore `tcp:8000 -> tcp:8100`, launch `com.eureka.mindapp`, and clear/logcat before acceptance.**
- [x] **Step 5: Verify the live overdue signal appears, opens its Todo, and the overflow offers complete/reschedule/dismiss; verify Reka no longer contains report workflow receipts.**
- [x] **Step 6: Verify Home, Calendar, Library, bell notifications, and Report entry still open without SocketException or unhandled Flutter errors.**
