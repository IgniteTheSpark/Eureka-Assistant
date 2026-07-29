# Theme V2 Calendar Scale Droplet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Calendar scale-switch droplet emerge at the user's gesture position, follow vertical movement with stable damping, and render as restrained premium frosted glass in Light and Dark themes.

**Architecture:** Keep pointer intent and ephemeral drag state in `ThemeV2CalendarPage`, adding only the local droplet center to `_CalendarScaleDragFeedback`. Extract the visual overlay into a focused `CalendarScaleDragIndicator` widget that owns clamping, reduced-motion positioning, clipped backdrop blur, shape painting, and repaint isolation without rebuilding Calendar content.

**Tech Stack:** Flutter/Dart, `Listener`, `ValueNotifier`, `AnimatedPositioned`, `BackdropFilter`, `CustomClipper`, `CustomPainter`, Flutter widget tests and golden tests.

## Global Constraints

- Use `PointerEvent.localPosition`; never mix global screen coordinates with the Calendar-local viewport.
- Apply 60 percent of vertical displacement from the pointer-down origin.
- Ignore vertical displacement below 3 logical pixels.
- Clamp the droplet center by half its current height plus 12 logical pixels at the top and bottom.
- Keep the existing horizontal activation, label, commit, cancellation, and confirmation behavior unchanged.
- Restrict backdrop filtering and repainting to the droplet overlay.
- Use Theme V2 tokens for all theme-dependent colors.
- Do not add a fragment shader, page snapshot, new package, or persistent scale control.
- Reduced Motion removes morphing and positional interpolation while retaining position-aware frosted feedback.

---

## File structure

- Create `mobile/lib/theme_v2/calendar/calendar_scale_droplet.dart`: focused visual component, path geometry, clipper, and painters.
- Modify `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`: local pointer tracking, damped center calculation, feedback state, and visual component integration.
- Modify `mobile/test/theme_v2/calendar/calendar_flow_test.dart`: behavioral and structural widget coverage.
- Modify `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart`: high- and low-origin Light/Dark golden scenarios.
- Update `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-411-light.png` and `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-411-dark.png`: upper-origin material baselines.
- Create `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-lower-411-light.png` and `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-lower-411-dark.png`: lower-origin material baselines.

### Task 1: Position-aware damped gesture feedback

**Files:**
- Modify: `mobile/test/theme_v2/calendar/calendar_flow_test.dart:730`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart:75-240`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart:560-720`

**Interfaces:**
- Consumes: `PointerEvent.localPosition`, existing `_scalePointerOrigin`, `_scalePointerAxis`, and `_updateScaleDragFeedback`.
- Produces: `_CalendarScaleDragFeedback.centerY` as a nullable Calendar-local logical-pixel center; null preserves centered feedback for pointerless scroll input.

- [ ] **Step 1: Add failing origin and damped-follow widget tests**

Add helpers and tests that measure the keyed indicator:

```dart
Future<Offset> revealScaleDroplet(
  WidgetTester tester, {
  required Offset start,
  Offset firstMove = const Offset(-50, 0),
}) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(firstMove);
  await tester.pump();
  await gesture.moveBy(const Offset(-10, 0));
  await tester.pump(const Duration(milliseconds: 90));
  addTearDown(gesture.cancel);
  return tester.getCenter(
    find.byKey(const ValueKey('calendar-scale-drag-indicator')),
  );
}
```

Add one test that starts 140 logical pixels below the PageView top and another
that starts 140 logical pixels above its bottom. Assert that their rendered
centers differ by more than 200 logical pixels instead of both appearing at
the viewport center.

Add a damped-follow assertion:

```dart
final before = tester.getCenter(indicator).dy;
await gesture.moveBy(const Offset(-4, 50));
await tester.pump(const Duration(milliseconds: 90));
final after = tester.getCenter(indicator).dy;
expect(after - before, closeTo(30, 3));
```

Add a 2-pixel vertical-noise assertion whose rendered Y remains unchanged
within one logical pixel.

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart --plain-name "scale droplet"
```

Expected: FAIL because the existing `Align.centerLeft/centerRight` ignores the
gesture's local Y and `_CalendarScaleDragFeedback` has no center.

- [ ] **Step 3: Store local pointer coordinates and calculate damped Y**

Change pointer-down and pointer-move to use local coordinates:

```dart
void _handleScalePointerDown(PointerDownEvent event) {
  _scaleSettleTimer?.cancel();
  _scalePointerOrigin = event.localPosition;
  _scalePointerAxis = null;
  _scaleDragOriginPage = _pageIndex;
  _scaleDragFeedback.value = null;
}

void _handleScalePointerMove(PointerMoveEvent event) {
  final origin = _scalePointerOrigin;
  if (origin == null) return;
  final delta = event.localPosition - origin;
  final horizontal = delta.dx.abs();
  final vertical = delta.dy.abs();
  if (_scalePointerAxis == null && (horizontal > 12 || vertical > 12)) {
    _scalePointerAxis = horizontal > vertical
        ? Axis.horizontal
        : Axis.vertical;
  }
  if (_scalePointerAxis == Axis.horizontal) {
    final verticalDisplacement = delta.dy.abs() < 3 ? 0.0 : delta.dy * 0.6;
    _updateScaleDragFeedback(
      -delta.dx,
      centerY: origin.dy + verticalDisplacement,
    );
  }
}
```

Extend feedback construction:

```dart
void _updateScaleDragFeedback(
  double displacement, {
  double? centerY,
}) {
  // Keep the existing distance and direction calculations.
  _scaleDragFeedback.value = _CalendarScaleDragFeedback(
    target: CalendarMode.values[targetPage % CalendarMode.values.length],
    onRightEdge: direction > 0,
    shapeProgress: ((distance - 12) / 26).clamp(0, 1),
    labelProgress: ((distance - 30) / 8).clamp(0, 1),
    centerY: centerY,
  );
}
```

Define the new field:

```dart
final double? centerY;
```

- [ ] **Step 4: Position and clamp the current indicator before extraction**

Replace center `Align` with a `LayoutBuilder` and compute the positioned
geometry with:

```dart
final desiredCenterY = feedback.centerY ?? constraints.maxHeight / 2;
final minCenterY = height / 2 + 12;
final unclampedMaxCenterY = constraints.maxHeight - height / 2 - 12;
final maxCenterY = math.max(minCenterY, unclampedMaxCenterY);
final centerY = desiredCenterY.clamp(minCenterY, maxCenterY).toDouble();
final top = centerY - height / 2;
```

Add `dart:math` as `math`, then place the existing keyed `SizedBox` subtree
unchanged inside an `AnimatedPositioned` with `top: top`, edge-selected
`left/right: 0`, `width`, `height`, `Curves.easeOutCubic`, and a duration of
zero under Reduce Motion or 70 milliseconds otherwise. The
`AnimatedPositioned` must be the sole child of a full-size `Stack`, so the
overlay continues to ignore pointer events while covering the Calendar
viewport.

- [ ] **Step 5: Run focused tests and confirm GREEN**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart --plain-name "scale droplet"
```

Expected: PASS for top origin, bottom origin, 60-percent follow, 3-pixel
dead-zone, and clamp behavior.

- [ ] **Step 6: Commit the position behavior**

```bash
git add mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart
git commit -m "fix(calendar): anchor scale droplet to gesture"
```

### Task 2: Restrained frosted-glass component

**Files:**
- Create: `mobile/lib/theme_v2/calendar/calendar_scale_droplet.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart:1-25`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart:560-830`
- Modify: `mobile/test/theme_v2/calendar/calendar_flow_test.dart:730`

**Interfaces:**
- Consumes: `targetLabel`, `onRightEdge`, `shapeProgress`, `labelProgress`, and nullable `centerY`.
- Produces: `CalendarScaleDragIndicator`, with stable keys `calendar-scale-drag-indicator`, `calendar-scale-drag-droplet`, `calendar-scale-drag-glass`, and `calendar-scale-drag-repaint-boundary`.

- [ ] **Step 1: Add a failing structural glass test**

After revealing a non-reduced-motion droplet, assert:

```dart
final droplet = find.byKey(
  const ValueKey('calendar-scale-drag-droplet'),
);
expect(
  find.descendant(of: droplet, matching: find.byType(BackdropFilter)),
  findsOneWidget,
);
expect(
  find.byKey(const ValueKey('calendar-scale-drag-glass')),
  findsOneWidget,
);
expect(
  find.byKey(const ValueKey('calendar-scale-drag-repaint-boundary')),
  findsOneWidget,
);
```

Retain the existing assertion that reduced motion does not render the morphing
droplet key.

- [ ] **Step 2: Run the structural test and confirm RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart --plain-name "scale droplet uses clipped frosted glass"
```

Expected: FAIL because the existing painter has an opaque fill and no
`BackdropFilter`.

- [ ] **Step 3: Create the focused visual API**

Create this public widget shell:

```dart
class CalendarScaleDragIndicator extends StatelessWidget {
  const CalendarScaleDragIndicator({
    super.key,
    required this.targetLabel,
    required this.onRightEdge,
    required this.shapeProgress,
    required this.labelProgress,
    required this.centerY,
  });

  final String targetLabel;
  final bool onRightEdge;
  final double shapeProgress;
  final double labelProgress;
  final double? centerY;
}
```

Move width/height interpolation, clamping, `AnimatedPositioned`, label layout,
and reduced-motion edge feedback into this widget. The positioned child must
be a `RepaintBoundary` keyed `calendar-scale-drag-repaint-boundary`; its only
child is the existing `SizedBox` keyed `calendar-scale-drag-indicator` with the
calculated width and height. Its `Stack` contains the non-reduced glass from
Step 5 or the existing reduced-motion decorated edge, followed by the existing
opacity/padding/label layer.

- [ ] **Step 4: Share one droplet path between clipper and painters**

Define one private geometry function:

```dart
Path _dropletPath(Size size, {required bool onRightEdge}) {
  final width = size.width;
  final height = size.height;
  final rightPath = Path()
    ..moveTo(width, 0)
    ..cubicTo(
      width * 0.78,
      0,
      width * 0.84,
      height * 0.18,
      width * 0.62,
      height * 0.23,
    )
    ..cubicTo(
      width * 0.31,
      height * 0.29,
      width * 0.18,
      height * 0.38,
      width * 0.15,
      height * 0.5,
    )
    ..cubicTo(
      width * 0.18,
      height * 0.62,
      width * 0.31,
      height * 0.71,
      width * 0.62,
      height * 0.77,
    )
    ..cubicTo(
      width * 0.84,
      height * 0.82,
      width * 0.78,
      height,
      width,
      height,
    )
    ..close();
  if (onRightEdge) return rightPath;
  return rightPath.transform(
    (Matrix4.identity()
          ..translate(width)
          ..scale(-1.0, 1.0))
        .storage,
  );
}
```

Use `_CalendarScaleDropletClipper` and both painters with this function; do not
duplicate cubic control points.

- [ ] **Step 5: Build the bounded frosted-glass stack**

Inside the non-reduced-motion droplet, use:

```dart
Stack(
  key: const ValueKey('calendar-scale-drag-droplet'),
  fit: StackFit.expand,
  children: [
    CustomPaint(
      painter: _CalendarScaleDropletShadowPainter(
        onRightEdge: onRightEdge,
        shadow: tokens.foreground.withValues(
          alpha: brightness == Brightness.light ? 0.10 : 0.24,
        ),
      ),
    ),
    ClipPath(
      clipper: _CalendarScaleDropletClipper(onRightEdge),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          key: const ValueKey('calendar-scale-drag-glass'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tokens.surface.withValues(
                  alpha: brightness == Brightness.light ? 0.36 : 0.24,
                ),
                tokens.surface.withValues(
                  alpha: brightness == Brightness.light ? 0.28 : 0.18,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    CustomPaint(
      painter: _CalendarScaleDropletFinishPainter(
        onRightEdge: onRightEdge,
        rim: Color.lerp(
          tokens.surface,
          tokens.foreground,
          brightness == Brightness.light ? 0.0 : 0.68,
        )!.withValues(
          alpha: brightness == Brightness.light ? 0.62 : 0.38,
        ),
        accent: tokens.accent.withValues(
          alpha: brightness == Brightness.light ? 0.16 : 0.22,
        ),
        specular: tokens.surface.withValues(
          alpha: brightness == Brightness.light ? 0.48 : 0.22,
        ),
      ),
    ),
  ],
)
```

The finish painter draws a gradient one-pixel rim, an upper-outer radial
highlight, and a faint edge-adjacent accent reflection, all clipped to
`_dropletPath`.

- [ ] **Step 6: Replace the page-local visual implementation**

Import `calendar_scale_droplet.dart`, construct:

```dart
return CalendarScaleDragIndicator(
  targetLabel: _calendarScaleLabel(feedback.target),
  onRightEdge: feedback.onRightEdge,
  shapeProgress: feedback.shapeProgress,
  labelProgress: feedback.labelProgress,
  centerY: feedback.centerY,
);
```

Delete `_CalendarScaleDragIndicator` and `_CalendarScaleDropletPainter` from
`theme_v2_calendar_page.dart`. Remove its `dart:ui` import once no `ui.*`
symbols remain.

- [ ] **Step 7: Run structural and existing scale tests and confirm GREEN**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart
```

Expected: PASS, including the new `BackdropFilter`/`RepaintBoundary` checks,
origin tracking, reduced motion, scale switching, and confirmation.

- [ ] **Step 8: Commit the material component**

```bash
git add mobile/lib/theme_v2/calendar/calendar_scale_droplet.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart
git commit -m "feat(calendar): render frosted scale droplet"
```

### Task 3: Golden, regression, and Android verification

**Files:**
- Modify: `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart:170-215`
- Modify: `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-411-light.png`
- Modify: `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-411-dark.png`
- Create: `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-lower-411-light.png`
- Create: `mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-lower-411-dark.png`

**Interfaces:**
- Consumes: stable scale droplet keys and the 411-pixel Calendar fixture.
- Produces: Light/Dark visual baselines at upper and lower gesture origins plus verified APK/device evidence.

- [ ] **Step 1: Add high- and low-origin golden scenarios**

Factor a local gesture helper:

```dart
Future<void> revealDropletAt(
  WidgetTester tester,
  Finder pages, {
  required double dyFromTop,
}) async {
  final rect = tester.getRect(pages);
  final gesture = await tester.startGesture(
    Offset(rect.center.dx, rect.top + dyFromTop),
  );
  await gesture.moveBy(const Offset(-50, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(-10, 0));
  await tester.pump(const Duration(milliseconds: 90));
  addTearDown(gesture.cancel);
}
```

Use `dyFromTop: 150` for
`calendar-flow-drag-month-411-$suffix.png` and
`dyFromTop: tester.getSize(pages).height - 150` for
`calendar-flow-drag-month-lower-411-$suffix.png`.

- [ ] **Step 2: Run the golden tests and inspect generated diffs**

Run:

```bash
cd mobile
flutter test --update-goldens test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
```

Expected: PASS and four scale-drag baselines showing distinct vertical origins
and readable restrained frosted glass in both themes.

Inspect all four PNGs at original resolution. Reject and tune if the surface
looks opaque, the rim glows, the label loses contrast, or the lower droplet
overlaps Dock clearance.

- [ ] **Step 3: Run formatting, analysis, and Calendar regression**

Run:

```bash
dart format lib/theme_v2/calendar/theme_v2_calendar_page.dart lib/theme_v2/calendar/calendar_scale_droplet.dart test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
flutter analyze lib/theme_v2/calendar/theme_v2_calendar_page.dart lib/theme_v2/calendar/calendar_scale_droplet.dart test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
flutter test test/theme_v2/calendar
```

Expected: formatter makes no unexpected semantic changes, analysis reports no
issues, and the full Calendar suite passes.

- [ ] **Step 4: Build the local Android debug APK**

Run:

```bash
cd mobile
flutter build apk --debug
cp build/app/outputs/flutter-apk/app-debug.apk build/app/outputs/flutter-apk/ureka-calendar-scale-droplet-debug.apk
shasum -a 256 build/app/outputs/flutter-apk/ureka-calendar-scale-droplet-debug.apk
```

Expected: successful debug APK and a recorded SHA-256 digest.

- [ ] **Step 5: Install and verify on the existing Android device**

Run:

```bash
cd mobile
flutter devices
adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/ureka-calendar-scale-droplet-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Verify Flow-to-Month and Month-to-Year drags from upper, center, and lower
touch points in Light and Dark. Confirm damped vertical following, safe-area
clamping, readable labels, correct page commit/cancel, and no stale overlay.

- [ ] **Step 6: Record screenshot and frame-timing evidence**

Capture at least one Light or Dark droplet at a non-central origin. Reset gfx
stats, perform repeated scale drags, then inspect:

```bash
adb -s RFCY71B21YK shell dumpsys gfxinfo com.eureka.mindapp reset
adb -s RFCY71B21YK shell dumpsys gfxinfo com.eureka.mindapp
```

Expected: no perceptible interaction hitch and no material regression from the
prior 5 ms p99 Calendar scale-switch baseline. If timing regresses, first
reduce blur sigma while retaining the visual hierarchy.

- [ ] **Step 7: Commit visual baselines and verified implementation**

```bash
git add mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-411-light.png mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-411-dark.png mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-lower-411-light.png mobile/test/theme_v2/calendar/goldens/calendar-flow-drag-month-lower-411-dark.png
git commit -m "test(calendar): cover positioned glass droplet"
```

Record the APK path, checksum, test count, device model, screenshot path, and
gfx timing in the final handoff.
