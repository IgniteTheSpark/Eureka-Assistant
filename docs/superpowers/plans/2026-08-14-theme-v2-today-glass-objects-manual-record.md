# Theme V2 Today Glass Objects and Manual Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both complete Today watermarks clickable and seam-aligned, add faint type-colored frosted glass to signals and assets, and replace Reka's asset shortcut with the shared Calendar manual-record flow.

**Architecture:** `TodayRegionWatermark` remains the single navigation affordance and gains a reversible visual order. Signal and asset components own only their glass presentation, with a shared asset `BackdropGroup` for moving circles. Calendar exports one orchestration helper that the Shell invokes, so Today reuses the existing picker, catalog loader, and editor router without duplicating them.

**Tech Stack:** Flutter, Dart, Theme V2 tokens, `BackdropFilter.grouped`, widget tests, golden tests.

## Global Constraints

- The entire count-plus-label watermark is one semantic button; its hit target must not cover the surrounding region.
- Both labels sit 8 px from the signal/asset seam.
- Signal tint mapping is overdue red, rhythm cyan, report violet, fallback brand blue.
- Glass remains very faint, has no new shadow, and does not change Dither displacement, physics, scrolling, or Reduce Motion.
- Reka copy is `手动记录` and invokes the exact Calendar manual-record picker and editor path for the current local day.
- Do not change the Calendar manual-record Bottom Sheet itself.

---

### Task 1: Unify watermark hit targets and seam alignment

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Test: `mobile/test/theme_v2/home/today_dither_material_test.dart`
- Test: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

**Interfaces:**
- Consumes: existing `TodayRegionWatermark(count, label, alignment, onPressed, semanticLabel)`.
- Produces: `TodayRegionWatermark(labelFirst: bool = false)` whose count and label share one callback and semantic node.

- [ ] **Step 1: Write failing widget tests**

Add a focused watermark host with keys around the count and label. Tap `find.text('12')` and `find.text('Reka 生成')` in separate pumps and assert the same callback increments. Add a layout assertion that the discovery label is the lowest child of its group while the generation label is the highest child and both callers use an 8 px seam inset.

```dart
expect(tester.getTopLeft(find.text('Reka 生成')).dy,
    lessThan(tester.getTopLeft(find.text('12')).dy));
await tester.tap(find.text('12'));
expect(openCalls, 1);
await tester.tap(find.text('Reka 生成'));
expect(openCalls, 2);
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
flutter test test/theme_v2/home/today_dither_material_test.dart test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: FAIL because the count is currently ignored and generation has no label-first layout.

- [ ] **Step 3: Implement one interactive group**

Wrap the complete visual column in `Semantics` and an opaque `GestureDetector`. Build its two visual children in reversible order without attaching pointer handlers to either child.

```dart
final countChild = Text('$count', style: countStyle);
final labelChild = ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 44),
  child: Align(alignment: textAlignment, child: Text(label, style: labelStyle)),
);
final visualChildren = labelFirst
    ? [labelChild, const SizedBox(height: 7), countChild]
    : [countChild, const SizedBox(height: 7), labelChild];
```

Use `labelFirst: true` for `Reka 生成`. Set discovery bottom padding and generation top padding to 8 px.

- [ ] **Step 4: Run focused tests and commit**

Run the Task 1 command again. Expected: PASS.

```bash
git add mobile/lib/theme_v2/home/today_region_watermark.dart mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/test/theme_v2/home/today_dither_material_test.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
git commit -m "fix: unify today watermark entries"
```

### Task 2: Add faint object-level glass

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Test: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Update: `mobile/test/theme_v2/home/goldens/today-reka-idle-411-light.png`
- Update: `mobile/test/theme_v2/home/goldens/today-reka-dragging-411-light.png`
- Update: `mobile/test/theme_v2/home/goldens/today-reka-reduce-motion-411-light.png`
- Update: `mobile/test/theme_v2/home/goldens/today-reka-idle-411-tall-light.png`
- Update: `mobile/test/theme_v2/home/goldens/home-today-360-light.png`
- Update: `mobile/test/theme_v2/home/goldens/home-today-411-light.png`
- Update: `mobile/test/theme_v2/home/goldens/home-today-411-dark.png`

**Interfaces:**
- Produces: private `_signalGlassColor(BuildContext, String)` and the existing `_bubbleDitherColor(BuildContext, int)` as the only tint sources.
- Consumes: `BackdropFilter.grouped`, the existing signal pills, and `_ThemeV2BubbleVisual`.

- [ ] **Step 1: Write failing material tests**

Give each glass layer a stable key. Pump overdue, rhythm, report, and fallback signals; assert their glass colors differ and remain below 0.13 alpha in both themes. Pump asset bubbles and assert their decoration has a non-transparent fill whose RGB matches the current outline palette.

```dart
final glass = tester.widget<ColoredBox>(
  find.byKey(const ValueKey('today-signal-glass-overdue')),
);
expect(glass.color.a, lessThan(.13));
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
flutter test test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: FAIL because the stable glass layers and translucent fills do not exist.

- [ ] **Step 3: Implement grouped frosted glass**

Import `dart:ui`. Clip each signal pill and bubble, apply `BackdropFilter.grouped(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6))`, then paint a type/palette tint. Use alpha `.055` light / `.10` dark for signals and `.05` light / `.09` dark for assets. Keep the signal border absent and preserve the asset outline.

```dart
Color _signalGlassColor(BuildContext context, String type) {
  final base = switch (type) {
    'overdue' => const Color(0xFFE46A5D),
    'rhythm_gap' => const Color(0xFF28A9B8),
    'report' => const Color(0xFF8B6CE8),
    _ => context.themeV2.accent,
  };
  final dark = Theme.of(context).brightness == Brightness.dark;
  return base.withValues(alpha: dark ? .10 : .055);
}
```

Wrap the asset rendering stack in one `BackdropGroup`; compact and physics paths continue to use `_ThemeV2BubbleVisual`.

- [ ] **Step 4: Run focused tests, refresh goldens, and inspect images**

Run:

```bash
flutter test test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart test/theme_v2/home/theme_v2_home_golden_test.dart
```

Expected: PASS. Inspect all seven changed PNGs for faint colored bodies, retained Dither texture, readable content, and no opaque circles/pills.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/goldens
git commit -m "feat: add subtle glass to today objects"
```

### Task 3: Reuse the Calendar manual-record flow from Reka

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_editor_router.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_quick_actions.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_manual_record_picker_test.dart`

**Interfaces:**
- Produces: `Future<void> openCalendarManualRecordFlow(BuildContext context, {DateTime? effectiveDate, CalendarSkillLoader? loader, CalendarSkillEditorOpener? openEditor})`.
- Produces: `typedef CalendarSkillEditorOpener = Future<void> Function(BuildContext, CalendarSkillOption, DateTime)` as a focused test seam; production uses `openCalendarSkillEditor`.
- Produces: `TodayRekaAction.manualRecord('手动记录')` and `onManualRecord` callbacks through the Today/Shell path.
- Consumes: `showCalendarManualRecordPicker`, `fetchCalendarSkillCatalog`, and `openCalendarSkillEditor`.

- [ ] **Step 1: Write failing tests for copy and routing**

Update quick-action tests to expect `手动记录`, select `TodayRekaAction.manualRecord`, and assert only `onManualRecord` runs. Update the Shell test seam from `onCreateAsset` to `onManualRecord`. Add a Calendar helper test with an injected API/loader seam that selects a known option and verifies the editor router receives the current effective date.

```dart
expect(find.text('手动记录'), findsOneWidget);
await tester.tap(find.text('手动记录'));
expect(manualRecordCount, 1);
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/calendar/calendar_manual_record_picker_test.dart
```

Expected: FAIL because the new action, callback, and shared flow do not exist.

- [ ] **Step 3: Implement the shared flow and rewire Today**

Add a Calendar-owned helper that creates/owns an `ApiClient` only when no loader is injected, opens the existing picker for `effectiveDate ?? DateTime.now()`, then opens the injected or production editor for the selected option. Close only the owned client.

```dart
Future<void> openCalendarManualRecordFlow(
  BuildContext context, {
  DateTime? effectiveDate,
  CalendarSkillLoader? loader,
  CalendarSkillEditorOpener? openEditor,
}) async {
  ApiClient? ownedApi;
  final effectiveLoader = loader ?? () {
    ownedApi ??= ApiClient();
    return fetchCalendarSkillCatalog(ownedApi!);
  };
  try {
    final day = effectiveDate ?? DateTime.now();
    final option = await showCalendarManualRecordPicker(
      context,
      effectiveDate: day,
      loader: effectiveLoader,
    );
    if (option != null && context.mounted) {
      await (openEditor ?? openCalendarSkillEditor)(context, option, day);
    }
  } finally {
    ownedApi?.close();
  }
}
```

Rename the Today action and callback chain to manual-record language. In production Shell fallback call `unawaited(openCalendarManualRecordFlow(context))`.

- [ ] **Step 4: Run focused tests and commit**

Run the Task 3 test command again. Expected: PASS.

```bash
git add mobile/lib/theme_v2/calendar/calendar_editor_router.dart mobile/lib/theme_v2/home/today_reka_quick_actions.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/test/theme_v2/calendar/calendar_manual_record_picker_test.dart
git commit -m "feat: reuse manual record from today reka"
```

### Task 4: Final regression and device update

**Files:**
- Verify all files changed in Tasks 1-3.

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: an analyzed, tested, device-installable Today revamp build.

- [ ] **Step 1: Run focused analysis**

```bash
flutter analyze lib/theme_v2/home/today_region_watermark.dart lib/theme_v2/home/today_signal_band.dart lib/theme_v2/home/theme_v2_asset_bubble_field.dart lib/theme_v2/home/today_reka_quick_actions.dart lib/theme_v2/home/today_dot_experiment_page.dart lib/theme_v2/calendar/calendar_editor_router.dart lib/theme_v2/shell/theme_v2_app_shell.dart
```

Expected: `No issues found!`

- [ ] **Step 2: Run Today, Calendar picker, and Shell regressions**

```bash
flutter test --reporter compact test/theme_v2/home test/theme_v2/calendar/calendar_manual_record_picker_test.dart test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Build and install the experiment APK**

```bash
flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true
adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: install succeeds and the phone opens Today with faint colored glass objects, symmetric watermark labels, complete watermark taps, and the shared `手动记录` Bottom Sheet.
