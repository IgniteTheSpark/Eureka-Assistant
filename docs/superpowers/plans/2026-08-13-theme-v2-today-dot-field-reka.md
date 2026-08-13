# Theme V2 Today Dot Field and Draggable Reka Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the passive Today dot experiment with a native Flutter dot field where only dragging Reka deforms nearby dots, release settles naturally, and idle exhalation reveals orange eyes.

**Architecture:** Keep `TodayDotExperimentPage` as the repository and refresh owner. Add a deterministic controller and mutable per-dot simulation under `TodayDotMatrixScene`, then make the existing painter render simulation state without allocating Widgets or rebuilding dot collections every frame. The scene owns ticker lifecycle and gesture arbitration; the page receives a live global Reka anchor for the existing quick-action menu.

**Tech Stack:** Flutter/Dart, `CustomPainter`, `Ticker`, Flutter gesture arena, `flutter_test`, Golden tests. No new package, WebView, React runtime, fragment shader, or external asset.

## Global Constraints

- The feature stays behind `--dart-define=TODAY_DOT_EXPERIMENT=true`; disabled behavior must remain unchanged.
- Light Today experiment only. Do not implement Dark Mode or reuse the dot field on other pages.
- Only a drag starting inside Reka's minimum `64 × 64 logical px` target deforms the field; empty background has no dot interaction.
- Reka starts in the middle-left safe region and remains clear of the Today heading, Dock, system insets, and reserved chrome.
- Idle breathing period is approximately `5.2 s`; eyes are orange, appear only during exhale, and disappear during inhale and drag.
- Drag influence begins near `160 logical px`, is speed-sensitive, uses a smooth falloff, and caps displacement.
- Release uses light bounded inertia, soft edge attraction, and damped dot return. The dropped position persists only while the scene stays mounted.
- Reduce Motion disables breathing, inertia, edge glide, and prolonged spring settling; eyes remain quietly visible and direct drag deformation stays small.
- Preserve the existing three quick actions, pull-to-refresh, recoverable refresh failure, shell navigation, and experiment routing.
- Stop ticker work while Today is inactive or the app is paused. Do not allocate a new dot list or one Widget per dot per frame.

---

## File Structure

- Create `mobile/lib/theme_v2/home/today_dot_field_controller.dart`: high-level Reka state, safe bounds, pointer velocity, breath/eye phase, inertia, and edge attraction.
- Create `mobile/lib/theme_v2/home/today_dot_field_simulation.dart`: mutable dot anchors/positions/velocities, layout rebuild, drag bulge, breathing displacement, and damped return.
- Modify `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`: retain palette/scene geometry, paint controller/simulation state, asymmetric Reka material, and phase-driven eyes.
- Modify `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart`: ticker, lifecycle, drag/tap arbitration, dynamic copy/target placement, and global quick-action anchor.
- Modify `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`: accept the scene-provided live anchor instead of recomputing the old fixed Reka center.
- Create `mobile/test/theme_v2/home/today_dot_field_controller_test.dart`: deterministic state, velocity, bounds, phase, Reduce Motion, and resize tests.
- Create `mobile/test/theme_v2/home/today_dot_field_simulation_test.dart`: locality, speed engagement, displacement cap, return, and list-reuse tests.
- Modify `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart`: eye visibility, local rendering, and repaint contract.
- Modify `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`: semantics, empty-background behavior, tap/drag split, lifecycle, and quick-action anchor behavior.
- Modify `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`: five deterministic visual states and taller viewport coverage.
- Replace/add Golden PNGs under `mobile/test/theme_v2/home/goldens/` for inhale, exhale, drag, settling, Reduce Motion, and tall layout.

---

### Task 1: Deterministic Reka Controller

**Files:**
- Create: `mobile/lib/theme_v2/home/today_dot_field_controller.dart`
- Create: `mobile/test/theme_v2/home/today_dot_field_controller_test.dart`

**Interfaces:**
- Produces: `enum TodayRekaMotionState { idle, dragging, settling }`
- Produces: `class TodayDotFieldController extends ChangeNotifier`
- Produces: `void layout(Size size, {required EdgeInsets reservedInsets})`
- Produces: `void beginDrag(Offset localPosition)`
- Produces: `void updateDrag(Offset localPosition, Duration elapsed)`
- Produces: `void endDrag()` and `void cancelDrag()`
- Produces: `void step(double dtSeconds, {required bool reduceMotion})`
- Produces: getters `rekaCenter`, `safeBounds`, `dragVelocity`, `dragEngagement`, `breathPhase`, `breathAmount`, `eyeOpacity`, `state`, and `isSettled`
- Consumes: Flutter `Size`, `Rect`, `Offset`, `EdgeInsets`, and `ChangeNotifier` only.

- [ ] **Step 1: Write failing controller tests**

Create `mobile/test/theme_v2/home/today_dot_field_controller_test.dart` with deterministic expectations:

```dart
import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodayDotFieldController', () {
    test('starts in the middle-left safe region', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );

      expect(controller.state, TodayRekaMotionState.idle);
      expect(controller.safeBounds.contains(controller.rekaCenter), isTrue);
      expect(controller.rekaCenter.dx, inInclusiveRange(80, 150));
      expect(controller.rekaCenter.dy, inInclusiveRange(300, 470));
    });

    test('drag speed controls engagement and remains capped', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      final start = controller.rekaCenter;

      controller.beginDrag(start);
      controller.updateDrag(start + const Offset(20, 0), const Duration(milliseconds: 40));
      final slow = controller.dragEngagement;
      controller.updateDrag(start + const Offset(180, 0), const Duration(milliseconds: 56));

      expect(slow, greaterThan(0));
      expect(controller.dragEngagement, greaterThan(slow));
      expect(controller.dragEngagement, lessThanOrEqualTo(1));
      expect(controller.rekaCenter, controller.safeBounds.clampPoint(controller.rekaCenter));
    });

    test('exhale reveals eyes while inhale and drag hide them', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );

      controller.debugSetBreathPhase(.25);
      expect(controller.eyeOpacity, 0);
      controller.debugSetBreathPhase(.76);
      expect(controller.eyeOpacity, greaterThan(.75));
      controller.beginDrag(controller.rekaCenter);
      expect(controller.eyeOpacity, 0);
    });

    test('release settles inside bounds and resumes idle', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(const Offset(360, 410), const Duration(milliseconds: 16));
      controller.endDrag();

      for (var i = 0; i < 360 && !controller.isSettled; i++) {
        controller.step(1 / 60, reduceMotion: false);
      }

      expect(controller.state, TodayRekaMotionState.idle);
      expect(controller.safeBounds.contains(controller.rekaCenter), isTrue);
      expect(controller.dragVelocity.distance, lessThan(.5));
    });

    test('reduce motion removes inertia and keeps quiet eyes visible', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(controller.rekaCenter + const Offset(90, 0), const Duration(milliseconds: 16));
      controller.endDrag();
      controller.step(1 / 60, reduceMotion: true);

      expect(controller.state, TodayRekaMotionState.idle);
      expect(controller.dragVelocity, Offset.zero);
      expect(controller.eyeOpacity, closeTo(.42, .01));
    });

    test('resize preserves normalized resting position', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(const Offset(300, 500), const Duration(milliseconds: 40));
      controller.cancelDrag();
      final before = controller.normalizedRekaPosition;

      controller.layout(
        const Size(411, 960),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );

      expect(controller.normalizedRekaPosition.dx, closeTo(before.dx, .02));
      expect(controller.normalizedRekaPosition.dy, closeTo(before.dy, .02));
      expect(controller.safeBounds.contains(controller.rekaCenter), isTrue);
    });
  });
}

extension on Rect {
  Offset clampPoint(Offset value) => Offset(
    value.dx.clamp(left, right),
    value.dy.clamp(top, bottom),
  );
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_field_controller_test.dart
```

Expected: FAIL because `today_dot_field_controller.dart` and its public API do not exist.

- [ ] **Step 3: Implement the controller with deterministic curves**

Create `mobile/lib/theme_v2/home/today_dot_field_controller.dart`. The implementation must use these constants and state rules so later tasks receive stable behavior:

```dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum TodayRekaMotionState { idle, dragging, settling }

class TodayDotFieldController extends ChangeNotifier {
  static const breathPeriodSeconds = 5.2;
  static const rekaVisualRadius = 45.0;
  static const rekaHitRadius = 32.0;
  static const maxDragSpeed = 1800.0;
  static const maxInertiaSpeed = 520.0;
  static const edgeAttractionDistance = 72.0;

  TodayRekaMotionState _state = TodayRekaMotionState.idle;
  Rect _safeBounds = Rect.zero;
  Offset _rekaCenter = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  Offset _lastPointer = Offset.zero;
  Offset _normalizedRekaPosition = const Offset(.24, .46);
  double _breathPhase = 0;
  double _dragEngagement = 0;
  bool _laidOut = false;

  TodayRekaMotionState get state => _state;
  Rect get safeBounds => _safeBounds;
  Offset get rekaCenter => _rekaCenter;
  Offset get dragVelocity => _dragVelocity;
  Offset get normalizedRekaPosition => _normalizedRekaPosition;
  double get breathPhase => _breathPhase;
  double get dragEngagement => _dragEngagement;
  bool get isSettled => _state == TodayRekaMotionState.idle;

  double get breathAmount {
    if (_state != TodayRekaMotionState.idle) return 0;
    final wave = math.sin(_breathPhase * math.pi * 2 - math.pi / 2);
    return (wave + 1) / 2;
  }

  double get eyeOpacity {
    if (_state != TodayRekaMotionState.idle) return 0;
    return eyeOpacityForPhase(_breathPhase);
  }

  static double eyeOpacityForPhase(double phase) {
    final p = phase % 1;
    if (p < .58 || p > .96) return 0;
    final fadeIn = ((p - .58) / .14).clamp(0.0, 1.0);
    final fadeOut = ((.96 - p) / .12).clamp(0.0, 1.0);
    return _smooth(math.min(fadeIn, fadeOut));
  }

  void layout(Size size, {required EdgeInsets reservedInsets}) {
    if (size.isEmpty) return;
    final horizontalMargin = rekaVisualRadius + 12;
    final verticalMargin = rekaVisualRadius + 12;
    final next = Rect.fromLTRB(
      reservedInsets.left + horizontalMargin,
      reservedInsets.top + verticalMargin,
      size.width - reservedInsets.right - horizontalMargin,
      size.height - reservedInsets.bottom - verticalMargin,
    );
    if (!_laidOut) {
      _safeBounds = next;
      _rekaCenter = Offset(
        next.left + next.width * _normalizedRekaPosition.dx,
        next.top + next.height * _normalizedRekaPosition.dy,
      );
      _laidOut = true;
    } else {
      _safeBounds = next;
      _rekaCenter = Offset(
        next.left + next.width * _normalizedRekaPosition.dx,
        next.top + next.height * _normalizedRekaPosition.dy,
      );
    }
    _clampAndNormalize();
    notifyListeners();
  }

  void beginDrag(Offset localPosition) {
    if (!_laidOut) return;
    _state = TodayRekaMotionState.dragging;
    _lastPointer = localPosition;
    _dragVelocity = Offset.zero;
    _dragEngagement = 0;
    notifyListeners();
  }

  void updateDrag(Offset localPosition, Duration elapsed) {
    if (_state != TodayRekaMotionState.dragging) return;
    final seconds = math.max(elapsed.inMicroseconds / Duration.microsecondsPerSecond, 1 / 240);
    final delta = localPosition - _lastPointer;
    final rawVelocity = delta / seconds;
    final speed = rawVelocity.distance;
    _dragVelocity = speed > maxDragSpeed ? rawVelocity / speed * maxDragSpeed : rawVelocity;
    _dragEngagement = (_dragVelocity.distance / 900).clamp(0.0, 1.0);
    _rekaCenter = _clamp(localPosition);
    _lastPointer = localPosition;
    _normalize();
    notifyListeners();
  }

  void endDrag() {
    if (_state != TodayRekaMotionState.dragging) return;
    final speed = _dragVelocity.distance;
    if (speed > maxInertiaSpeed) _dragVelocity = _dragVelocity / speed * maxInertiaSpeed;
    _state = TodayRekaMotionState.settling;
    notifyListeners();
  }

  void cancelDrag() {
    _dragVelocity = Offset.zero;
    _dragEngagement = 0;
    _state = TodayRekaMotionState.idle;
    _clampAndNormalize();
    notifyListeners();
  }

  void step(double dtSeconds, {required bool reduceMotion}) {
    final dt = dtSeconds.clamp(0.0, 1 / 20);
    if (reduceMotion) {
      _dragVelocity = Offset.zero;
      _dragEngagement = 0;
      if (_state != TodayRekaMotionState.dragging) _state = TodayRekaMotionState.idle;
      notifyListeners();
      return;
    }
    if (_state == TodayRekaMotionState.idle) {
      _breathPhase = (_breathPhase + dt / breathPeriodSeconds) % 1;
    } else if (_state == TodayRekaMotionState.settling) {
      _rekaCenter += _dragVelocity * dt;
      _dragVelocity *= math.pow(.12, dt).toDouble();
      _applyEdgeAttraction(dt);
      _clampAndNormalize();
      _dragEngagement += (0 - _dragEngagement) * math.min(1, dt * 8);
      if (_dragVelocity.distance < .5 && _dragEngagement < .005) {
        _dragVelocity = Offset.zero;
        _dragEngagement = 0;
        _state = TodayRekaMotionState.idle;
      }
    }
    notifyListeners();
  }

  void debugSetBreathPhase(double value) {
    assert(value >= 0 && value <= 1);
    _breathPhase = value;
    notifyListeners();
  }

  void _applyEdgeAttraction(double dt) {
    final distances = <(double, Offset)>[
      ((_rekaCenter.dx - _safeBounds.left).abs(), Offset(_safeBounds.left, _rekaCenter.dy)),
      ((_safeBounds.right - _rekaCenter.dx).abs(), Offset(_safeBounds.right, _rekaCenter.dy)),
      ((_rekaCenter.dy - _safeBounds.top).abs(), Offset(_rekaCenter.dx, _safeBounds.top)),
      ((_safeBounds.bottom - _rekaCenter.dy).abs(), Offset(_rekaCenter.dx, _safeBounds.bottom)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final nearest = distances.first;
    if (nearest.$1 >= edgeAttractionDistance) return;
    final strength = math.pow(1 - nearest.$1 / edgeAttractionDistance, 2).toDouble();
    _rekaCenter += (nearest.$2 - _rekaCenter) * math.min(1, dt * 2.2 * strength);
  }

  Offset _clamp(Offset value) => Offset(
    value.dx.clamp(_safeBounds.left, _safeBounds.right),
    value.dy.clamp(_safeBounds.top, _safeBounds.bottom),
  );

  void _clampAndNormalize() {
    _rekaCenter = _clamp(_rekaCenter);
    _normalize();
  }

  void _normalize() {
    _normalizedRekaPosition = Offset(
      (_rekaCenter.dx - _safeBounds.left) / _safeBounds.width,
      (_rekaCenter.dy - _safeBounds.top) / _safeBounds.height,
    );
  }

  static double _smooth(double value) => value * value * (3 - 2 * value);
}
```

If the project Dart SDK rejects records, replace the four record entries in `_applyEdgeAttraction` with a private `_EdgeCandidate` class in the same file without changing behavior.

- [ ] **Step 4: Run controller tests and format**

Run:

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_field_controller.dart test/theme_v2/home/today_dot_field_controller_test.dart
flutter test test/theme_v2/home/today_dot_field_controller_test.dart
```

Expected: formatting succeeds and all six controller tests PASS.

- [ ] **Step 5: Commit the controller increment**

```bash
git add mobile/lib/theme_v2/home/today_dot_field_controller.dart mobile/test/theme_v2/home/today_dot_field_controller_test.dart
git commit -m "feat: model draggable today reka state"
```

---

### Task 2: Per-Dot Simulation

**Files:**
- Create: `mobile/lib/theme_v2/home/today_dot_field_simulation.dart`
- Create: `mobile/test/theme_v2/home/today_dot_field_simulation_test.dart`

**Interfaces:**
- Consumes: controller getters `rekaCenter`, `dragEngagement`, `breathAmount`, `state`, and `dragVelocity`.
- Produces: mutable `TodayDotNode` with `anchor`, `position`, and `velocity`.
- Produces: `TodayDotFieldSimulation({double interval = 8})`.
- Produces: `void layout(Size size)` that reuses nodes when size/interval are unchanged.
- Produces: `void step(double dtSeconds, {required Offset rekaCenter, required TodayRekaMotionState state, required double dragEngagement, required double breathAmount, required bool reduceMotion})`.
- Produces: getters `nodes`, `interval`, `isAtRest`, and `layoutRevision`.

- [ ] **Step 1: Write failing simulation tests**

Create `mobile/test/theme_v2/home/today_dot_field_simulation_test.dart`:

```dart
import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:eureka/theme_v2/home/today_dot_field_simulation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout builds an 8 px anchored field and reuses it for stable size', () {
    final simulation = TodayDotFieldSimulation();
    simulation.layout(const Size(411, 860));
    final firstNodes = simulation.nodes;
    final firstRevision = simulation.layoutRevision;

    simulation.layout(const Size(411, 860));

    expect(simulation.interval, 8);
    expect(simulation.nodes, same(firstNodes));
    expect(simulation.layoutRevision, firstRevision);
    expect(simulation.nodes, isNotEmpty);
  });

  test('drag deformation is local, speed-sensitive, and capped', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    const center = Offset(120, 420);
    final near = simulation.nodes.reduce(
      (a, b) => (a.anchor - center).distance < (b.anchor - center).distance ? a : b,
    );
    final far = simulation.nodes.reduce(
      (a, b) => (a.anchor - center).distance > (b.anchor - center).distance ? a : b,
    );

    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: .25,
      breathAmount: 0,
      reduceMotion: false,
    );
    final slow = (near.position - near.anchor).distance;
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: 1,
      breathAmount: 0,
      reduceMotion: false,
    );

    expect((near.position - near.anchor).distance, greaterThan(slow));
    expect((near.position - near.anchor).distance, lessThanOrEqualTo(18));
    expect((far.position - far.anchor).distance, lessThan(.01));
  });

  test('idle breathing affects only the local field', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    const center = Offset(120, 420);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.idle,
      dragEngagement: 0,
      breathAmount: 1,
      reduceMotion: false,
    );

    expect(
      simulation.nodes.any((node) =>
        (node.anchor - center).distance < 120 &&
        (node.position - node.anchor).distance > .05),
      isTrue,
    );
    expect(
      simulation.nodes.where((node) => (node.anchor - center).distance > 170)
          .every((node) => (node.position - node.anchor).distance < .01),
      isTrue,
    );
  });

  test('settling returns all dots to anchors without rebuilding nodes', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    final nodes = simulation.nodes;
    const center = Offset(120, 420);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: 1,
      breathAmount: 0,
      reduceMotion: false,
    );

    for (var i = 0; i < 360 && !simulation.isAtRest; i++) {
      simulation.step(
        1 / 60,
        rekaCenter: center,
        state: TodayRekaMotionState.settling,
        dragEngagement: 0,
        breathAmount: 0,
        reduceMotion: false,
      );
    }

    expect(simulation.nodes, same(nodes));
    expect(simulation.isAtRest, isTrue);
    expect(simulation.nodes.every((node) => (node.position - node.anchor).distance < .05), isTrue);
  });

  test('reduce motion uses a small immediate displacement and no spring tail', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    const center = Offset(120, 420);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: 1,
      breathAmount: 0,
      reduceMotion: true,
    );
    final maxOffset = simulation.nodes
        .map((node) => (node.position - node.anchor).distance)
        .reduce((a, b) => a > b ? a : b);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.idle,
      dragEngagement: 0,
      breathAmount: 0,
      reduceMotion: true,
    );

    expect(maxOffset, lessThanOrEqualTo(4));
    expect(simulation.isAtRest, isTrue);
  });
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_field_simulation_test.dart
```

Expected: FAIL because `TodayDotFieldSimulation` does not exist.

- [ ] **Step 3: Implement mutable dot state and deterministic stepping**

Create `mobile/lib/theme_v2/home/today_dot_field_simulation.dart` with this structure and formulas:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'today_dot_field_controller.dart';

class TodayDotNode {
  TodayDotNode(this.anchor)
      : position = anchor,
        velocity = Offset.zero;

  final Offset anchor;
  Offset position;
  Offset velocity;
}

class TodayDotFieldSimulation {
  TodayDotFieldSimulation({this.interval = 8});

  static const dragRadius = 160.0;
  static const breathRadius = 120.0;
  static const maxDisplacement = 18.0;
  static const reducedMotionDisplacement = 4.0;

  final double interval;
  List<TodayDotNode> _nodes = <TodayDotNode>[];
  Size _size = Size.zero;
  int _layoutRevision = 0;

  List<TodayDotNode> get nodes => _nodes;
  int get layoutRevision => _layoutRevision;
  bool get isAtRest => _nodes.every(
    (node) =>
        (node.position - node.anchor).distance < .05 &&
        node.velocity.distance < .05,
  );

  void layout(Size size) {
    if (size == _size || size.isEmpty) return;
    _size = size;
    final half = interval / 2;
    final nodes = <TodayDotNode>[];
    for (var y = half; y < size.height; y += interval) {
      for (var x = half; x < size.width; x += interval) {
        nodes.add(TodayDotNode(Offset(x, y)));
      }
    }
    _nodes = nodes;
    _layoutRevision++;
  }

  void step(
    double dtSeconds, {
    required Offset rekaCenter,
    required TodayRekaMotionState state,
    required double dragEngagement,
    required double breathAmount,
    required bool reduceMotion,
  }) {
    final dt = dtSeconds.clamp(0.0, 1 / 20);
    for (final node in _nodes) {
      final delta = node.anchor - rekaCenter;
      final distance = delta.distance;
      final direction = distance == 0 ? const Offset(1, 0) : delta / distance;
      var target = node.anchor;

      if (state == TodayRekaMotionState.dragging && distance < dragRadius) {
        final falloff = _smooth(1 - distance / dragRadius);
        final cap = reduceMotion ? reducedMotionDisplacement : maxDisplacement;
        target += direction * (falloff * cap * dragEngagement);
      } else if (!reduceMotion && state == TodayRekaMotionState.idle && distance < breathRadius) {
        final falloff = _smooth(1 - distance / breathRadius);
        final angle = math.atan2(delta.dy, delta.dx);
        final asymmetric = 1 + .08 * math.sin(angle * 3 + .6) + .05 * math.sin(angle * 5 - .8);
        target += direction * (falloff * 5.5 * breathAmount * asymmetric);
      }

      if (reduceMotion) {
        node.position = target;
        node.velocity = Offset.zero;
        continue;
      }

      final spring = state == TodayRekaMotionState.dragging ? 42.0 : 28.0;
      final damping = state == TodayRekaMotionState.dragging ? 14.0 : 11.0;
      final acceleration = (target - node.position) * spring - node.velocity * damping;
      node.velocity += acceleration * dt;
      node.position += node.velocity * dt;

      final offset = node.position - node.anchor;
      if (offset.distance > maxDisplacement) {
        node.position = node.anchor + offset / offset.distance * maxDisplacement;
        node.velocity *= .5;
      }
      if ((node.position - node.anchor).distance < .025 && node.velocity.distance < .025) {
        node.position = node.anchor;
        node.velocity = Offset.zero;
      }
    }
  }

  static double _smooth(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}
```

- [ ] **Step 4: Format and run controller plus simulation tests**

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_field_simulation.dart test/theme_v2/home/today_dot_field_simulation_test.dart
flutter test test/theme_v2/home/today_dot_field_controller_test.dart test/theme_v2/home/today_dot_field_simulation_test.dart
```

Expected: all controller and simulation tests PASS.

- [ ] **Step 5: Commit the simulation increment**

```bash
git add mobile/lib/theme_v2/home/today_dot_field_simulation.dart mobile/test/theme_v2/home/today_dot_field_simulation_test.dart
git commit -m "feat: simulate today reka dot field"
```

---

### Task 3: Render Dot Field, Organic Reka, and Exhale Eyes

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart:33-132`
- Modify: `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart:7-75`

**Interfaces:**
- Consumes: `TodayDotFieldSimulation.nodes` and `TodayDotFieldController` state getters.
- Changes `TodayDotMatrixPainter` constructor to require `simulation`, `rekaCenter`, `rekaState`, `breathAmount`, `eyeOpacity`, `refreshEmphasis`, `reduceMotion`, and `devicePixelRatio`.
- Produces: `static double rekaMaterialFalloff(Offset point, Offset center)` for deterministic paint tests.
- Keeps: `TodayDotMatrixPalette.light`, physical-pixel snapping, top refresh-opacity band, and one canvas painter.

- [ ] **Step 1: Replace painter tests with state-based failing tests**

Update `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart` so it constructs a simulation, advances explicit states, and verifies:

```dart
test('reference geometry starts Reka in the middle-left region', () {
  final geometry = TodayDotSceneGeometry.forSize(const Size(411, 860));
  expect(geometry.gridInterval, 8);
  expect(geometry.initialRekaCenter.dx, inInclusiveRange(80, 150));
  expect(geometry.initialRekaCenter.dy, inInclusiveRange(300, 470));
});

test('eyes change only the local eye region during exhale', () async {
  final inhale = await _paintState(eyeOpacity: 0, breathAmount: .7);
  final exhale = await _paintState(eyeOpacity: 1, breathAmount: .2);

  expect(
    await _regionBytes(inhale, const Rect.fromLTWH(300, 200, 20, 20)),
    await _regionBytes(exhale, const Rect.fromLTWH(300, 200, 20, 20)),
  );
  expect(
    await _regionBytes(inhale, const Rect.fromLTWH(88, 380, 64, 32)),
    isNot(await _regionBytes(exhale, const Rect.fromLTWH(88, 380, 64, 32))),
  );
});

test('same simulation revision and visual inputs do not repaint', () {
  final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
  final first = TodayDotMatrixPainter(
    simulation: simulation,
    rekaCenter: const Offset(120, 400),
    rekaState: TodayRekaMotionState.idle,
    breathAmount: 0,
    eyeOpacity: 0,
    refreshEmphasis: 0,
    reduceMotion: false,
    devicePixelRatio: 1,
  );
  final same = TodayDotMatrixPainter(
    simulation: simulation,
    rekaCenter: const Offset(120, 400),
    rekaState: TodayRekaMotionState.idle,
    breathAmount: 0,
    eyeOpacity: 0,
    refreshEmphasis: 0,
    reduceMotion: false,
    devicePixelRatio: 1,
  );
  expect(same.shouldRepaint(first), isFalse);
});
```

Update `_paintState` to build and step `TodayDotFieldSimulation` at `Size(411, 860)`, use center `Offset(120, 400)`, and pass explicit state values to the painter. Keep `_regionBytes` unchanged.

- [ ] **Step 2: Run painter tests and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: FAIL because the painter still accepts `rekaPhase` and paints permanently visible eyes.

- [ ] **Step 3: Refactor geometry and painter**

In `today_dot_matrix_painter.dart`:

1. Rename the geometry field from `rekaCenter` to `initialRekaCenter` and calculate it from safe scene proportions:

```dart
factory TodayDotSceneGeometry.forSize(Size size) => TodayDotSceneGeometry(
  size: size,
  initialRekaCenter: Offset(size.width * .29, size.height * .46),
  rekaInfluenceRadius: 120,
);
```

2. Import the controller and simulation files.

3. Replace the painter fields with:

```dart
final TodayDotFieldSimulation simulation;
final Offset rekaCenter;
final TodayRekaMotionState rekaState;
final double breathAmount;
final double eyeOpacity;
final double refreshEmphasis;
final bool reduceMotion;
final double devicePixelRatio;
final TodayDotMatrixPalette palette;
```

4. Paint `simulation.nodes` instead of regenerating nested `x/y` loops. Derive local Reka material independently of motion so the body remains readable at rest:

```dart
for (final node in simulation.nodes) {
  final falloff = rekaMaterialFalloff(node.anchor, rekaCenter);
  final refreshFalloff = (1 - node.anchor.dy / 96).clamp(0.0, 1.0);
  final center = Offset(_snap(node.position.dx), _snap(node.position.dy));
  final radius = .9 + falloff * (1.25 + breathAmount * .2);
  final baseColor = Color.lerp(palette.dot, palette.rekaDot, falloff)!;
  final refreshAlpha = refreshEmphasis.clamp(0.0, 1.0) * refreshFalloff * .24;
  dotPaint.color = baseColor.withValues(
    alpha: (baseColor.a + refreshAlpha).clamp(0.0, 1.0),
  );
  canvas.drawCircle(center, radius, dotPaint);
}
```

5. Use an asymmetric soft-core falloff:

```dart
static double rekaMaterialFalloff(Offset point, Offset center) {
  final delta = point - center;
  final angle = math.atan2(delta.dy, delta.dx);
  final organicRadius = 45 *
      (1 + .08 * math.sin(angle * 3 + .6) + .05 * math.sin(angle * 5 - .8));
  final normalized = (1 - delta.distance / organicRadius).clamp(0.0, 1.0);
  return normalized * normalized * (3 - 2 * normalized);
}
```

6. Paint eyes only when `eyeOpacity > .001`, multiplying `palette.eye.a` by `eyeOpacity`. Keep the two three-dot eye clusters centered at `rekaCenter + Offset(±15, 0)`.

7. Include every new visual input and `simulation.layoutRevision` in `shouldRepaint`. Do not compare individual node lists.

- [ ] **Step 4: Format and run model/painter tests**

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_matrix_painter.dart test/theme_v2/home/today_dot_matrix_painter_test.dart
flutter test test/theme_v2/home/today_dot_field_controller_test.dart test/theme_v2/home/today_dot_field_simulation_test.dart test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: all focused tests PASS.

- [ ] **Step 5: Commit the render increment**

```bash
git add mobile/lib/theme_v2/home/today_dot_matrix_painter.dart mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart
git commit -m "feat: render breathing reka dot field"
```

---

### Task 4: Scene Ticker, Drag/Tap Arbitration, Lifecycle, and Live Menu Anchor

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart:1-175`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart:132-205`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart:12-234`

**Interfaces:**
- Consumes: controller and simulation public APIs from Tasks 1-2.
- Changes `TodayDotMatrixScene.onRekaTap` from `VoidCallback` to `ValueChanged<Rect>` where the `Rect` is global screen coordinates.
- Produces: `static const rekaTargetKey = ValueKey<String>('today-reka-drag-target')` for gesture tests.
- Produces: optional constructor injections `TodayDotFieldController? controller` and `TodayDotFieldSimulation? simulation` for deterministic tests/Goldens; scene owns and disposes defaults only.
- Changes `_openQuickActions()` to `_openQuickActions(Rect anchor)` in `TodayDotExperimentPage`.

- [ ] **Step 1: Add failing gesture and lifecycle widget tests**

Extend `today_dot_experiment_page_test.dart` with these cases:

```dart
testWidgets('Reka semantics describe tap and drag with a 64 px target', (tester) async {
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(
    _Host(child: TodayDotMatrixScene(refreshEmphasis: 0, onRekaTap: (_) {})),
  );
  final reka = find.bySemanticsLabel('Reka 快捷操作，可拖动');
  expect(reka, findsOneWidget);
  expect(tester.getSize(reka).width, greaterThanOrEqualTo(64));
  expect(tester.getSize(reka).height, greaterThanOrEqualTo(64));
  semantics.dispose();
});

testWidgets('empty background drag does not move Reka', (tester) async {
  final controller = TodayDotFieldController();
  await tester.pumpWidget(
    _Host(
      disableAnimations: false,
      child: TodayDotMatrixScene(
        controller: controller,
        refreshEmphasis: 0,
        onRekaTap: (_) {},
      ),
    ),
  );
  final before = controller.rekaCenter;
  await tester.dragFrom(const Offset(330, 260), const Offset(-90, 80));
  await tester.pump();
  expect(controller.rekaCenter, before);
});

testWidgets('dragging Reka moves it without opening quick actions', (tester) async {
  final controller = TodayDotFieldController();
  var taps = 0;
  await tester.pumpWidget(
    _Host(
      disableAnimations: false,
      child: TodayDotMatrixScene(
        controller: controller,
        refreshEmphasis: 0,
        onRekaTap: (_) => taps++,
      ),
    ),
  );
  final before = controller.rekaCenter;
  await tester.drag(find.byKey(TodayDotMatrixScene.rekaTargetKey), const Offset(100, -30));
  await tester.pump(const Duration(milliseconds: 32));
  expect(controller.rekaCenter.dx, greaterThan(before.dx + 50));
  expect(taps, 0);
});

testWidgets('tap reports the current global Reka anchor', (tester) async {
  Rect? anchor;
  await tester.pumpWidget(
    _Host(child: TodayDotMatrixScene(refreshEmphasis: 0, onRekaTap: (value) => anchor = value)),
  );
  final target = find.byKey(TodayDotMatrixScene.rekaTargetKey);
  await tester.tap(target);
  await tester.pump();
  expect(anchor, isNotNull);
  expect(anchor!.center, tester.getCenter(target));
  expect(anchor!.size, const Size.square(64));
});

testWidgets('inactive scene stops phase and cancels drag', (tester) async {
  final controller = TodayDotFieldController();
  Widget build(bool active) => _Host(
    disableAnimations: false,
    child: TodayDotMatrixScene(
      active: active,
      controller: controller,
      refreshEmphasis: 0,
      onRekaTap: (_) {},
    ),
  );
  await tester.pumpWidget(build(true));
  await tester.startGesture(tester.getCenter(find.byKey(TodayDotMatrixScene.rekaTargetKey)));
  await tester.pumpWidget(build(false));
  final phase = controller.breathPhase;
  await tester.pump(const Duration(seconds: 1));
  expect(controller.state, TodayRekaMotionState.idle);
  expect(controller.breathPhase, phase);
});
```

Update all existing `onRekaTap: () {}` calls to `onRekaTap: (_) {}` and the semantics label expectation to `Reka 快捷操作，可拖动`.

- [ ] **Step 2: Run widget tests and verify RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: FAIL because the scene has no controller injection, drag target key, dynamic anchor, or drag state.

- [ ] **Step 3: Replace the breathing AnimationController with a scene ticker**

Refactor `_TodayDotMatrixSceneState` to mix in `SingleTickerProviderStateMixin, WidgetsBindingObserver` and own:

```dart
late final TodayDotFieldController _controller =
    widget.controller ?? TodayDotFieldController();
late final TodayDotFieldSimulation _simulation =
    widget.simulation ?? TodayDotFieldSimulation();
late final Ticker _ticker = createTicker(_onTick);
Duration _lastElapsed = Duration.zero;
Duration? _lastDragTimestamp;
bool? _reduceMotion;
```

Implement `_onTick` with capped delta and no list rebuild:

```dart
void _onTick(Duration elapsed) {
  final micros = elapsed.inMicroseconds - _lastElapsed.inMicroseconds;
  _lastElapsed = elapsed;
  final dt = (micros / Duration.microsecondsPerSecond).clamp(0.0, 1 / 20);
  _controller.step(dt, reduceMotion: _reduceMotion ?? true);
  _simulation.step(
    dt,
    rekaCenter: _controller.rekaCenter,
    state: _controller.state,
    dragEngagement: _controller.dragEngagement,
    breathAmount: _controller.breathAmount,
    reduceMotion: _reduceMotion ?? true,
  );
  setState(() {});
}
```

In `LayoutBuilder`, call controller layout only when size changes, with `EdgeInsets.fromLTRB(18, 88, 18, 118)`, then call `simulation.layout(size)`. Use controller state to construct the painter.

Start the ticker only when `widget.active` and `AppLifecycleState` is resumed. On inactive, paused, hidden, or detached: stop the ticker, reset `_lastElapsed`, and call `controller.cancelDrag()`.

Dispose `Ticker` and `WidgetsBindingObserver`; dispose controller only when `widget.controller == null`.

- [ ] **Step 4: Add gesture arbitration and dynamic positioning**

Position the semantic target from `_controller.rekaCenter`, using a keyed `GestureDetector`:

```dart
Positioned(
  left: _controller.rekaCenter.dx - 32,
  top: _controller.rekaCenter.dy - 32,
  child: Semantics(
    label: 'Reka 快捷操作，可拖动',
    button: true,
    expanded: widget.menuExpanded,
    child: GestureDetector(
      key: TodayDotMatrixScene.rekaTargetKey,
      behavior: HitTestBehavior.opaque,
      onTap: _reportTapAnchor,
      onPanStart: (details) {
        _lastDragTimestamp = details.sourceTimeStamp;
        _controller.beginDrag(_controller.rekaCenter);
      },
      onPanUpdate: (details) {
        final timestamp = details.sourceTimeStamp;
        final elapsed = timestamp != null && _lastDragTimestamp != null
            ? timestamp - _lastDragTimestamp!
            : const Duration(milliseconds: 16);
        _lastDragTimestamp = timestamp;
        final box = _sceneKey.currentContext?.findRenderObject();
        if (box is RenderBox) {
          _controller.updateDrag(box.globalToLocal(details.globalPosition), elapsed);
        }
      },
      onPanEnd: (_) {
        _lastDragTimestamp = null;
        _controller.endDrag();
      },
      onPanCancel: () {
        _lastDragTimestamp = null;
        _controller.cancelDrag();
      },
      child: const SizedBox.square(dimension: 64),
    ),
  ),
)
```

Flutter's pan recognizer supplies the movement threshold that separates tap from drag. A successful pan wins the gesture arena and suppresses `onTap`; movement below the pan threshold remains a tap. Use `DragUpdateDetails.sourceTimeStamp` deltas when available and fall back to `16 ms` so velocity remains physical.

Implement `_reportTapAnchor` from the target's own `RenderBox`:

```dart
void _reportTapAnchor() {
  final context = _rekaTargetKey.currentContext;
  final box = context?.findRenderObject();
  if (box is! RenderBox) return;
  widget.onRekaTap(box.localToGlobal(Offset.zero) & box.size);
}
```

Use a private `GlobalKey _rekaTargetKey` for geometry while keeping the public `ValueKey` on a nested keyed box for tests. Move the authored copy relative to the live center and clamp it inside the scene.

- [ ] **Step 5: Update page quick-action anchoring**

In `today_dot_experiment_page.dart`, replace fixed geometry lookup:

```dart
Future<void> _openQuickActions(Rect anchor) async {
  setState(() => _menuExpanded = true);
  try {
    await showTodayRekaQuickActions(
      context,
      anchor: anchor,
      onCreateAsset: widget.onCreateAsset,
      onCreateReport: widget.onCreateReport,
      onStartChat: widget.onStartChat,
    );
  } finally {
    if (mounted) setState(() => _menuExpanded = false);
  }
}
```

Pass `onRekaTap: (anchor) => unawaited(_openQuickActions(anchor))` to the scene and remove `_sceneKey` if it has no remaining use.

- [ ] **Step 6: Format and run focused widget tests**

```bash
cd mobile
dart format lib/theme_v2/home/today_dot_matrix_scene.dart lib/theme_v2/home/today_dot_experiment_page.dart test/theme_v2/home/today_dot_experiment_page_test.dart
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: all page and gesture tests PASS with no pending ticker exception.

- [ ] **Step 7: Run all Today dot tests and analyze changed Dart files**

```bash
cd mobile
flutter test \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart
flutter analyze \
  lib/theme_v2/home/today_dot_field_controller.dart \
  lib/theme_v2/home/today_dot_field_simulation.dart \
  lib/theme_v2/home/today_dot_matrix_painter.dart \
  lib/theme_v2/home/today_dot_matrix_scene.dart \
  lib/theme_v2/home/today_dot_experiment_page.dart \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: tests PASS and analyzer reports `No issues found!`.

- [ ] **Step 8: Commit interaction integration**

```bash
git add \
  mobile/lib/theme_v2/home/today_dot_matrix_scene.dart \
  mobile/lib/theme_v2/home/today_dot_experiment_page.dart \
  mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat: make today reka draggable"
```

---

### Task 5: Deterministic Goldens, Regression, and Real-Device Handoff

**Files:**
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Replace: `mobile/test/theme_v2/home/goldens/today-dot-empty-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-inhale-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-exhale-eyes-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-drag-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-settling-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-reduce-motion-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-idle-411-tall-light.png`
- Verify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Verify: `mobile/test/theme_v2/theme_v2_rollout_test.dart`

**Interfaces:**
- Consumes: controller `debugSetBreathPhase`, scene controller/simulation injection, and experiment flag seam.
- Produces: deterministic `pumpGolden` helper with explicit phase, drag state, Reduce Motion state, and viewport size.
- Produces: evidence that opt-out shell behavior and experiment routing still pass.

- [ ] **Step 1: Expand Golden coverage with deterministic state injection**

Refactor the Golden test into a parameterized helper:

```dart
Future<void> pumpGolden(
  WidgetTester tester, {
  required String name,
  required double phase,
  required bool reduceMotion,
  required Size size,
  Offset? dragTo,
  bool settling = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final controller = TodayDotFieldController();
  final simulation = TodayDotFieldSimulation();
  controller.layout(
    Size(size.width, size.height - 100),
    reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
  );
  controller.debugSetBreathPhase(phase);
  if (dragTo != null) {
    controller.beginDrag(controller.rekaCenter);
    controller.updateDrag(dragTo, const Duration(milliseconds: 24));
    if (settling) controller.endDrag();
  }

  await tester.pumpWidget(
    _GoldenHost(
      size: size,
      disableAnimations: reduceMotion,
      child: RepaintBoundary(
        key: surface,
        child: ThemeV2PageScaffold(
          topNav: const ThemeV2GlobalTopNav(
            deviceStatus: DeviceStatusSummary.disconnected(),
            onDeviceSelected: _noopDeviceTarget,
            onNotificationsPressed: _noop,
          ),
          dock: const ThemeV2FloatingDock(
            selectedIndex: 0,
            onDestinationSelected: _noopIndex,
          ),
          body: TodayDotExperimentPage(
            now: DateTime(2026, 7, 31),
            sceneControllerOverride: controller,
            sceneSimulationOverride: simulation,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await expectLater(find.byKey(surface), matchesGoldenFile('goldens/$name.png'));
}
```

Add optional `sceneControllerOverride` and `sceneSimulationOverride` parameters to `TodayDotExperimentPage` only if needed to pass deterministic state to the scene; keep them nullable and test-only by convention. Do not expose them through `ThemeV2AppShell`.

Create six named `testWidgets` calls for:

```text
today-dot-inhale-411-light       phase .25, no drag
today-dot-exhale-eyes-411-light phase .76, no drag
today-dot-drag-411-light         dragTo Offset(270, 360), active drag
today-dot-settling-411-light     same drag then endDrag
today-dot-reduce-motion-411-light phase .76, Reduce Motion true
today-dot-idle-411-tall-light    phase .76, Size(411, 1060)
```

Keep `today-dot-empty-411-light.png` only as a compatibility alias if another test references it; otherwise replace it with the inhale baseline and update the filename reference.

- [ ] **Step 2: Run Golden tests without updating and verify expected mismatch**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: FAIL because new Golden files are missing and the old baseline reflects the passive scene.

- [ ] **Step 3: Generate Goldens and visually inspect every PNG**

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: PASS and all six PNG files are written. Open each PNG and verify:

- initial Reka is middle-left and clear of title/Dock;
- inhale has hidden eyes;
- exhale has only orange eyes as expression;
- drag deformation is local and does not tear the grid;
- settling remains controlled;
- Reduce Motion is calm and identifiable;
- tall layout preserves density and safe placement.

If a visual check fails, tune constants in controller/simulation/painter, rerun focused tests, regenerate Goldens, and inspect again before continuing.

- [ ] **Step 4: Run the complete regression set**

```bash
cd mobile
flutter test \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/theme_v2_rollout_test.dart
flutter analyze \
  lib/theme_v2/home/today_dot_field_controller.dart \
  lib/theme_v2/home/today_dot_field_simulation.dart \
  lib/theme_v2/home/today_dot_matrix_painter.dart \
  lib/theme_v2/home/today_dot_matrix_scene.dart \
  lib/theme_v2/home/today_dot_experiment_page.dart \
  test/theme_v2/home/today_dot_field_controller_test.dart \
  test/theme_v2/home/today_dot_field_simulation_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: all tests PASS and analyzer reports `No issues found!`.

- [ ] **Step 5: Commit Goldens and verification coverage**

```bash
git add \
  mobile/lib/theme_v2/home/today_dot_experiment_page.dart \
  mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart \
  mobile/test/theme_v2/home/goldens/
git commit -m "test: lock draggable reka dot field states"
```

- [ ] **Step 6: Build the experiment APK for the connected Android device**

```bash
cd mobile
flutter devices
flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true
```

Expected: the target Android device is listed and `build/app/outputs/flutter-apk/app-debug.apk` is produced successfully.

- [ ] **Step 7: Install and launch on the target device**

```bash
cd mobile
flutter run -d RFCY71B21YK --debug --dart-define=TODAY_DOT_EXPERIMENT=true
```

Expected: the app launches on the physical device with the revised Today experiment enabled.

- [ ] **Step 8: Complete the physical-device acceptance loop**

Verify on device, in order:

1. Reka begins middle-left and breathes without a visible loop seam.
2. Eyes are absent during inhale and fade in during exhale; no mouth appears.
3. Drag starts only on Reka; swiping empty background does not deform dots.
4. Slow and fast drags produce visibly different, capped local deformation.
5. Release has light inertia, soft edge attraction, and no jitter or uncontrolled bounce.
6. Dots return cleanly to anchors and breathing resumes.
7. A tap opens exactly Create Asset, Create Report, and Start New Chat.
8. Pull-to-refresh and Retry still work after repeated drags.
9. Navigating away stops animation; returning resumes without a position jump.
10. Five minutes of repeated drag/breathe cycles show no visible frame degradation or memory instability.

Record at least one screenshot at inhale, one at exhale, and one after a dragged resting position for user review. Do not expand to Dark Mode or other pages during this task.

- [ ] **Step 9: Check final branch state**

```bash
git status --short --branch
git log --oneline --decorate -8
```

Expected: branch `首页-revamp` is clean and contains the controller, simulation, painter, interaction, and Golden commits after design commit `4a9af39`.
