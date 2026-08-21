# Today Reka Physics and Dither Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Today Reka follow the finger, keep Calendar controls clear of docked Reka, transfer generated assets to physics at chamber entry, and amplify dither around moving balls.

**Architecture:** `ShellDitheredReka` remains the only renderer, but finger motion becomes direct while only root-mode changes animate. Generated assets retain their output animation until they enter the asset chamber, where the existing Forge2D field takes visual and physical ownership. Existing dither source energy gains a bounded visual spread without changing collision or hit geometry.

**Tech Stack:** Flutter/Dart, widget tests, Forge2D, Flutter fragment shaders, Android Flutter tooling.

## Global Constraints

- Work only in `.worktrees/skill-dither-report-revamp` on `codex/skill-dither-report-revamp`; never switch or edit `main`.
- Preserve exactly one shared dither Reka renderer across Today, Calendar, and Library.
- Apply the existing 260ms transition only to `today <-> dock`, never to dragging or settling.
- Keep dock Reka as an overlay; do not create a Dock slot or permanent page spacer.
- Use the existing `BubbleField`; do not add another physics engine.
- Dither spread must not alter Forge2D radius or the 44px minimum hit target.
- Respect `MediaQuery.disableAnimations` and existing lifecycle cleanup.
- Write a failing regression before each production change and make focused commits.
- Install the verified APK on Android device `RFCY71B21YK` with API port 8200 reversed.

---

### Task 1: Separate Finger Motion from Root Handoff Animation

**Files:**
- Modify: `mobile/test/theme_v2/shell/shell_dithered_reka_test.dart`
- Modify: `mobile/lib/theme_v2/shell/shell_dithered_reka.dart`

**Interfaces:**
- Consumes: `ShellDitheredRekaMode` and `TodayRekaMotionController.rekaCenter`.
- Produces: `shellRekaPositionDuration(...)`, a visible-for-testing policy returning zero for same-mode motion and 260ms only for a mode change.

- [ ] **Step 1: Add failing policy and composition tests**

```dart
test('Today drag and settle never interpolate position', () {
  expect(
    shellRekaPositionDuration(
      reduceMotion: false,
      modeChanged: false,
    ),
    Duration.zero,
  );
  expect(
    shellRekaPositionDuration(
      reduceMotion: false,
      modeChanged: true,
    ),
    ShellDitheredReka.transitionDuration,
  );
});

testWidgets('Today visual follows a 90px controller drag in one frame',
    (tester) async {
  final harness = _Harness(mode: ShellDitheredRekaMode.today);
  await tester.pumpWidget(harness.build());
  final before = tester.getCenter(find.byKey(ShellDitheredReka.visualKey));
  final start = harness.motion.rekaCenter;
  harness.motion.beginDrag(start);
  harness.motion.updateDrag(
    start + const Offset(90, -30),
    const Duration(milliseconds: 16),
  );
  await tester.pump();
  expect(
    tester.getCenter(find.byKey(ShellDitheredReka.visualKey)) - before,
    const Offset(90, -30),
  );
});
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `cd mobile && flutter test --no-pub test/theme_v2/shell/shell_dithered_reka_test.dart`

Expected: FAIL because the helper is absent and every controller update still receives a 260ms `AnimatedPositioned` duration.

- [ ] **Step 3: Implement handoff-only duration**

```dart
@visibleForTesting
Duration shellRekaPositionDuration({
  required bool reduceMotion,
  required bool modeChanged,
}) {
  if (reduceMotion || !modeChanged) return Duration.zero;
  return ShellDitheredReka.transitionDuration;
}
```

Track whether `widget.mode` changed in `didUpdateWidget`. Use the helper for both position and scale, consume the pending mode-change flag after the transition build, and keep same-mode controller notifications at `Duration.zero`.

- [ ] **Step 4: Run Shell and navigation regressions**

Run:

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/shell/shell_dithered_reka_test.dart \
  test/theme_v2/shell/reka_shell_companion_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: PASS, including the existing one-renderer and 260ms handoff behavior.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/shell/shell_dithered_reka.dart \
  mobile/test/theme_v2/shell/shell_dithered_reka_test.dart
git commit -m "fix(mobile): make Today Reka drag follow the finger"
```

---

### Task 2: Define and Respect the Dock Companion Exclusion Zone

**Files:**
- Create: `mobile/lib/theme_v2/shell/theme_v2_dock_overlay_geometry.dart`
- Modify: `mobile/lib/theme_v2/shell/shell_dithered_reka.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`
- Modify: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`
- Modify: `mobile/test/theme_v2/shell/shell_dithered_reka_test.dart`

**Interfaces:**
- Consumes: `ThemeV2FloatingDock.shellSize` and `.viewportBottomPadding`.
- Produces: `ThemeV2DockOverlayGeometry.rekaCenter`, `.rekaVisibleSize`, `.rekaTargetExtent`, and `.contentExclusionExtent`.

- [ ] **Step 1: Add a failing geometry regression**

In the Calendar Flow host, include the actual dock companion and assert:

```dart
final returnRect = tester.getRect(find.bySemanticsLabel('回到今天'));
final rekaRect = tester.getRect(find.byKey(ShellDitheredReka.targetKey));
expect(returnRect.overlaps(rekaRect), isFalse);
await tester.tap(find.bySemanticsLabel('回到今天'));
expect(find.bySemanticsLabel('回到今天'), findsNothing);
```

Also assert the exclusion extent is at least the 72px interaction target, not only the 54px visible body.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/calendar/calendar_flow_test.dart \
  test/theme_v2/shell/shell_dithered_reka_test.dart
```

Expected: FAIL because the return control still uses `bottom: 0` and shares the central overlay region.

- [ ] **Step 3: Create shared geometry and move only the transient control**

```dart
abstract final class ThemeV2DockOverlayGeometry {
  static const Size rekaVisibleSize = Size(78, 54);
  static const double rekaTargetExtent = 72;
  static const double centerLiftAboveDock = 12;
  static const double contentExclusionExtent = rekaTargetExtent;

  static Offset rekaCenter(Size viewport, double safeBottom) => Offset(
    viewport.width / 2,
    viewport.height -
        math.max(safeBottom, ThemeV2FloatingDock.viewportBottomPadding) -
        ThemeV2FloatingDock.shellSize.height -
        centerLiftAboveDock,
  );
}
```

Have `ShellDitheredReka` consume these values. Set Calendar Flow's return control to `bottom: ThemeV2DockOverlayGeometry.contentExclusionExtent`; do not change page clearance or Dock dimensions.

- [ ] **Step 4: Run the same focused tests and confirm GREEN**

Expected: PASS; rectangles do not overlap and tapping still returns to Today.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_dock_overlay_geometry.dart \
  mobile/lib/theme_v2/shell/shell_dithered_reka.dart \
  mobile/lib/theme_v2/calendar/calendar_flow_view.dart \
  mobile/test/theme_v2/calendar/calendar_flow_test.dart \
  mobile/test/theme_v2/shell/shell_dithered_reka_test.dart
git commit -m "fix(mobile): keep calendar controls clear of Reka"
```

---

### Task 3: Hand Generated Assets to Forge2D at Chamber Entry

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/lib/theme_v2/home/today_output_coordinator.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/test/theme_v2/home/today_output_overlay_test.dart`
- Modify: `mobile/test/theme_v2/home/today_output_coordinator_test.dart`
- Modify: `mobile/test/theme_v2/home/today_living_surface_test.dart`
- Modify: `mobile/test/today/bubble_physics_test.dart`

**Interfaces:**
- Consumes: `TodayAssetHandoff(center, velocity)`, `TodayOutputPhase.handoff`, and `BubbleField.addBubble(... velocityPxPerSecond:)`.
- Produces: `TodayOutputOverlay.assetEntryY`; stable asset exposure beginning at handoff; overlay ownership ending at handoff.

- [ ] **Step 1: Add failing overlay and coordinator tests**

```dart
await tester.pumpWidget(_host(TodayOutputOverlay(
  item: assetItem,
  signalBoundaryY: 74,
  assetEntryY: 420,
  assetDiameter: 70,
  assetVisual: const SizedBox(key: ValueKey('final-asset-ball')),
  onAssetHandoff: (value) => handoff = value,
  onComplete: () {},
)));
await tester.pump();
await tester.pump(const Duration(milliseconds: 1570));
expect(handoff!.center.dy, closeTo(455, 1));
expect(handoff!.velocity.dy, greaterThan(0));
expect(find.byKey(const ValueKey('final-asset-ball')), findsNothing);
```

Coordinator coverage:

```dart
coordinator.updatePhase(TodayOutputPhase.handoff);
expect(coordinator.stableAssetIds(const ['asset-2']), ['asset-2']);
expect(coordinator.producing?.id, 'asset-2');
```

Living-surface coverage must assert `assetEntryY == assetChamberTop`, not the full surface floor.

- [ ] **Step 2: Add a failing pre-floor collision test**

```dart
final field = BubbleField(box: const Size(300, 500), gravity: Offset.zero);
field.addBubble('existing', const Offset(150, 210), 28);
field.addBubble(
  'generated',
  const Offset(150, 70),
  28,
  velocityPxPerSecond: const Offset(0, 720),
);
for (var frame = 0; frame < 20; frame++) {
  field.step();
}
final existing = field.bubbles.singleWhere((b) => b.id == 'existing');
final generated = field.bubbles.singleWhere((b) => b.id == 'generated');
expect(existing.body.linearVelocity.y, greaterThan(0));
expect(generated.y, lessThan(500 - generated.r));
```

- [ ] **Step 3: Run focused tests and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/home/today_output_overlay_test.dart \
  test/theme_v2/home/today_output_coordinator_test.dart \
  test/theme_v2/home/today_living_surface_test.dart \
  test/today/bubble_physics_test.dart
```

Expected: FAIL because the API still targets `assetFloorY`, stable assets stay hidden until completion, and the overlay retains visual ownership.

- [ ] **Step 4: Implement ordered boundary handoff**

Use this order in `TodayOutputOverlay`:

```dart
if (value >= plan.travelEnd && !_handedOff) {
  _handoff();
  _reportPhase(TodayOutputPhase.handoff);
}
```

For assets, compute destination Y as `assetEntryY + assetDiameter / 2`, then stop drawing `assetVisual` after `_handedOff`. In `stableAssetIds`, include the current asset when phase is `handoff` or `recover`, while leaving it as `producing` until recovery completes. `TodayLivingSurface` passes `assetChamberTop` and stores the handoff center relative to that chamber. Existing spawn-state consumption creates the Forge2D body with the supplied downward velocity.

- [ ] **Step 5: Run focused tests and confirm GREEN**

Run the same command from Step 3.

Expected: PASS; the real body starts fully inside the chamber and collides before floor contact.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/home/today_output_overlay.dart \
  mobile/lib/theme_v2/home/today_output_coordinator.dart \
  mobile/lib/theme_v2/home/today_living_surface.dart \
  mobile/test/theme_v2/home/today_output_overlay_test.dart \
  mobile/test/theme_v2/home/today_output_coordinator_test.dart \
  mobile/test/theme_v2/home/today_living_surface_test.dart \
  mobile/test/today/bubble_physics_test.dart
git commit -m "fix(mobile): hand generated assets to physics at entry"
```

---

### Task 4: Expand Dither Around Moving Asset Balls

**Files:**
- Modify: `mobile/lib/theme_v2/foundation/theme_v2_dither_field.dart`
- Modify: `mobile/shaders/today_dither_field.frag`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/test/theme_v2/foundation/theme_v2_dither_surface_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

**Interfaces:**
- Consumes: `ThemeV2DitherSource.energy` in `0...1`.
- Produces: `themeV2DitherSpreadFor(source)` and a matching shader formula; no widget API or physical-geometry change.

- [ ] **Step 1: Add failing pressure-envelope tests**

```dart
test('energy expands pressure outside the physical source', () {
  const resting = ThemeV2DitherSource.circle(
    center: Offset(100, 100),
    radius: 30,
  );
  const moving = ThemeV2DitherSource.circle(
    center: Offset(100, 100),
    radius: 30,
    energy: 1,
  );
  const probe = Offset(145, 100);
  expect(themeV2DitherPressureAt(probe, resting), 0);
  expect(themeV2DitherPressureAt(probe, moving), greaterThan(.15));
  expect(themeV2DitherSpreadFor(resting), 0);
  expect(themeV2DitherSpreadFor(moving), inInclusiveRange(18, 24));
});
```

Extend the bubble-field test to prove moving energy rises while the visual target keeps its prior size.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub \
  test/theme_v2/foundation/theme_v2_dither_surface_test.dart \
  test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: FAIL because energy currently gives only a small in-radius pressure multiplier.

- [ ] **Step 3: Implement one bounded spread formula in Dart and GLSL**

```dart
double themeV2DitherSpreadFor(ThemeV2DitherSource source) {
  final base = math.min(source.size.width, source.size.height);
  return source.energy.clamp(0, 1) * (base * .34).clamp(18.0, 24.0);
}
```

Subtract spread from signed distance and add `spread * .35` to feather in `themeV2DitherPressureAt`. Mirror the exact calculation in `today_dither_field.frag` using `meta.y` and the source diameter. Keep `_ditherEnergy` speed-bounded and leave `bubble.r`, fixtures, and `_targetRect` unchanged.

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run the same command from Step 2.

Expected: PASS for Canvas pressure, shader configuration, energy response, and unchanged hit geometry.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/foundation/theme_v2_dither_field.dart \
  mobile/shaders/today_dither_field.frag \
  mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart \
  mobile/test/theme_v2/foundation/theme_v2_dither_surface_test.dart \
  mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
git commit -m "feat(mobile): amplify dither around moving assets"
```

---

### Task 5: Full Regression, Build, and Physical Device Verification

**Files:**
- Modify only if a regression exposes an in-scope defect in the files listed above.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: analyzer-clean debug APK installed on `RFCY71B21YK` with port 8200 reversed.

- [ ] **Step 1: Run the complete affected test suite**

Run: `cd mobile && flutter test --no-pub test/theme_v2 test/voice_input`

Expected: zero failed tests.

- [ ] **Step 2: Run analyzer**

Run: `cd mobile && flutter analyze lib test/theme_v2 test/voice_input`

Expected: `No issues found!`

- [ ] **Step 3: Build the APK**

Run: `cd mobile && flutter build apk --debug --dart-define=API_BASE=http://127.0.0.1:8200`

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced.

- [ ] **Step 4: Install, reverse, and launch**

```bash
cd mobile
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$ADB -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s RFCY71B21YK reverse tcp:8200 tcp:8200
$ADB -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$ADB -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: install reports `Success`, reverse reports `8200`, and launch injects one event.

- [ ] **Step 5: Verify the four behaviors on device**

1. Scroll Calendar Flow until “回到今天” appears; verify it is fully visible above Reka and tappable.
2. Drag Today Reka slowly and quickly; verify it stays under the finger and does not catch up after release.
3. Trigger one generated asset; verify it joins the chamber at the top and can collide before floor contact.
4. Move asset balls; verify surrounding dither expands during motion and settles afterward.

Capture screenshots for Calendar non-overlap and the final Today state. Record any behavior that cannot be triggered; do not report it as verified.

- [ ] **Step 6: Inspect final scope**

Run: `git status --short && git diff --check && git diff --stat`

Expected: only plan-listed corrections are dirty, or the worktree is clean after the four focused commits.
