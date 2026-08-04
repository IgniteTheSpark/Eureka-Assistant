# Theme V2 Session, Todo, and Custom Icon Regression Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore generic New Chat behavior from flash sessions, make todo filters comfortably tappable, and preserve custom-skill icons in Theme V2.

**Architecture:** Keep the flash-session controller scoped to the daily flash workflow and route New Chat into the existing generic `ChatPage` pipeline. Preserve the current asset-list and library architecture; fix only the hit target and render-spec selection boundaries that caused the regressions.

**Tech Stack:** Flutter, Dart, flutter_test, MockClient.

## Global Constraints

- Do not change the backend API contract or the flash-session grouping model.
- A fresh chat must use `ChatControllerSessionAdapter`, not `CaptureSessionController`.
- Interactive pills must meet the Theme V2 44 px minimum target.
- Built-in core records retain canonical icons; custom skills retain their server-provided `render_spec`.
- Run only the focused test after each RED/GREEN loop. Run the affected Theme V2 suites once after all three fixes.

---

### Task 1: Route flash-session New Chat into a generic agent session

**Files:**

- Modify: `mobile/lib/theme_v2/capture/capture_session_page.dart`
- Create: `mobile/test/theme_v2/capture/capture_session_page_test.dart`

- [ ] **Step 1: Write the failing navigation test**

Pump `CaptureSessionPage` with a fake session controller and a test-only new-chat destination builder. Tap the top-right `New Chat` action and assert that the flash page is replaced by the supplied generic destination.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `cd mobile && flutter test test/theme_v2/capture/capture_session_page_test.dart`

Expected: FAIL because `CaptureSessionPage` does not yet own New Chat navigation or expose the test seams.

- [ ] **Step 3: Implement the minimal route boundary**

Add optional controller/destination injection for the widget test. In production, pass `onNewConversation` to `ThemeV2SessionPage` and replace the flash page with `const ChatPage(startBlank: true, themeV2Override: true)`. Dispose only controllers created by `CaptureSessionPage`.

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run: `cd mobile && flutter test test/theme_v2/capture/capture_session_page_test.dart`

Expected: PASS and the fake capture controller is never reset to create a generic conversation.

---

### Task 2: Restore the minimum todo filter tap target

**Files:**

- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`

- [ ] **Step 1: Write the failing size assertion**

Pump a todo asset list, find every `todo-filter-*` pill, and assert that each rendered height is at least `ThemeV2Semantics.minimumTapTarget`.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_list_page_test.dart --plain-name 'todo filter pills meet the minimum tap target'`

Expected: FAIL with the current 34 px height.

- [ ] **Step 3: Raise the control height without changing filtering behavior**

Use the shared Theme V2 minimum target for `_TodoFilterTabs`; retain the four-filter layout and count labels.

- [ ] **Step 4: Run the focused asset-list suite**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_list_page_test.dart`

Expected: PASS.

---

### Task 3: Preserve custom skill icons under the core-record API

**Files:**

- Modify: `mobile/lib/theme_v2/library/library_repository.dart`
- Modify: `mobile/test/theme_v2/library/library_repository_test.dart`

- [ ] **Step 1: Write the failing custom render-spec test**

Return a core-record custom skill named `running_training` with `render_spec.icon = 🏃` and one matching asset. Assert that both the custom container and recent asset use `🏃`.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `cd mobile && flutter test test/theme_v2/library/library_repository_test.dart --plain-name 'preserves custom skill render icon in core-record mode'`

Expected: FAIL because the repository currently replaces every core-record render spec with `coreRecordRenderSpec` and falls back to `•`.

- [ ] **Step 3: Select render specs by skill ownership**

For the four built-in records (`todo`, `notes`, `event`, `contact`), continue using the canonical core render specs. For custom skills, parse the server `render_spec`, attach `schema`/`payload_schema`, and fall back to the canonical spec only when the server did not provide a usable icon.

- [ ] **Step 4: Run the focused repository suite**

Run: `cd mobile && flutter test test/theme_v2/library/library_repository_test.dart`

Expected: PASS for built-in icons, custom icons, and recent assets.

---

### Task 4: Batch verification

- [ ] **Step 1: Format changed Dart files**

Run: `dart format mobile/lib/theme_v2/capture/capture_session_page.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/lib/theme_v2/library/library_repository.dart mobile/test/theme_v2/capture/capture_session_page_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart mobile/test/theme_v2/library/library_repository_test.dart`

- [ ] **Step 2: Run the three affected suites once**

Run: `cd mobile && flutter test test/theme_v2/capture test/theme_v2/library/asset/asset_list_page_test.dart test/theme_v2/library/library_repository_test.dart`

Expected: PASS.

- [ ] **Step 3: Analyze only changed production files**

Run: `cd mobile && flutter analyze lib/theme_v2/capture/capture_session_page.dart lib/theme_v2/library/asset/asset_list_page.dart lib/theme_v2/library/library_repository.dart`

Expected: no new issues.
