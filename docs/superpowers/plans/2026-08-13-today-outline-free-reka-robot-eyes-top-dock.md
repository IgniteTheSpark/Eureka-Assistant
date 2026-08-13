# Today Outline-Free Reka, Robot Eyes, and Top Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Today-page Reka an outline-free breathing rise with two 3 by 3 retro LED eyes and replace the light-mode Today top bar with a floating dock that matches the bottom dock language.

**Architecture:** Keep motion and gesture state in the existing controller and simulation, while changing only the painter's visual composition. Add an explicit `floatingDock` presentation to the shared top navigation, wire it only for the continuous light Today scene, and use its published outer extent for Today layout and drag bounds.

**Tech Stack:** Flutter, Dart, `CustomPainter`, Material widgets, `flutter_test`, golden tests

## Global Constraints

- Scope is Theme V2 Today page in light mode only.
- Do not add Reka to another page or redesign dark mode.
- Do not add a new animation controller, gesture, facial feature, or background interaction.
- Preserve device, theme, notification, bottom-dock, accessibility, and reduced-motion behavior.
- Support a minimum logical width of 360 dp.
- Keep `cursorRadius` as Reka rise size and `glowRadius` as ambient shading size.

---

## File Structure

- `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`: compose outline-free Reka light fields, ambient shading, and two LED matrices.
- `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart`: pixel-level contracts for the soft rise, glow separation, LED geometry, and drag hiding.
- `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`: publish the existing light dock surface constants used by both docks.
- `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`: add the explicit floating top-dock presentation and its stable geometry.
- `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`: verify top-dock dimensions, shared surface language, narrow layout, semantics, and standard-nav regression.
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`: select the floating presentation only for continuous light Today.
- `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`: reserve the floating top dock's outer extent in the Today scene.
- `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`: verify Today/light selection and Calendar/dark regression.
- `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`: host the floating variant and update visual fixtures for all existing scene states.

---

### Task 1: Paint an outline-free rise and LED matrix eyes

**Files:**
- Modify: `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`

**Interfaces:**
- Consumes: `TodayDotFieldConfig.cursorRadius`, `TodayDotFieldConfig.glowRadius`, `TodayDotFieldConfig.glowColor`, `TodayDotMatrixPalette.eye`, `TodayRekaMotionState`, `breathAmount`, and `eyeOpacity`.
- Produces: `TodayDotMatrixPainter.paint(Canvas, Size)` with an unbounded-looking layered rise and two 3 by 3 LED matrices; no public API changes.

- [ ] **Step 1: Write failing pixel contracts**

Replace the existing ball-oriented tests with tests that verify asymmetric falloff, a low-opacity broad halo, nine LED samples per eye, dim corners, and no eye changes while dragging:

```dart
test('Reka rise has offset soft falloff without a circular rim', () async {
  final image = await _renderPainter(
    config: const TodayDotFieldConfig(
      cursorRadius: 36,
      glowRadius: 76,
      glowColor: Colors.black,
    ),
    rekaCenter: const Offset(100, 100),
    breathAmount: 1,
    eyeOpacity: 0,
  );

  final center = await _pixel(image, 94, 94);
  final rightFalloff = await _pixel(image, 132, 100);
  final lowerFalloff = await _pixel(image, 100, 132);
  final outside = await _pixel(image, 188, 100);
  expect(_brightness(center), greaterThan(_brightness(rightFalloff)));
  expect(rightFalloff, isNot(lowerFalloff));
  expect((_brightness(rightFalloff) - _brightness(outside)).abs(), lessThan(120));
}

test('eyes render as two warm 3 by 3 LED matrices', () async {
  final visible = await _renderPainter(
    config: const TodayDotFieldConfig(cursorRadius: 54),
    rekaCenter: const Offset(100, 100),
    breathAmount: 1,
    eyeOpacity: 1,
  );
  final hidden = await _renderPainter(
    config: const TodayDotFieldConfig(cursorRadius: 54),
    rekaCenter: const Offset(100, 100),
    breathAmount: 1,
    eyeOpacity: 0,
  );

  for (final originX in [78, 110]) {
    for (final row in [0, 1, 2]) {
      for (final column in [0, 1, 2]) {
        final x = originX + column * 5;
        final y = 95 + row * 5;
        expect(await _pixel(visible, x, y), isNot(await _pixel(hidden, x, y)));
      }
    }
  }
  expect(
    _warmth(await _pixel(visible, 83, 100)),
    greaterThan(_warmth(await _pixel(visible, 78, 95))),
  );
}

int _warmth(Color color) => ((color.r - color.b) * 255).round();
```

- [ ] **Step 2: Run the focused painter tests and confirm RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: FAIL because the current circular core is symmetrical and each eye is one circle rather than nine LEDs.

- [ ] **Step 3: Implement layered light fields and LED modules**

Change the painter so `_paintRekaGlow` uses a low-opacity, broad radial gradient, `_paintRekaRise` draws several offset ellipses whose alpha reaches zero well inside their paint bounds, and `_paintEyes` draws three rows and three columns per eye:

```dart
void _paintEyes(Canvas canvas, Offset center, double opacity, Paint paint) {
  final alpha = opacity.clamp(0.0, 1.0);
  final moduleGap = math.max(2.0, config.dotRadius * .8);
  final ledRadius = math.max(1.15, config.dotRadius * .72);
  final pitch = ledRadius * 2 + moduleGap;
  final eyeWidth = pitch * 2;
  final eyeGap = config.cursorRadius * .34;

  for (final eyeCenterX in [center.dx - eyeGap, center.dx + eyeGap]) {
    for (var row = -1; row <= 1; row++) {
      for (var column = -1; column <= 1; column++) {
        final corner = row.abs() == 1 && column.abs() == 1;
        paint.color = palette.eye.withValues(
          alpha: palette.eye.a * alpha * (corner ? .48 : 1),
        );
        canvas.drawCircle(
          Offset(
            _snap(eyeCenterX + column * pitch),
            _snap(center.dy + row * pitch),
          ),
          ledRadius,
          paint,
        );
      }
    }
  }
}
```

Keep the existing guard that skips `_paintEyes` while `rekaState == TodayRekaMotionState.dragging`.

- [ ] **Step 4: Run painter tests and confirm GREEN**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit the painter increment**

```bash
git add mobile/lib/theme_v2/home/today_dot_matrix_painter.dart mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart
git commit -m "feat: refine reka rise and robot eyes"
```

---

### Task 2: Add the floating top-dock presentation

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

**Interfaces:**
- Consumes: existing top-nav callbacks and `ThemeV2FloatingDock` light surface constants.
- Produces: `ThemeV2GlobalTopNav.floatingDock`, `ThemeV2GlobalTopNav.floatingDockKey`, and `ThemeV2GlobalTopNav.floatingExtent`; the standard constructor behavior remains unchanged.

- [ ] **Step 1: Write failing widget tests for geometry and parity**

Add a floating variant test at 360 dp and retain the standard-nav border assertion:

```dart
testWidgets('floating top dock matches bottom dock surface and fits 360px', (
  tester,
) async {
  await tester.pumpWidget(
    const _TestHost(
      size: Size(360, 800),
      child: Align(
        alignment: Alignment.topCenter,
        child: ThemeV2GlobalTopNav(
          floatingDock: true,
          transparentSurface: true,
          deviceStatus: DeviceStatusSummary.disconnected(),
          onDeviceSelected: _noopDeviceTarget,
          onNotificationsPressed: _noop,
        ),
      ),
    ),
  );

  final dock = find.byKey(ThemeV2GlobalTopNav.floatingDockKey);
  expect(tester.getSize(dock), const Size(328, 60));
  expect(tester.getSize(find.byType(ThemeV2GlobalTopNav)).height,
      ThemeV2GlobalTopNav.floatingExtent);
  final material = tester.widget<Material>(dock);
  final shape = material.shape! as RoundedRectangleBorder;
  expect(material.elevation, ThemeV2FloatingDock.elevation);
  expect(material.color, ThemeV2Tokens.light.surface);
  expect(shape.borderRadius, BorderRadius.circular(ThemeV2FloatingDock.lightRadius));
  expect(shape.side.color, ThemeV2Tokens.light.border);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run the shell test and confirm RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_shell_test.dart --plain-name "floating top dock matches bottom dock surface and fits 360px"
```

Expected: compile failure because the floating top-dock API and shared constants do not exist.

- [ ] **Step 3: Publish the dock style constants and build the variant**

Add these public constants to `ThemeV2FloatingDock` and use them in its existing light branch:

```dart
static const double elevation = 8;
static const double lightRadius = 18;
static const Color lightShadowColor = Color(0x1F000000);
```

Add to `ThemeV2GlobalTopNav`:

```dart
final bool floatingDock;
static const floatingDockKey = Key('theme-v2-floating-top-dock');
static const double floatingHorizontalInset = 16;
static const double floatingVerticalInset = 8;
static const double floatingContentHeight = 60;
static const double floatingExtent = 76;
```

When `floatingDock` is true, return a transparent `SizedBox(height: floatingExtent)` containing horizontal and vertical padding and an inner `Material` keyed by `floatingDockKey`. Give it the shared elevation, light shadow, `tokens.surface`, an 18 dp rounded rectangle, and `tokens.border`. Move the existing `Row` into a private `_TopNavContent` widget so the standard and floating branches share one content tree. The standard branch retains height 56 and its bottom border.

- [ ] **Step 4: Run all shell widget tests and confirm GREEN**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_shell_test.dart
```

Expected: all tests pass; semantics and device-menu tests remain green at 360 and 411 dp.

- [ ] **Step 5: Commit the top-dock component increment**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat: add floating today top dock"
```

---

### Task 3: Wire Today-only layout and update visual regression coverage

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Update: `mobile/test/theme_v2/home/goldens/today-dot-*-411-light.png`
- Update: `mobile/test/theme_v2/home/goldens/today-dot-idle-411-tall-light.png`

**Interfaces:**
- Consumes: `ThemeV2GlobalTopNav.floatingDock` and `ThemeV2GlobalTopNav.floatingExtent` from Task 2.
- Produces: light Today-only floating chrome with content, Reka drag bounds, and refresh failure UI below the dock.

- [ ] **Step 1: Write failing shell-selection assertions**

Update the Today light-mode test to assert the explicit variant, Calendar to assert it is off, and the dark-mode test to assert it is off:

```dart
expect(nav.floatingDock, isTrue);

await tester.tap(find.bySemanticsLabel('日历'));
await tester.pumpAndSettle();
expect(
  tester.widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav)).floatingDock,
  isFalse,
);
```

In the dark test:

```dart
expect(
  tester.widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav)).floatingDock,
  isFalse,
);
```

- [ ] **Step 2: Run the navigation test and confirm RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart --plain-name "Today experiment extends one body behind transparent chrome"
```

Expected: FAIL because the app shell does not select `floatingDock` yet.

- [ ] **Step 3: Wire the app shell and Today inset**

Pass the explicit flag from `ThemeV2AppShell`:

```dart
final todayFloatingDock = continuousToday && _index == 0;
final standardTopNav = ThemeV2GlobalTopNav(
  transparentSurface: todayFloatingDock,
  floatingDock: todayFloatingDock,
  deviceStatus:
      widget.deviceStatus ??
      _deviceStatusAdapter?.value ??
      const DeviceStatusSummary.disconnected(),
  unreadNotificationCount: widget.usesLegacyInbox
      ? _inboxController.unreadCount
      : RekaNotifications.instance.unread,
  onDeviceSelected: (target) => _openDevice(context, target),
  onNotificationsPressed: () => _openNotifications(context),
);
```

In `TodayDotExperimentPage`, replace the 56 dp extended inset with:

```dart
final topChromeInset = widget.extendUnderChrome
    ? ThemeV2GlobalTopNav.floatingExtent
    : 0.0;
```

This value already flows into heading placement, drag clamping, quick-action positioning, and refresh-failure placement through `TodayDotMatrixScene`.

- [ ] **Step 4: Run selection, page, controller, and scene tests**

Run:

```bash
cd mobile
flutter test \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Switch the golden host to the floating variant and regenerate fixtures**

Set `floatingDock: true` on the golden host's `ThemeV2GlobalTopNav`, then run:

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
flutter test test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: the update command rewrites the six existing light Today fixtures, and the verification run passes without pixel differences.

- [ ] **Step 6: Run scoped analysis and the complete affected suite**

Run:

```bash
cd mobile
flutter analyze \
  lib/theme_v2/home/today_dot_matrix_painter.dart \
  lib/theme_v2/home/today_dot_experiment_page.dart \
  lib/theme_v2/shell/theme_v2_global_top_nav.dart \
  lib/theme_v2/shell/theme_v2_floating_dock.dart \
  lib/theme_v2/shell/theme_v2_app_shell.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter test \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: analysis reports no issues and all affected tests pass.

- [ ] **Step 7: Build and perform the physical-device pass**

Run:

```bash
cd mobile
flutter build apk --debug
flutter devices
flutter run -d RFCY71B21YK --debug
```

Verify on the connected phone:

- the white rise has no closed circular edge at inhale, bright, or falling phases;
- two 3 by 3 warm-orange eyes fade in at the bright phase and disappear while dragging;
- the Reka drag target, quick-action anchor, and breathing recovery still work;
- the top dock has 16 dp side insets with dots visible around it;
- the device menu opens below its button and the notification/theme actions remain usable;
- Calendar and dark mode retain the standard full-width top navigation.

- [ ] **Step 8: Commit the integrated visual increment**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart mobile/test/theme_v2/home/goldens
git commit -m "feat: integrate today robot reka chrome"
```
