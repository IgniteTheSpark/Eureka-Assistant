# Today Continuous Dot Field and Reka Bulge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the light Today experiment one continuous native Flutter dot field behind Top Nav and Dock surroundings, with Reka rendered as a draggable white convex bulge driven by the complete React Bits Dot Field parameter contract.

**Architecture:** Add an immutable `TodayDotFieldConfig` containing every React Bits prop, then thread it through the existing controller, mutable simulation, painter, scene, and page. Add a Today-only extended-body presentation to the shared scaffold so the scene owns one coordinate space beneath transparent standard navigation while the floating Dock capsule stays opaque. Keep the native ticker, lifecycle, refresh, gesture arbitration, and quick actions.

**Tech Stack:** Flutter/Dart, `CustomPainter`, `Ticker`, Material shell widgets, `flutter_test`, Golden tests. No WebGL, WebView, React runtime, fragment shader, package, or image asset.

## Global Constraints

- Work only in `/Users/admin/workwork/eureka-staff/Eureka-Assistant/.worktrees/home-revamp` on branch `首页-revamp`.
- The feature remains behind `--dart-define=TODAY_DOT_EXPERIMENT=true`.
- Apply dots only to the light Today experiment; Calendar, Library, Dark Mode, capture top bar, and other routes retain their existing surfaces.
- Use one continuous dot coordinate space behind Top Nav, content, Dock surroundings, and bottom safe area.
- Top Nav may be transparent only for the active standard Today experiment; the floating Dock capsule remains white and opaque.
- Reka is the white convex bulge. Do not paint the previous dense dark dot sphere.
- A drag must begin inside the visible Reka core. Empty-field drag remains inert for Reka and available to pull-to-refresh.
- Keep live quick-action anchoring, bounded inertia, soft edge attraction, mounted-scene position, lifecycle pausing, and Reduce Motion.
- Preserve all eleven React Bits names: `dotRadius`, `dotSpacing`, `cursorRadius`, `cursorForce`, `bulgeOnly`, `bulgeStrength`, `glowRadius`, `sparkle`, `waveAmplitude`, `gradientFrom`, `gradientTo`, and `glowColor`.
- Mobile defaults: `1.5`, `14`, `54`, `0.1`, `true`, `67`, `150`, `false`, `0`, brand gray-green, deeper brand gray-green, and black respectively.
- Eyes are warm orange, appear inside the white bulge with idle glow strength, hide during drag, and remain faint in Reduce Motion.
- Run formatting, focused tests, complete regressions, static analysis, Golden inspection, APK build, and physical-device verification before completion.

---

## File Structure

- Create `mobile/lib/theme_v2/home/today_dot_field_config.dart`: immutable React Bits parameter names, defaults, validation, and Dart documentation.
- Modify `mobile/lib/theme_v2/home/today_dot_field_controller.dart`: accept config and derive safe bounds from the larger core.
- Modify `mobile/lib/theme_v2/home/today_dot_field_simulation.dart`: config-driven spacing, bulge/force modes, wave, and deterministic sparkle selection.
- Modify `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`: gradient dots, black glow, white convex core, orange eyes, and no dark sphere.
- Modify `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart`: shared config, larger hit target, full-Chrome geometry, and painter inputs.
- Modify `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`: config injection and extended-Chrome scene geometry.
- Modify `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`: opt-in extended-body layout.
- Modify `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`: opt-in transparent standard surface.
- Modify `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`: enable the two opt-ins only for the active Today experiment.
- Create `mobile/test/theme_v2/home/today_dot_field_config_test.dart`.
- Modify the existing controller, simulation, painter, scene/page, shell navigation, and Golden tests.

---

### Task 1: React Bits Parameter Contract

**Files:**
- Create: `mobile/lib/theme_v2/home/today_dot_field_config.dart`
- Create: `mobile/test/theme_v2/home/today_dot_field_config_test.dart`

**Interfaces:**
- Produces: `@immutable class TodayDotFieldConfig`
- Produces: `const TodayDotFieldConfig({...})` with the eleven exact camelCase fields.
- Produces: `TodayDotFieldConfig copyWith({...})` for deterministic state-specific tests.
- Consumes: Flutter `Color` and `@immutable` only.

- [ ] **Step 1: Write the failing config contract tests**

Create `mobile/test/theme_v2/home/today_dot_field_config_test.dart`:

```dart
import 'package:eureka/theme_v2/home/today_dot_field_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults expose every React Bits Dot Field parameter', () {
    const config = TodayDotFieldConfig();

    expect(config.dotRadius, 1.5);
    expect(config.dotSpacing, 14);
    expect(config.cursorRadius, 54);
    expect(config.cursorForce, .1);
    expect(config.bulgeOnly, isTrue);
    expect(config.bulgeStrength, 67);
    expect(config.glowRadius, 150);
    expect(config.sparkle, isFalse);
    expect(config.waveAmplitude, 0);
    expect(config.gradientFrom, const Color(0xA674837A));
    expect(config.gradientTo, const Color(0x8F607269));
    expect(config.glowColor, Colors.black);
  });

  test('copyWith changes every field without changing the source', () {
    const source = TodayDotFieldConfig();
    final changed = source.copyWith(
      dotRadius: 2,
      dotSpacing: 12,
      cursorRadius: 60,
      cursorForce: .25,
      bulgeOnly: false,
      bulgeStrength: 80,
      glowRadius: 170,
      sparkle: true,
      waveAmplitude: 2,
      gradientFrom: Colors.white,
      gradientTo: Colors.grey,
      glowColor: Colors.blue,
    );

    expect(changed.dotRadius, 2);
    expect(changed.dotSpacing, 12);
    expect(changed.cursorRadius, 60);
    expect(changed.cursorForce, .25);
    expect(changed.bulgeOnly, isFalse);
    expect(changed.bulgeStrength, 80);
    expect(changed.glowRadius, 170);
    expect(changed.sparkle, isTrue);
    expect(changed.waveAmplitude, 2);
    expect(changed.gradientFrom, Colors.white);
    expect(changed.gradientTo, Colors.grey);
    expect(changed.glowColor, Colors.blue);
    expect(source, const TodayDotFieldConfig());
  });

  test('invalid geometric values assert in debug builds', () {
    expect(() => TodayDotFieldConfig(dotRadius: 0), throwsAssertionError);
    expect(() => TodayDotFieldConfig(dotSpacing: 0), throwsAssertionError);
    expect(() => TodayDotFieldConfig(cursorRadius: 0), throwsAssertionError);
    expect(() => TodayDotFieldConfig(glowRadius: 40), throwsAssertionError);
    expect(() => TodayDotFieldConfig(cursorForce: -1), throwsAssertionError);
    expect(() => TodayDotFieldConfig(bulgeStrength: -1), throwsAssertionError);
    expect(() => TodayDotFieldConfig(waveAmplitude: -1), throwsAssertionError);
  });
}
```

- [ ] **Step 2: Run the config test and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_field_config_test.dart
```

Expected: FAIL because `today_dot_field_config.dart` does not exist.

- [ ] **Step 3: Implement the immutable config**

Create `mobile/lib/theme_v2/home/today_dot_field_config.dart` with this public shape and full Dart comments:

```dart
import 'package:flutter/material.dart';

@immutable
class TodayDotFieldConfig {
  const TodayDotFieldConfig({
    this.dotRadius = 1.5,
    this.dotSpacing = 14,
    this.cursorRadius = 54,
    this.cursorForce = .1,
    this.bulgeOnly = true,
    this.bulgeStrength = 67,
    this.glowRadius = 150,
    this.sparkle = false,
    this.waveAmplitude = 0,
    this.gradientFrom = const Color(0xA674837A),
    this.gradientTo = const Color(0x8F607269),
    this.glowColor = Colors.black,
  }) : assert(dotRadius > 0),
       assert(dotSpacing > 0),
       assert(cursorRadius > 0),
       assert(glowRadius >= cursorRadius),
       assert(cursorForce >= 0),
       assert(bulgeStrength >= 0),
       assert(waveAmplitude >= 0);

  /// Radius of each individual dot in logical pixels.
  final double dotRadius;

  /// Center-to-center spacing between dots in logical pixels.
  final double dotSpacing;

  /// Radius of the visible white Reka convex core in this mobile adaptation.
  final double cursorRadius;

  /// Force applied to nearby dots when [bulgeOnly] is false.
  final double cursorForce;

  /// Whether dots use a bounded radial bulge instead of pushed-dot physics.
  final bool bulgeOnly;

  /// Strength of the local bulge around Reka.
  final double bulgeStrength;

  /// Radius of the radial outer glow around Reka.
  final double glowRadius;

  /// Whether a deterministic three percent subset of dots enlarges.
  final bool sparkle;

  /// Amplitude of the field-wide wave displacement in logical pixels.
  final double waveAmplitude;

  /// Starting color of the diagonal dot gradient.
  final Color gradientFrom;

  /// Ending color of the diagonal dot gradient.
  final Color gradientTo;

  /// Color of the radial outer glow around Reka.
  final Color glowColor;

  TodayDotFieldConfig copyWith({
    double? dotRadius,
    double? dotSpacing,
    double? cursorRadius,
    double? cursorForce,
    bool? bulgeOnly,
    double? bulgeStrength,
    double? glowRadius,
    bool? sparkle,
    double? waveAmplitude,
    Color? gradientFrom,
    Color? gradientTo,
    Color? glowColor,
  }) => TodayDotFieldConfig(
    dotRadius: dotRadius ?? this.dotRadius,
    dotSpacing: dotSpacing ?? this.dotSpacing,
    cursorRadius: cursorRadius ?? this.cursorRadius,
    cursorForce: cursorForce ?? this.cursorForce,
    bulgeOnly: bulgeOnly ?? this.bulgeOnly,
    bulgeStrength: bulgeStrength ?? this.bulgeStrength,
    glowRadius: glowRadius ?? this.glowRadius,
    sparkle: sparkle ?? this.sparkle,
    waveAmplitude: waveAmplitude ?? this.waveAmplitude,
    gradientFrom: gradientFrom ?? this.gradientFrom,
    gradientTo: gradientTo ?? this.gradientTo,
    glowColor: glowColor ?? this.glowColor,
  );
}
```

- [ ] **Step 4: Format and verify GREEN**

Run:

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_field_config.dart test/theme_v2/home/today_dot_field_config_test.dart
flutter test test/theme_v2/home/today_dot_field_config_test.dart
flutter analyze lib/theme_v2/home/today_dot_field_config.dart test/theme_v2/home/today_dot_field_config_test.dart
```

Expected: three tests PASS and analyzer reports `No issues found!`.

- [ ] **Step 5: Commit the parameter contract**

```bash
git add mobile/lib/theme_v2/home/today_dot_field_config.dart mobile/test/theme_v2/home/today_dot_field_config_test.dart
git commit -m "feat: model today dot field parameters"
```

---

### Task 2: Config-Driven Controller and Dot Simulation

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dot_field_controller.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_field_simulation.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_field_controller_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_field_simulation_test.dart`

**Interfaces:**
- Consumes: `TodayDotFieldConfig` from Task 1.
- Produces: `TodayDotFieldController({this.config = const TodayDotFieldConfig()})`.
- Produces: `TodayDotFieldSimulation({this.config = const TodayDotFieldConfig()})`.
- Produces: `bool isSparkle(int index)` and config-driven `step(..., required double fieldPhase)`.

- [ ] **Step 1: Add failing controller and simulation tests**

Append controller coverage:

```dart
test('larger cursor radius expands safe bounds and visual target', () {
  final small = TodayDotFieldController(
    config: const TodayDotFieldConfig(cursorRadius: 40),
  )..layout(
      const Size(411, 960),
      reservedInsets: const EdgeInsets.fromLTRB(18, 144, 18, 153),
    );
  final large = TodayDotFieldController(
    config: const TodayDotFieldConfig(cursorRadius: 60),
  )..layout(
      const Size(411, 960),
      reservedInsets: const EdgeInsets.fromLTRB(18, 144, 18, 153),
    );

  expect(large.safeBounds.left, greaterThan(small.safeBounds.left));
  expect(large.safeBounds.right, lessThan(small.safeBounds.right));
});
```

Replace the simulation spacing assertion and add parameter behavior:

```dart
test('dotSpacing builds the reusable geometry', () {
  final simulation = TodayDotFieldSimulation(
    config: const TodayDotFieldConfig(dotSpacing: 14),
  );
  simulation.layout(const Size(42, 42));
  final nodes = simulation.nodes;

  expect(nodes, hasLength(9));
  expect(nodes.first.anchor, const Offset(7, 7));
  simulation.layout(const Size(42, 42));
  expect(identical(nodes, simulation.nodes), isTrue);
});

test('bulge strength and cursor force affect distinct modes', () {
  final bulge = TodayDotFieldSimulation(
    config: const TodayDotFieldConfig(
      dotSpacing: 14,
      bulgeOnly: true,
      bulgeStrength: 80,
    ),
  )..layout(const Size(280, 280));
  final physics = TodayDotFieldSimulation(
    config: const TodayDotFieldConfig(
      dotSpacing: 14,
      bulgeOnly: false,
      cursorForce: .5,
    ),
  )..layout(const Size(280, 280));

  for (var frame = 0; frame < 20; frame++) {
    for (final simulation in [bulge, physics]) {
      simulation.step(
        1 / 60,
        rekaCenter: const Offset(140, 140),
        state: TodayRekaMotionState.dragging,
        dragEngagement: 1,
        breathAmount: 1,
        fieldPhase: frame / 20,
        reduceMotion: false,
      );
    }
  }

  expect(bulge.nodes.any((node) => node.position != node.anchor), isTrue);
  expect(physics.nodes.any((node) => node.velocity.distance > 0), isTrue);
});

test('wave and sparkle are deterministic and configurable', () {
  final simulation = TodayDotFieldSimulation(
    config: const TodayDotFieldConfig(
      dotSpacing: 14,
      waveAmplitude: 2,
      sparkle: true,
    ),
  )..layout(const Size(280, 280));
  simulation.step(
    1 / 60,
    rekaCenter: const Offset(140, 140),
    state: TodayRekaMotionState.idle,
    dragEngagement: 0,
    breathAmount: 0,
    fieldPhase: .25,
    reduceMotion: false,
  );

  expect(simulation.nodes.any((node) => node.position.dy != node.anchor.dy), isTrue);
  expect(
    List.generate(simulation.nodes.length, simulation.isSparkle),
    equals(List.generate(simulation.nodes.length, simulation.isSparkle)),
  );
});
```

- [ ] **Step 2: Run the model tests and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_field_controller_test.dart test/theme_v2/home/today_dot_field_simulation_test.dart
```

Expected: FAIL because constructors do not accept `config`, spacing is fixed at 8, and `fieldPhase` / `isSparkle` do not exist.

- [ ] **Step 3: Thread config through controller geometry**

Add `final TodayDotFieldConfig config`, set it in the controller constructor, replace `rekaVisualRadius` reads in `layout` with `config.cursorRadius`, and keep a minimum twelve-pixel geometry margin:

```dart
TodayDotFieldController({this.config = const TodayDotFieldConfig()});

final TodayDotFieldConfig config;

void layout(Size size, {required EdgeInsets reservedInsets}) {
  if (size.isEmpty) return;
  final margin = config.cursorRadius + 12;
  final next = Rect.fromLTRB(
    reservedInsets.left + margin,
    reservedInsets.top + margin,
    size.width - reservedInsets.right - margin,
    size.height - reservedInsets.bottom - margin,
  );
  // Preserve the existing normalized-position, clamp, and notification logic.
}
```

- [ ] **Step 4: Implement config-driven simulation**

Build nodes with `config.dotSpacing / 2`, use `config.glowRadius` as the local influence range, and compute the bounded bulge target:

```dart
final falloff = _smooth(1 - distance / config.glowRadius);
final strength = config.bulgeStrength / 67;
final idleScale = state == TodayRekaMotionState.idle
    ? .82 + breathAmount * .18
    : 1.0;
final displacement = 12 * strength * idleScale * falloff;

if (config.bulgeOnly) {
  target += direction * displacement;
} else {
  target += direction * displacement * .35;
  node.velocity +=
      direction * (config.cursorForce * 180 * falloff * dragEngagement * dt);
}

if (!reduceMotion && config.waveAmplitude > 0) {
  final wave = math.sin(
    node.anchor.dx * .035 + node.anchor.dy * .021 + fieldPhase * math.pi * 2,
  );
  target += Offset(0, wave * config.waveAmplitude);
}
```

Implement deterministic sparkle selection without per-frame randomness:

```dart
bool isSparkle(int index) =>
    config.sparkle && ((index * 37 + 17) % 100) < 3;
```

Keep node-list reuse, displacement caps, damping, Reduce Motion direct positioning, and `paintRevision` behavior.

- [ ] **Step 5: Update every simulation call site**

Pass `fieldPhase: _controller.breathPhase` from `TodayDotMatrixScene`, and update model/painter tests to pass an explicit `fieldPhase`. Instantiate controller and simulation from the same config in the scene.

- [ ] **Step 6: Format, run model regressions, and analyze**

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_field_controller.dart lib/theme_v2/home/today_dot_field_simulation.dart test/theme_v2/home/today_dot_field_controller_test.dart test/theme_v2/home/today_dot_field_simulation_test.dart
flutter test test/theme_v2/home/today_dot_field_config_test.dart test/theme_v2/home/today_dot_field_controller_test.dart test/theme_v2/home/today_dot_field_simulation_test.dart
flutter analyze lib/theme_v2/home/today_dot_field_config.dart lib/theme_v2/home/today_dot_field_controller.dart lib/theme_v2/home/today_dot_field_simulation.dart
```

Expected: all model tests PASS and analyzer reports no issues.

- [ ] **Step 7: Commit the model integration**

```bash
git add mobile/lib/theme_v2/home/today_dot_field_controller.dart mobile/lib/theme_v2/home/today_dot_field_simulation.dart mobile/lib/theme_v2/home/today_dot_matrix_scene.dart mobile/test/theme_v2/home/today_dot_field_controller_test.dart mobile/test/theme_v2/home/today_dot_field_simulation_test.dart mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart
git commit -m "feat: parameterize today dot field motion"
```

---

### Task 3: White Convex Reka Painter

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart`

**Interfaces:**
- Consumes: shared `TodayDotFieldConfig`, simulation nodes, controller breath and eye values.
- Produces: `TodayDotMatrixPainter(config: ...)` that paints gradient dots, black glow, white convex core, and orange eyes.
- Removes: dark `rekaMaterialFalloff` sphere treatment.

- [ ] **Step 1: Replace dark-sphere expectations with failing bulge tests**

Add a raster helper that returns pixel colors, then add tests with a small deterministic field:

```dart
test('Reka is a white convex core with an independent black glow', () async {
  const config = TodayDotFieldConfig(
    cursorRadius: 32,
    glowRadius: 72,
    dotSpacing: 14,
    glowColor: Colors.black,
  );
  final image = await renderPainter(
    config: config,
    rekaCenter: const Offset(100, 100),
    breathAmount: 1,
    eyeOpacity: 0,
  );

  final center = await pixel(image, 100, 100);
  final halo = await pixel(image, 150, 100);
  final outside = await pixel(image, 190, 100);

  expect(center.red + center.green + center.blue,
      greaterThan(outside.red + outside.green + outside.blue));
  expect(halo.red + halo.green + halo.blue,
      lessThan(outside.red + outside.green + outside.blue));
});

test('eyes are local to the white core and hidden while dragging', () async {
  final idle = await renderPainter(
    config: const TodayDotFieldConfig(),
    rekaCenter: const Offset(100, 100),
    breathAmount: 1,
    eyeOpacity: 1,
  );
  final dragging = await renderPainter(
    config: const TodayDotFieldConfig(),
    rekaCenter: const Offset(100, 100),
    rekaState: TodayRekaMotionState.dragging,
    breathAmount: 1,
    eyeOpacity: 0,
  );

  expect(await pixel(idle, 85, 100), isNot(await pixel(dragging, 85, 100)));
  expect(await pixel(idle, 10, 10), await pixel(dragging, 10, 10));
});

test('gradient and sparkle parameters affect dot rendering', () async {
  final image = await renderPainter(
    config: const TodayDotFieldConfig(
      gradientFrom: Colors.red,
      gradientTo: Colors.blue,
      sparkle: true,
    ),
    rekaCenter: const Offset(100, 100),
    breathAmount: 0,
    eyeOpacity: 0,
  );

  expect(await pixel(image, 7, 7), isNot(await pixel(image, 189, 189)));
});
```

- [ ] **Step 2: Run painter tests and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: FAIL because the painter still creates a dense dark sphere and does not accept `config`.

- [ ] **Step 3: Paint the parameterized base field**

Add `final TodayDotFieldConfig config`. For each node, derive diagonal progress and sparkle radius:

```dart
final gradientProgress =
    ((node.anchor.dx / size.width) + (node.anchor.dy / size.height)) / 2;
final dotColor = Color.lerp(
  config.gradientFrom,
  config.gradientTo,
  gradientProgress.clamp(0.0, 1.0),
)!;
final sparkleScale = field.isSparkle(index) ? 1.65 : 1.0;
canvas.drawCircle(center, config.dotRadius * sparkleScale, dotPaint..color = dotColor);
```

- [ ] **Step 4: Paint black glow and white convex core**

After dots, paint two independent radial gradients:

```dart
final glowRect = Rect.fromCircle(center: resolvedCenter, radius: config.glowRadius);
canvas.drawCircle(
  resolvedCenter,
  config.glowRadius,
  Paint()
    ..shader = RadialGradient(
      colors: [
        config.glowColor.withValues(alpha: .16 * resolvedBreath),
        config.glowColor.withValues(alpha: .055 * resolvedBreath),
        config.glowColor.withValues(alpha: 0),
      ],
      stops: const [0, .46, 1],
    ).createShader(glowRect),
);

final coreRect = Rect.fromCircle(center: resolvedCenter, radius: config.cursorRadius);
canvas.drawCircle(
  resolvedCenter,
  config.cursorRadius,
  Paint()
    ..shader = RadialGradient(
      center: const Alignment(-.22, -.28),
      colors: [
        Colors.white.withValues(alpha: .92),
        Colors.white.withValues(alpha: .72),
        Colors.white.withValues(alpha: .16),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0, .34, .76, 1],
    ).createShader(coreRect),
);
```

Scale the highlight and glow opacity by a quiet idle floor plus breath amount so Reka remains identifiable throughout the cycle. Do not color dots darker near the center.

- [ ] **Step 5: Position eyes inside the core**

Scale eye spacing from `cursorRadius` while retaining the warm orange palette:

```dart
final eyeOffset = config.cursorRadius * .28;
for (final eyeX in [-eyeOffset, eyeOffset]) {
  canvas.drawCircle(
    Offset(_snap(center.dx + eyeX), _snap(center.dy)),
    math.max(1.8, config.dotRadius * 1.35),
    eyePaint,
  );
}
```

Use the existing controller-derived `eyeOpacity`; dragging passes zero.

- [ ] **Step 6: Verify painter GREEN and inspect generated test images**

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_matrix_painter.dart test/theme_v2/home/today_dot_matrix_painter_test.dart
flutter test test/theme_v2/home/today_dot_field_config_test.dart test/theme_v2/home/today_dot_field_controller_test.dart test/theme_v2/home/today_dot_field_simulation_test.dart test/theme_v2/home/today_dot_matrix_painter_test.dart
flutter analyze lib/theme_v2/home/today_dot_matrix_painter.dart test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: model and painter tests PASS, no dark-sphere assertion remains, and analyzer is clean.

- [ ] **Step 7: Commit the renderer**

```bash
git add mobile/lib/theme_v2/home/today_dot_matrix_painter.dart mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart
git commit -m "feat: render reka as a white dot bulge"
```

---

### Task 4: Continuous Today Canvas Behind Shell Chrome

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Produces: `ThemeV2PageScaffold.extendBodyBehindChrome` defaulting to false and preserved by `withShellChrome`.
- Produces: `ThemeV2GlobalTopNav.transparentSurface` defaulting to false.
- Produces: `TodayDotExperimentPage(config:, extendUnderChrome:)`.
- Produces: dynamic Reka hit size `max(64, config.cursorRadius * 2)`.

- [ ] **Step 1: Add failing shell and gesture tests**

Add scaffold structure coverage:

```dart
testWidgets('Today experiment extends one body behind transparent chrome', (
  tester,
) async {
  await tester.pumpWidget(
    _ThemeHost(
      child: ThemeV2AppShell(
        showStartupOverlays: false,
        todayDotExperimentOverride: true,
        deviceStatus: const DeviceStatusSummary.disconnected(),
        homeRepository: const _HomeRepository(),
      ),
    ),
  );
  await tester.pump();

  final scaffold = tester.widget<ThemeV2PageScaffold>(
    find.byType(ThemeV2PageScaffold),
  );
  final nav = tester.widget<ThemeV2GlobalTopNav>(
    find.byType(ThemeV2GlobalTopNav),
  );
  expect(scaffold.extendBodyBehindChrome, isTrue);
  expect(nav.transparentSurface, isTrue);

  await tester.tap(find.bySemanticsLabel('日历'));
  await tester.pumpAndSettle();
  expect(
    tester.widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav))
        .transparentSurface,
    isFalse,
  );
});
```

Add enlarged Reka target coverage:

```dart
testWidgets('Reka target covers the configured white core', (tester) async {
  await tester.pumpWidget(
    _host(
      TodayDotMatrixScene(
        config: const TodayDotFieldConfig(cursorRadius: 60),
        refreshEmphasis: 0,
        onRekaTap: (_) {},
      ),
    ),
  );
  await tester.pump();

  expect(
    tester.getSize(find.byKey(TodayDotMatrixScene.rekaTargetKey)),
    const Size.square(120),
  );
});
```

- [ ] **Step 2: Run shell/page tests and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: FAIL because the new scaffold, nav, page, and scene parameters do not exist.

- [ ] **Step 3: Add the opt-in extended scaffold path**

Add `extendBodyBehindChrome` to the constructor, fields, and `withShellChrome`. Preserve the current Column exactly when false. When true, build:

```dart
SafeArea(
  bottom: false,
  child: Stack(
    fit: StackFit.expand,
    children: [
      body,
      if (showTopNav && topNav != null)
        Positioned(left: 0, right: 0, top: 0, child: topNav!),
      if (showDock && dock != null)
        Positioned(left: 0, right: 0, bottom: 0, child: dock!),
    ],
  ),
)
```

This gives Today one full scene behind Chrome. Do not apply the old body bottom padding in the extended path; the scene safe bounds reserve it instead.

- [ ] **Step 4: Add transparent standard Top Nav support**

Add `transparentSurface`, and resolve the Material color without changing controls:

```dart
final background = transparentSurface ? Colors.transparent : tokens.background;
return Material(
  color: background,
  child: Container(
    height: height,
    // Keep existing padding, border, semantics, and children.
  ),
);
```

- [ ] **Step 5: Enable continuous Chrome only for Today**

In `_pages`, set `extendBodyBehindChrome: widget.usesTodayDotExperiment` on page zero and pass `extendUnderChrome: true` to `TodayDotExperimentPage`. In `build`, create the standard nav with:

```dart
transparentSurface: widget.usesTodayDotExperiment && _index == 0,
```

The `CaptureActivityTopBar` remains unchanged and opaque. Other page scaffold instances retain their default false value.

- [ ] **Step 6: Adapt Today scene geometry and config ownership**

Pass one config instance through page, scene, controller, simulation, and painter. In the extended scene:

```dart
final topChromeInset = widget.extendUnderChrome
    ? ThemeV2GlobalTopNav.height
    : 0.0;
final bottomChromeInset = widget.extendUnderChrome
    ? ThemeV2FloatingDock.contentClearance + MediaQuery.paddingOf(context).bottom
    : 0.0;
final reservedInsets = EdgeInsets.fromLTRB(
  18,
  topChromeInset + 88,
  18,
  bottomChromeInset + 38,
);
final headingTop = topChromeInset + 14;
final targetSize = math.max(64.0, widget.config.cursorRadius * 2);
```

Use `targetSize / 2` for target positioning and live global anchor geometry. Continue deriving copy position from Reka center. Import shell constants only in the page and pass numeric insets into the scene if needed to preserve the existing home/shell dependency direction.

- [ ] **Step 7: Verify interaction, shell isolation, and analysis**

```bash
cd mobile
dart format lib/theme_v2/shell/theme_v2_page_scaffold.dart lib/theme_v2/shell/theme_v2_global_top_nav.dart lib/theme_v2/shell/theme_v2_app_shell.dart lib/theme_v2/home/today_dot_experiment_page.dart lib/theme_v2/home/today_dot_matrix_scene.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/theme_v2_rollout_test.dart
flutter analyze lib/theme_v2/shell/theme_v2_page_scaffold.dart lib/theme_v2/shell/theme_v2_global_top_nav.dart lib/theme_v2/shell/theme_v2_app_shell.dart lib/theme_v2/home/today_dot_experiment_page.dart lib/theme_v2/home/today_dot_matrix_scene.dart
```

Expected: page, navigation, and rollout tests PASS; Calendar/Library retain opaque standard Chrome.

- [ ] **Step 8: Commit continuous Chrome integration**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/home/today_dot_matrix_scene.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "feat: extend today dots behind shell chrome"
```

---

### Task 5: Golden Regression and Physical-Device Handoff

**Files:**
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Replace: the six `mobile/test/theme_v2/home/goldens/today-dot-*.png` files referenced by the test.
- Verify: all changed Dart files, rollout/navigation tests, Android APK, device `RFCY71B21YK`.

**Interfaces:**
- Consumes: final config, extended scene, deterministic controller/simulation injection.
- Produces: six approved Golden states and physical-device evidence.

- [ ] **Step 1: Update deterministic Golden states before production images**

Keep the existing six state names and inject the production config. Update assertions so:

```dart
expect(
  tester.getTopLeft(find.byType(TodayDotExperimentPage)).dy,
  lessThan(tester.getBottomLeft(find.byType(ThemeV2GlobalTopNav)).dy),
);
expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
```

The inhale state must show a quiet white bulge without orange eyes. The exhale state shows eyes. Dragging hides eyes and moves the white core. Reduce Motion keeps faint eyes without animated wave/sparkle. The tall state keeps one aligned grid behind Top Nav and Dock surroundings.

- [ ] **Step 2: Run Golden tests without updating and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: FAIL with visual mismatches against the previous dark-sphere and opaque-Chrome baselines.

- [ ] **Step 3: Generate and inspect all six Goldens**

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Open every referenced PNG and verify: continuous dot alignment, readable nav icons, opaque Dock capsule, visible white bulge, black glow outside the core, no dense dark sphere, eyes only in approved states, and safe placement on both viewport heights.

- [ ] **Step 4: Run complete regression and static analysis**

```bash
cd mobile
flutter test \
  test/theme_v2/home/today_dot_field_config_test.dart \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/theme_v2_rollout_test.dart
flutter analyze \
  lib/theme_v2/home/today_dot_field_config.dart \
  lib/theme_v2/home/today_dot_field_controller.dart \
  lib/theme_v2/home/today_dot_field_simulation.dart \
  lib/theme_v2/home/today_dot_matrix_painter.dart \
  lib/theme_v2/home/today_dot_matrix_scene.dart \
  lib/theme_v2/home/today_dot_experiment_page.dart \
  lib/theme_v2/shell/theme_v2_page_scaffold.dart \
  lib/theme_v2/shell/theme_v2_global_top_nav.dart \
  lib/theme_v2/shell/theme_v2_app_shell.dart
```

Expected: all tests PASS and analyzer reports `No issues found!`.

- [ ] **Step 5: Commit Golden coverage**

```bash
git add mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart mobile/test/theme_v2/home/goldens/
git commit -m "test: lock continuous today reka bulge states"
```

- [ ] **Step 6: Build, install, and launch the experiment APK**

```bash
cd mobile
flutter devices
flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$ADB -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s RFCY71B21YK reverse tcp:8000 tcp:8000
$ADB -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$ADB -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: device `SM F9660` is listed, APK builds and installs successfully, and Today opens with the new continuous field.

- [ ] **Step 7: Complete physical-device acceptance**

Verify in order:

1. Dots remain aligned behind Top Nav, content, Dock surroundings, and bottom safe area.
2. Nav icons remain readable and tappable; the Dock capsule remains opaque.
3. The white convex bulge reads as Reka without a dense dark sphere.
4. A full 5.2-second idle cycle changes bulge/glow gently and shows orange eyes only at stronger idle glow.
5. Empty-field swipe does not move Reka; pull-to-refresh remains available.
6. Drag starting on the enlarged core moves Reka, hides eyes, deforms dots locally, and preserves light bounded inertia.
7. Release settles cleanly, keeps position while mounted, then resumes breathing.
8. Tap opens exactly Create Asset, Create Report, and Start New Chat at the live anchor.
9. Calendar and Library return to their existing opaque backgrounds.
10. Reduce Motion remains calm and identifiable.

Record one full breath video and screenshots for inhale, eyes/glow, dragged rest, and quick actions.

- [ ] **Step 8: Check the final branch state**

```bash
git status --short --branch
git log --oneline --decorate -10
```

Expected: branch `首页-revamp` is clean and contains config, motion, painter, Shell, and Golden commits after design commit `e0c96f9`.
