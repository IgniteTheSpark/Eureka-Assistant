# Single Dither Reka Dock Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the raised realistic Dock cockpit with the one existing dither renderer, restore the compact three-button Dock on Today, and float the same Reka above Dock pages without increasing page clearance.

**Architecture:** `ThemeV2AppShell` becomes the only owner of `TodayDitheredReka`. A small `ShellRekaPresentationController` bridges Today-owned output/refresh cues into that shell renderer while the existing `TodayRekaMotionController` supplies pose and the full-size anchor. The shell positions one renderer between the Today anchor and a compact-Dock anchor; `ThemeV2FloatingDock` returns to its old three-button geometry and no longer accepts a cockpit child.

**Tech Stack:** Flutter, Dart, `webview_flutter`, existing Theme V2 motion/foundation tokens, Flutter widget/golden tests, Android ADB.

## Global Constraints

- Exactly one `TodayDitheredReka` may exist across Today, Calendar, Library, transitions, and reduced-motion states.
- Today uses the previous compact `169 × 60` three-destination Dock with no spacer, recess, bulge, or Reka target.
- Calendar and Library show the same renderer in a `78 × 54` visible frame centered above the Dock.
- The compact Reka has no cockpit, card, halo container, border, or pedestal and must not increase page bottom clearance.
- The Reka target remains at least `72 × 72` logical pixels.
- Root-page transform duration is `260 ms`; reduced motion removes travel and idle breathing.
- Tap, long-press Flash, upward cancel, release-to-send, Terminal, and microphone ownership remain unchanged.
- Routes and sheets without the Dock show neither compact Reka nor Terminal.
- Android acceptance uses `API_BASE=http://127.0.0.1:8200` and `adb reverse tcp:8200 tcp:8200`.

---

### Task 1: Restore the compact Dock and compact page clearance

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`

**Interfaces:**
- Consumes: `ThemeV2FloatingDock(selectedIndex, onDestinationSelected)`.
- Produces: `ThemeV2FloatingDock.shellSize == Size(169, 60)`, `contentClearance == 72`, no `rekaCockpit` argument or cockpit keys.

- [ ] **Step 1: Write failing compact-geometry tests**

```dart
expect(tester.getSize(find.byKey(ThemeV2FloatingDock.dockKey)),
    const Size(169, 60));
expect(find.byKey(const ValueKey('theme-v2-reka-cockpit')), findsNothing);
expect(ThemeV2FloatingDock.contentClearance, 72);
for (final label in ['今日', '日历', '资产']) {
  expect(find.bySemanticsLabel(label), findsOneWidget);
}
```

- [ ] **Step 2: Run the tests and capture RED**

Run:

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/shell/theme_v2_floating_dock_test.dart \
  test/theme_v2/shell/theme_v2_page_scaffold_test.dart
```

Expected: FAIL because the shell is `248 × 64`, cockpit exists, and clearance is `110`.

- [ ] **Step 3: Remove cockpit geometry and restore the old row**

Implement the public contract as:

```dart
class ThemeV2FloatingDock extends StatelessWidget {
  const ThemeV2FloatingDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const Size shellSize = Size(169, 60);
  static const double viewportBottomPadding = 35;
  static const double contentGap = 12;
  static const double contentClearance = shellSize.height + contentGap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: EdgeInsets.only(
        bottom: math.max(
          MediaQuery.paddingOf(context).bottom,
          viewportBottomPadding,
        ),
      ),
      child: SizedBox.fromSize(
        key: dockKey,
        size: shellSize,
        child: ThemeV2GlassChrome(
          materialKey: dockMaterialKey,
          child: Row(
            children: [for (var index = 0; index < 3; index++)
              Expanded(child: _destination(index))],
          ),
        ),
      ),
    ),
  );
}
```

Update `ThemeV2PageScaffold` and Today bottom inset to use only `contentClearance` plus safe-area padding.

- [ ] **Step 4: Run compact-Dock tests GREEN**

Run the Step 2 command plus `test/theme_v2/home/theme_v2_home_golden_test.dart`.

Expected: geometry assertions pass; existing goldens fail only because the intentional Dock pixels changed.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart \
  mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart \
  mobile/lib/theme_v2/home/today_dot_experiment_page.dart \
  mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart \
  mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart \
  mobile/test/theme_v2/home/theme_v2_home_golden_test.dart
git commit -m "fix(mobile): restore the compact theme v2 dock"
```

### Task 2: Give the shell one dither renderer

**Files:**
- Create: `mobile/lib/theme_v2/shell/shell_reka_presentation_controller.dart`
- Create: `mobile/lib/theme_v2/shell/shell_dithered_reka.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Test: `mobile/test/theme_v2/shell/shell_reka_presentation_controller_test.dart`
- Test: `mobile/test/theme_v2/shell/shell_dithered_reka_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Produces: immutable `ShellRekaPresentation` and mutable `ShellRekaPresentationController extends ChangeNotifier`.
- Produces: `ShellDitheredReka(mode, presentation, motionController, ...)` containing the only `TodayDitheredReka`.
- Consumes: existing `TodayOutputCue`, `TodayRekaCaptureCue`, `TodayRekaPose`, and gesture callbacks.

- [ ] **Step 1: Write controller and single-renderer RED tests**

```dart
test('presentation controller deduplicates identical renderer state', () {
  final controller = ShellRekaPresentationController();
  var changes = 0;
  controller.addListener(() => changes++);
  controller.update(refreshSignal: 2, cue: const TodayOutputCue.idle());
  controller.update(refreshSignal: 2, cue: const TodayOutputCue.idle());
  expect(changes, 1);
});

testWidgets('shell owns exactly one dither renderer on every root page',
    (tester) async {
  await pumpShell(tester);
  expect(find.byType(TodayDitheredReka), findsOneWidget);
  await tester.tap(find.bySemanticsLabel('日历'));
  await tester.pumpAndSettle();
  expect(find.byType(TodayDitheredReka), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/shell/shell_reka_presentation_controller_test.dart \
  test/theme_v2/shell/shell_dithered_reka_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: FAIL because the controller/widget do not exist and Today still owns the renderer.

- [ ] **Step 3: Implement the presentation bridge**

```dart
@immutable
class ShellRekaPresentation {
  const ShellRekaPresentation({
    this.refreshSignal = 0,
    this.cue = const TodayOutputCue.idle(),
    this.captureCue = const TodayRekaCaptureCue.idle(),
  });
  final int refreshSignal;
  final TodayOutputCue cue;
  final TodayRekaCaptureCue captureCue;
}

class ShellRekaPresentationController extends ChangeNotifier {
  ShellRekaPresentation value = const ShellRekaPresentation();

  void update({
    required int refreshSignal,
    required TodayOutputCue cue,
    required TodayRekaCaptureCue captureCue,
  }) {
    final next = ShellRekaPresentation(
      refreshSignal: refreshSignal,
      cue: cue,
      captureCue: captureCue,
    );
    if (next == value) return;
    value = next;
    notifyListeners();
  }
}
```

Create and dispose this controller in `ThemeV2AppShell`. Pass it into `TodayDotExperimentPage`; update it from `_onOutputChanged`, capture changes, and refresh changes. Remove the renderer construction from `TodayRekaScene`, leaving its scene hit/anchor responsibilities intact.

- [ ] **Step 4: Implement the single shell renderer**

`ShellDitheredReka` uses an `AnimatedBuilder` over both controllers and constructs one renderer:

```dart
TodayDitheredReka(
  pose: motionController.pose,
  active: active,
  reduceMotion: MediaQuery.disableAnimationsOf(context),
  refreshSignal: presentation.value.refreshSignal,
  cue: presentation.value.cue,
  captureCue: presentation.value.captureCue,
)
```

Wrap it in one `GestureDetector`/`Semantics` target. Do not create `RekaMini`, `RekaMiniVisual`, or another `TodayDitheredReka` in any route.

- [ ] **Step 5: Run Task 2 tests GREEN and commit**

```bash
flutter test --no-pub \
  test/theme_v2/shell/shell_reka_presentation_controller_test.dart \
  test/theme_v2/shell/shell_dithered_reka_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
git add mobile/lib/theme_v2/shell mobile/lib/theme_v2/home \
  mobile/test/theme_v2/shell
git commit -m "refactor(mobile): share one dither reka across root pages"
```

### Task 3: Position, breathe, and anchor the single renderer

**Files:**
- Modify: `mobile/lib/theme_v2/shell/shell_dithered_reka.dart`
- Modify: `mobile/lib/theme_v2/shell/reka_shell_companion.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Delete: `mobile/lib/theme_v2/shell/reka_mini.dart`
- Test: `mobile/test/theme_v2/shell/shell_dithered_reka_test.dart`
- Test: `mobile/test/theme_v2/shell/reka_shell_companion_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart`

**Interfaces:**
- Produces: `ShellDitheredRekaMode.today` and `.dock`.
- Produces: `ShellDitheredReka.dockVisibleSize == Size(78, 54)` and `targetExtent == 72`.
- Consumes: `TodayRekaMotionController.rekaCenter`, compact Dock bottom padding, and existing voice callbacks.

- [ ] **Step 1: Add failing transform and no-clearance tests**

```dart
expect(tester.getSize(find.byKey(ShellDitheredReka.visibleKey)),
    const Size(78, 54));
expect(find.byType(RekaMini), findsNothing);
expect(tester.getBottomLeft(find.byKey(ShellDitheredReka.visibleKey)).dy,
    lessThan(tester.getTopLeft(find.byKey(ThemeV2FloatingDock.dockKey)).dy + 16));
expect(pageBottomPadding, ThemeV2FloatingDock.contentClearance);
```

Add a deterministic ticker test proving Dock idle translation changes, app pause stops it, and `disableAnimations: true` keeps its transform fixed.

- [ ] **Step 2: Run RED**

Run the three Task 3 test files. Expected: FAIL because the shell renderer has no Dock transform/breathing and the native mini remains.

- [ ] **Step 3: Implement positioning and motion**

Use a single `AnimationController(duration: Duration(milliseconds: 2400))` for Dock breathing and an `AnimatedPositioned`/`TweenAnimationBuilder` duration of `260 ms` for root transitions. Calculate the Dock center as:

```dart
Offset dockCenter(Size viewport, double safeBottom) => Offset(
  viewport.width / 2,
  viewport.height -
      math.max(safeBottom, ThemeV2FloatingDock.viewportBottomPadding) -
      ThemeV2FloatingDock.shellSize.height + 4,
);
```

Render at full `TodayDitheredRekaConfig.renderExtent` and scale to `78 / visibleBodyWidth` in Dock mode. Apply Dock breathing only after the root transform finishes. In reduced motion, stop/reset the breathing controller and set the destination transform without travel.

- [ ] **Step 4: Move Terminal anchoring to the new Dock center**

Replace cockpit constants in `RekaShellCompanion` with `ShellDitheredReka.dockAnchor(...)`. Position Terminal `10` pixels above the compact visible frame. Preserve the existing Today above/below placement and dismiss lifecycle.

- [ ] **Step 5: Remove obsolete native mini and run GREEN**

Delete `reka_mini.dart`, `RekaDockCockpit`, cockpit-light helpers, and old handoff proxy art. Run Task 3 tests and repeat the transition test five times.

- [ ] **Step 6: Commit**

```bash
git add -A mobile/lib/theme_v2/shell mobile/test/theme_v2/shell
git commit -m "feat(mobile): float the dither reka above the compact dock"
```

### Task 4: Refresh visual baselines and verify the physical device

**Files:**
- Modify: affected PNG files under `mobile/test/theme_v2/**/goldens/`
- Modify: `mobile/test/theme_v2/shell/reka_dock_cockpit_golden_test.dart` (rename scenarios/copy to dither terminology)
- Rename: test to `mobile/test/theme_v2/shell/shell_dithered_reka_golden_test.dart`

**Interfaces:**
- Consumes: completed compact Dock and single dither renderer.
- Produces: reviewed light/dark and capture-state baselines plus installed Android APK.

- [ ] **Step 1: Run visual tests without updating**

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/home/theme_v2_home_golden_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart \
  test/theme_v2/calendar/theme_v2_calendar_golden_test.dart \
  test/theme_v2/library/theme_v2_library_golden_test.dart \
  test/theme_v2/shell/shell_dithered_reka_golden_test.dart
```

Expected: RED only for intentional compact-Dock and dither-Reka pixels.

- [ ] **Step 2: Update and inspect affected baselines**

Run the same command with `--update-goldens`. Inspect Today light, Calendar light, Library dark, listening, cancel-armed, Terminal-open, and reduce-motion images. Reject any image with a Today placeholder, realistic mini, container, clipped target, or additional bottom gap.

- [ ] **Step 3: Run complete regression and analysis**

```bash
flutter test --no-pub test/theme_v2 test/voice_input
flutter analyze lib test/theme_v2 test/voice_input
```

Expected: all tests pass and analysis reports `No issues found`.

- [ ] **Step 4: Build and install the full-chain APK**

```bash
flutter build apk --debug --dart-define=API_BASE=http://127.0.0.1:8200
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$ADB -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s RFCY71B21YK reverse tcp:8200 tcp:8200
$ADB -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$ADB -s RFCY71B21YK shell monkey -p com.eureka.mindapp \
  -c android.intent.category.LAUNCHER 1
```

Expected: build and install succeed, Today business data loads without 404, and the package is foreground.

- [ ] **Step 5: Physical acceptance and final commit**

Capture Today, Calendar, Library, and Session screenshots. Verify Today has the compact three-button Dock with no placeholder; Calendar/Library show the same dithered floating Reka with no container or extra content gap; tap enters Session; long press visibly enters listening state and cancellation remains available. Do not submit a voice capture during automated checking.

```bash
git add mobile/test/theme_v2
git commit -m "test(mobile): baseline the single dither reka"
git status --short
```

Expected: final status is clean.
