# Today Dithered 3D Reka and Floating Top Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the active Today dot-field experiment with a draggable, locally hosted, dithered 3D Reka robot head on the standard Today background while keeping the approved floating Top Dock.

**Architecture:** Flutter owns Today layout, Reka position, gesture arbitration, safe bounds, quick-action anchoring, lifecycle, and Reduce Motion. A small transparent local WebView owns procedural Three.js geometry, studio lighting, Bayer post-processing, permanent non-dithered eye meshes, and internal idle motion. The WebView never receives pointer input and falls back to a deterministic Flutter painter if WebGL cannot initialize.

**Tech Stack:** Flutter/Dart, `webview_flutter`, local HTML/JavaScript assets, Three.js r185, WebGL2/GLSL3, Flutter widget/unit/golden tests, Android physical-device verification.

## Global Constraints

- Today uses its standard Theme V2 background; no full-page dot matrix, ripple, bulge, glow, or background pointer response remains active.
- Reka appears on Today only.
- Reka is a floating robot head with a rounded shell, inset dark visor, side modules, and no torso, legs, antenna, mouth, outline halo, or circular container.
- Both orange `3 × 3` eyes remain visible in idle, dragging, settling, Reduce Motion, and fallback states.
- Drag moves Reka across the page; it never orbits or freely rotates the camera.
- Velocity-driven head tilt is clamped to `8°`.
- The local render region is `216 × 216` logical pixels and caps DPR at `2`.
- Initial dither settings are Bayer, `4 CSS px` grid, pixel ratio `1`, grayscale on, invert off, and transparent background.
- Runtime renderer loading is fully local; no model, decoder, texture, script, font, or configuration fetch is allowed.
- The minimum loop remains behind the existing `TODAY_DOT_EXPERIMENT` compile-time flag for this round.
- Dark Mode, other-page changes, new expressions, and restart persistence are excluded.

## File Structure

### New production files

- `mobile/lib/theme_v2/home/today_dithered_reka_config.dart` — typed visual and motion constants shared by Flutter and the HTML bootstrap.
- `mobile/lib/theme_v2/home/today_reka_motion_controller.dart` — Reka position, safe bounds, velocity, tilt, and motion state.
- `mobile/lib/theme_v2/home/today_reka_scene.dart` — Today heading, Reka positioning, gesture target, lifecycle ticker, and quick-action anchor reporting.
- `mobile/lib/theme_v2/home/today_dithered_reka.dart` — local asset loading, WebView bridge, renderer status, pose synchronization, and fallback switching.
- `mobile/lib/theme_v2/home/today_reka_fallback_painter.dart` — deterministic static robot-head fallback.
- `mobile/assets/reka_dither/three.module.min.js` — pinned Three.js r185 browser module.
- `mobile/assets/reka_dither/THREE-LICENSE` — upstream Three.js license.
- `mobile/assets/reka_dither/reka_dither_engine.js` — procedural head scene, Bayer shader, eye pass, animation loop, and lifecycle API.
- `mobile/assets/reka_dither/reka_dither.html` — inline module bootstrap and `RekaHost` messaging.

### Modified production files

- `mobile/pubspec.yaml` — register `assets/reka_dither/`.
- `mobile/lib/config.dart` — clarify that the legacy flag name now gates the Today Reka visual experiment.
- `mobile/lib/theme_v2/home/today_dot_experiment_page.dart` — retain the feature-flag entry point but compose `TodayRekaScene` on the standard Theme V2 background.
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart` — preserve floating Top Dock behavior while removing dot-specific naming from local variables where safe.

### Removed production files

- `mobile/lib/theme_v2/home/today_dot_field_config.dart`
- `mobile/lib/theme_v2/home/today_dot_field_controller.dart`
- `mobile/lib/theme_v2/home/today_dot_field_simulation.dart`
- `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`
- `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart`

### New and modified tests

- Create `mobile/test/theme_v2/home/today_reka_motion_controller_test.dart`.
- Create `mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart`.
- Create `mobile/test/theme_v2/home/today_dithered_reka_test.dart`.
- Create `mobile/test/theme_v2/home/today_reka_scene_test.dart`.
- Modify `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart` for refresh and page-level behavior using an injected renderer surface.
- Rewrite `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart` around the standard background, floating Top Dock, and deterministic fallback Reka.
- Remove dot-field config, simulation, and painter tests and their obsolete golden PNGs.

---

### Task 1: Replace dot-field configuration and motion state with Reka-only types

**Files:**
- Create: `mobile/lib/theme_v2/home/today_dithered_reka_config.dart`
- Create: `mobile/lib/theme_v2/home/today_reka_motion_controller.dart`
- Create: `mobile/test/theme_v2/home/today_reka_motion_controller_test.dart`
- Reference: `mobile/lib/theme_v2/home/today_dot_field_controller.dart`

**Interfaces:**
- Produces: `TodayDitheredRekaConfig`, `TodayRekaMotionState`, `TodayRekaPose`, and `TodayRekaMotionController`.
- `TodayRekaMotionController.layout(Size, {required EdgeInsets reservedInsets})` computes safe center bounds using half the `216` render extent.
- `TodayRekaMotionController.pose` supplies `state`, `tiltXDegrees`, and `tiltYDegrees` to later renderer tasks.
- `TodayRekaMotionController.step(double, {required bool reduceMotion})` advances only bounded settling; idle 3D animation belongs to JavaScript.

- [ ] **Step 1: Write failing configuration and controller tests**

Create tests that pin the new contract:

```dart
test('config exposes the approved local render contract', () {
  const config = TodayDitheredRekaConfig();
  expect(config.renderExtent, 216);
  expect(config.hitExtent, 176);
  expect(config.maxTiltDegrees, 8);
  expect(config.ditherGridSize, 4);
  expect(config.maxDevicePixelRatio, 2);
});

test('eyes are permanent and fast drag maps to capped tilt', () {
  final controller = TodayRekaMotionController()
    ..layout(
      const Size(411, 860),
      reservedInsets: const EdgeInsets.fromLTRB(18, 164, 18, 156),
    );
  final start = controller.rekaCenter;
  controller.beginDrag(start);
  controller.updateDrag(
    start + const Offset(180, -90),
    const Duration(milliseconds: 16),
  );
  expect(controller.pose.state, TodayRekaMotionState.dragging);
  expect(controller.pose.eyeOpacity, 1);
  expect(controller.pose.tiltXDegrees.abs(), lessThanOrEqualTo(8));
  expect(controller.pose.tiltYDegrees.abs(), lessThanOrEqualTo(8));
  expect(controller.pose.tiltYDegrees, greaterThan(0));
});

test('reduce motion removes settling and tilt', () {
  final controller = TodayRekaMotionController()
    ..layout(
      const Size(411, 860),
      reservedInsets: const EdgeInsets.fromLTRB(18, 164, 18, 156),
    );
  controller.beginDrag(controller.rekaCenter);
  controller.updateDrag(
    controller.rekaCenter + const Offset(80, 0),
    const Duration(milliseconds: 16),
  );
  controller.endDrag();
  controller.step(1 / 60, reduceMotion: true);
  expect(controller.pose.state, TodayRekaMotionState.idle);
  expect(controller.pose.tiltXDegrees, 0);
  expect(controller.pose.tiltYDegrees, 0);
});
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_reka_motion_controller_test.dart
```

Expected: compilation fails because the new config and controller do not exist.

- [ ] **Step 3: Implement the Reka-only config and pose types**

Use immutable values and explicit assertions:

```dart
@immutable
class TodayDitheredRekaConfig {
  const TodayDitheredRekaConfig({
    this.renderExtent = 216,
    this.hitExtent = 176,
    this.maxTiltDegrees = 8,
    this.ditherGridSize = 4,
    this.pixelSizeRatio = 1,
    this.maxDevicePixelRatio = 2,
  }) : assert(renderExtent >= hitExtent),
       assert(hitExtent >= 64),
       assert(maxTiltDegrees > 0),
       assert(ditherGridSize > 0),
       assert(pixelSizeRatio >= 1),
       assert(maxDevicePixelRatio >= 1);

  final double renderExtent;
  final double hitExtent;
  final double maxTiltDegrees;
  final double ditherGridSize;
  final double pixelSizeRatio;
  final double maxDevicePixelRatio;
}

enum TodayRekaMotionState { idle, dragging, settling }

@immutable
class TodayRekaPose {
  const TodayRekaPose({
    required this.state,
    required this.tiltXDegrees,
    required this.tiltYDegrees,
    this.eyeOpacity = 1,
  });

  final TodayRekaMotionState state;
  final double tiltXDegrees;
  final double tiltYDegrees;
  final double eyeOpacity;
}
```

Implement the motion controller by retaining normalized position, clamping, capped release velocity, and edge attraction from the tested existing controller. Remove `breathPhase`, `breathAmount`, conditional eye opacity, and all dot-field config dependencies. Map velocity to tilt with:

```dart
TodayRekaPose get pose => TodayRekaPose(
  state: _state,
  tiltXDegrees: (-_dragVelocity.dy / maxDragSpeed * config.maxTiltDegrees)
      .clamp(-config.maxTiltDegrees, config.maxTiltDegrees),
  tiltYDegrees: (_dragVelocity.dx / maxDragSpeed * config.maxTiltDegrees)
      .clamp(-config.maxTiltDegrees, config.maxTiltDegrees),
);
```

- [ ] **Step 4: Run the focused tests and verify they pass**

Run the same `flutter test` command. Expected: all controller tests pass.

- [ ] **Step 5: Commit the controller boundary**

```bash
git add mobile/lib/theme_v2/home/today_dithered_reka_config.dart mobile/lib/theme_v2/home/today_reka_motion_controller.dart mobile/test/theme_v2/home/today_reka_motion_controller_test.dart
git commit -m "feat: add today reka motion model"
```

---

### Task 2: Vendor Three.js and build the local renderer baseline

**Files:**
- Create: `mobile/assets/reka_dither/three.module.min.js`
- Create: `mobile/assets/reka_dither/THREE-LICENSE`
- Create: `mobile/assets/reka_dither/reka_dither_engine.js`
- Create: `mobile/assets/reka_dither/reka_dither.html`
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart`

**Interfaces:**
- Produces browser API: `window.RekaRenderer.init(options)`, `setMotion(pose)`, `setReduceMotion(enabled)`, `setPaused(paused)`, `pulseRefresh()`, `resize(width, height, dpr)`, and `destroy()`.
- Produces host messages through `RekaHost.postMessage(JSON.stringify({type: 'ready'}))` or `{type: 'error', code}`.
- Consumes config JSON with `gridSize`, `pixelSizeRatio`, `maxDpr`, and `reduceMotion`.

- [ ] **Step 1: Write failing local-asset contract tests**

The test reads assets through `rootBundle` and asserts the runtime has no network path:

```dart
testWidgets('renderer assets are local and expose the narrow API', (tester) async {
  final template = await rootBundle.loadString(
    'assets/reka_dither/reka_dither.html',
  );
  final engine = await rootBundle.loadString(
    'assets/reka_dither/reka_dither_engine.js',
  );
  final three = await rootBundle.loadString(
    'assets/reka_dither/three.module.min.js',
  );

  expect(template, contains('RekaHost.postMessage'));
  expect(engine, contains('setMotion'));
  expect(engine, contains('setReduceMotion'));
  expect(engine, contains('setPaused'));
  expect(engine, contains('pulseRefresh'));
  expect(engine, contains('destroy'));
  expect(engine, contains('THRESHOLDS'));
  expect(engine, isNot(contains('fetch(')));
  expect(engine, isNot(contains('OrbitControls')));
  expect(three, isNotEmpty);
});
```

- [ ] **Step 2: Run the asset test and verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_reka_renderer_assets_test.dart
```

Expected: asset load fails because `assets/reka_dither/` is not registered.

- [ ] **Step 3: Vendor the pinned Three.js r185 module and license**

Use a temporary package extraction rather than adding npm files to the repository:

```bash
reka_vendor_dir=$(mktemp -d)
cd "$reka_vendor_dir"
npm pack three@0.185.0
tar -xzf three-0.185.0.tgz
cp package/build/three.module.min.js /Users/admin/workwork/eureka-staff/Eureka-Assistant/.worktrees/home-revamp/mobile/assets/reka_dither/three.module.min.js
cp package/LICENSE /Users/admin/workwork/eureka-staff/Eureka-Assistant/.worktrees/home-revamp/mobile/assets/reka_dither/THREE-LICENSE
```

Record `three@0.185.0` in a comment at the top of the HTML bootstrap. Do not retain the tarball or temporary package directory in the repository.

- [ ] **Step 4: Implement the procedural head and Bayer pipeline**

`reka_dither_engine.js` must:

- create a transparent `WebGLRenderer` with `antialias: false`, `alpha: true`, and `powerPreference: 'high-performance'`;
- cap DPR at `2`;
- create a rounded wide head from procedural Three.js geometry, a dark visor, and side modules;
- place the head in a transform group used for idle rocking and drag tilt;
- render shell geometry to a multisampled `WebGLRenderTarget`;
- apply the source-derived `4 × 4` Bayer thresholds in a GLSL3 fullscreen pass;
- exclude eye meshes from the dither target and render them afterward using the same camera and head transform;
- implement each eye as eight orange squares in a `3 × 3` matrix with the center square omitted;
- perform no `fetch`, OrbitControls, zoom, model loading, or GPU readback;
- stop `renderer.setAnimationLoop` while paused and release every geometry, material, target, and renderer on destroy.
- expose `pulseRefresh()` as a single bounded brightness breath driven inside JavaScript, without animating the page background.

Use this exact external API shape:

```javascript
window.RekaRenderer = {
  init,
  setMotion,
  setReduceMotion,
  setPaused,
  pulseRefresh,
  resize,
  destroy,
};
```

The HTML template dynamically imports the vendored module from an in-memory Blob, initializes the engine, and posts a classified result:

```javascript
try {
  const moduleUrl = URL.createObjectURL(
    new Blob([/*__THREE_SOURCE_JSON__*/], { type: 'text/javascript' }),
  );
  const THREE = await import(moduleUrl);
  URL.revokeObjectURL(moduleUrl);
  window.RekaRendererFactory(THREE, document.querySelector('canvas'));
  window.RekaRenderer.init(/*__OPTIONS_JSON__*/);
  RekaHost.postMessage(JSON.stringify({ type: 'ready' }));
} catch (error) {
  RekaHost.postMessage(JSON.stringify({
    type: 'error',
    code: error && error.name ? error.name : 'renderer_init',
  }));
}
```

- [ ] **Step 5: Register the local asset directory**

Add under `flutter.assets`:

```yaml
    - assets/reka_dither/
```

- [ ] **Step 6: Run the asset test and verify it passes**

Expected: all assertions pass and the test finds no renderer network call or OrbitControls dependency.

- [ ] **Step 7: Commit the renderer baseline**

```bash
git add mobile/assets/reka_dither mobile/pubspec.yaml mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart
git commit -m "feat: add local dithered reka renderer"
```

---

### Task 3: Build the transparent Flutter WebView surface and deterministic fallback

**Files:**
- Create: `mobile/lib/theme_v2/home/today_dithered_reka.dart`
- Create: `mobile/lib/theme_v2/home/today_reka_fallback_painter.dart`
- Create: `mobile/test/theme_v2/home/today_dithered_reka_test.dart`

**Interfaces:**
- Consumes: `TodayDitheredRekaConfig` and `TodayRekaPose` from Task 1.
- Consumes: the three local assets from Task 2.
- Produces: `TodayDitheredReka(pose, active, reduceMotion, refreshSignal, config, forceFallback)`.
- Produces: `TodayRekaRenderStatus { loading, ready, fallback }` for tests and diagnostics.

- [ ] **Step 1: Write failing fallback and semantics tests**

```dart
testWidgets('forced fallback keeps the approved head and permanent eyes', (
  tester,
) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: TodayDitheredReka(
        pose: TodayRekaPose(
          state: TodayRekaMotionState.idle,
          tiltXDegrees: 0,
          tiltYDegrees: 0,
        ),
        active: true,
        reduceMotion: false,
        refreshSignal: 0,
        forceFallback: true,
      ),
    ),
  );

  expect(find.byKey(TodayDitheredReka.fallbackKey), findsOneWidget);
  expect(find.byKey(TodayDitheredReka.leftEyeKey), findsOneWidget);
  expect(find.byKey(TodayDitheredReka.rightEyeKey), findsOneWidget);
  expect(tester.getSize(find.byType(TodayDitheredReka)), const Size.square(216));
});

testWidgets('renderer content is excluded from semantics', (tester) async {
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(
    const MaterialApp(
      home: TodayDitheredReka(
        pose: TodayRekaPose(
          state: TodayRekaMotionState.idle,
          tiltXDegrees: 0,
          tiltYDegrees: 0,
        ),
        active: true,
        reduceMotion: true,
        refreshSignal: 0,
        forceFallback: true,
      ),
    ),
  );
  expect(find.bySemanticsLabel('Reka 快捷操作，可拖动'), findsNothing);
  semantics.dispose();
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_dithered_reka_test.dart
```

Expected: compilation fails because `TodayDitheredReka` does not exist.

- [ ] **Step 3: Implement the fallback painter**

The painter draws a wide rounded head, dark visor, two side modules, and a deterministic Bayer-like grayscale fill. Draw the orange eye pixels as child widgets above the painter so tests can address both eye keys independently. Apply `Matrix4.rotationX/Y` from `TodayRekaPose` with perspective `0.0015`; do not add a circular outline or glow.

- [ ] **Step 4: Implement local HTML assembly and the WebView bridge**

Load assets once with `rootBundle`, use `jsonEncode` for safe source injection, and replace exact template markers:

```dart
String buildRekaHtml({
  required String template,
  required String threeSource,
  required String engineSource,
  required Map<String, Object?> options,
}) => template
    .replaceFirst('/*__THREE_SOURCE_JSON__*/', jsonEncode(threeSource))
    .replaceFirst('/*__ENGINE_SOURCE__*/', engineSource)
    .replaceFirst('/*__OPTIONS_JSON__*/', jsonEncode(options));
```

Configure the controller with unrestricted JavaScript, transparent background, no navigation delegate that permits external pages, and a `RekaHost` channel. Wrap `WebViewWidget` in `IgnorePointer` and `ExcludeSemantics`.

On pose changes call exactly:

```dart
controller.runJavaScript(
  'window.RekaRenderer && window.RekaRenderer.setMotion('
  '${jsonEncode(<String, Object?>{
    'state': pose.state.name,
    'tiltXDegrees': pose.tiltXDegrees,
    'tiltYDegrees': pose.tiltYDegrees,
  })})',
);
```

On `active`, lifecycle, or Reduce Motion changes, send `setPaused` and `setReduceMotion`. When `refreshSignal` changes after the first build, send exactly one `pulseRefresh()` call. Switch to fallback on local load failure, a renderer `error` message, or a bounded ready timeout. Do not retry within the same widget instance.

- [ ] **Step 5: Run the tests and verify they pass**

Expected: forced fallback tests pass without initializing the WebView plugin.

- [ ] **Step 6: Commit the Flutter renderer surface**

```bash
git add mobile/lib/theme_v2/home/today_dithered_reka.dart mobile/lib/theme_v2/home/today_reka_fallback_painter.dart mobile/test/theme_v2/home/today_dithered_reka_test.dart
git commit -m "feat: add today dithered reka surface"
```

---

### Task 4: Replace the dot scene with the draggable Reka scene

**Files:**
- Create: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Create: `mobile/test/theme_v2/home/today_reka_scene_test.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

**Interfaces:**
- Consumes: `TodayRekaMotionController` and `TodayDitheredReka`.
- Produces: `TodayRekaScene(onRekaTap, active, topChromeInset, bottomChromeInset, now, refreshSignal, controller, rekaBuilder)`.
- `rekaBuilder` has signature `Widget Function(BuildContext, TodayRekaPose, bool active, bool reduceMotion, int refreshSignal)` so widget tests never instantiate a platform WebView.

- [ ] **Step 1: Write failing scene tests**

Pin the absence of the old background and the retained interaction contract:

```dart
testWidgets('scene uses standard background and has no dot painter', (tester) async {
  await tester.pumpWidget(_host(TodayRekaScene(
    refreshSignal: 0,
    onRekaTap: (_) {},
    rekaBuilder: _fakeReka,
  )));
  expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
  expect(find.byKey(TodayRekaScene.rekaRenderKey), findsOneWidget);
  expect(find.text('今天很安静，我在这里。'), findsOneWidget);
});

testWidgets('drag moves Reka, creates tilt, and does not tap', (tester) async {
  final controller = TodayRekaMotionController();
  var taps = 0;
  await tester.pumpWidget(_host(TodayRekaScene(
    controller: controller,
    refreshSignal: 0,
    onRekaTap: (_) => taps++,
    rekaBuilder: _fakeReka,
  )));
  final before = controller.rekaCenter;
  await tester.drag(
    find.byKey(TodayRekaScene.rekaTargetKey),
    const Offset(90, -30),
  );
  await tester.pump(const Duration(milliseconds: 32));
  expect(controller.rekaCenter.dx, greaterThan(before.dx + 40));
  expect(controller.pose.tiltYDegrees, isNot(0));
  expect(taps, 0);
});
```

Also port existing tests for empty-background drag, live tap anchor, inactive scene cancellation, refresh de-duplication, refresh failure, and quick-action callback selection.

- [ ] **Step 2: Run scene and page tests and verify they fail**

```bash
cd mobile
flutter test test/theme_v2/home/today_reka_scene_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: compilation fails because `TodayRekaScene` does not exist.

- [ ] **Step 3: Implement `TodayRekaScene`**

Use the existing scene's tested gesture code but remove simulation and full-page painting. The build stack contains only heading/copy, the positioned `216 × 216` renderer, and the centered `176 × 176` gesture target.

Reserve safe insets with:

```dart
final reservedInsets = EdgeInsets.fromLTRB(
  18,
  topChromeInset + 88,
  18,
  bottomChromeInset + 38,
);
```

Drive a Flutter ticker only while the controller is settling. Do not keep a 60 fps Flutter ticker running during idle; the local renderer owns idle animation.

The gesture target owns semantics and anchor reporting:

```dart
Semantics(
  label: 'Reka 快捷操作，可拖动',
  button: true,
  expanded: menuExpanded,
  onTap: reportTapAnchor,
  child: GestureDetector(
    key: TodayRekaScene.rekaTargetKey,
    behavior: HitTestBehavior.opaque,
    onTap: reportTapAnchor,
    onPanStart: handlePanStart,
    onPanUpdate: handlePanUpdate,
    onPanEnd: handlePanEnd,
    onPanCancel: handlePanCancel,
    child: const SizedBox.square(dimension: 176),
  ),
)
```

- [ ] **Step 4: Recompose the experiment page**

Replace `TodayDotMatrixScene` with `TodayRekaScene`, use `context.themeV2.background`, and keep refresh behavior unchanged. Rename injectable constructor parameters from dot simulation/config to `rekaController`, `rekaConfig`, and `rekaBuilder`.

Replace the page's refresh `AnimationController` with an integer `_refreshSignal`. Increment it once when `RefreshIndicatorStatus.refresh` begins, pass it through `TodayRekaScene`, and let the renderer own the short brightness breath. If the JavaScript bridge is not ready, dropping the signal is acceptable; it must not queue repeated flashes.

- [ ] **Step 5: Run scene and page tests and verify they pass**

Expected: gesture, refresh, semantics, and quick-action tests pass without a WebView plugin.

- [ ] **Step 6: Commit the Today composition**

```bash
git add mobile/lib/theme_v2/home/today_reka_scene.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/test/theme_v2/home/today_reka_scene_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat: integrate draggable dithered reka"
```

---

### Task 5: Remove the retired dot-field path and lock the floating Top Dock presentation

**Files:**
- Modify: `mobile/lib/config.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Delete: the five retired dot-field production files listed in File Structure.
- Delete: `mobile/test/theme_v2/home/today_dot_field_config_test.dart`
- Delete: `mobile/test/theme_v2/home/today_dot_field_controller_test.dart`
- Delete: `mobile/test/theme_v2/home/today_dot_field_simulation_test.dart`
- Delete: `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart`
- Delete: obsolete `mobile/test/theme_v2/home/goldens/today-dot-*.png` images.
- Create: replacement `mobile/test/theme_v2/home/goldens/today-reka-*.png` images.

**Interfaces:**
- Retains the public compile-time name `AppConfig.todayDotExperiment` for build compatibility.
- Retains `TodayDotExperimentPage` as the flag entry widget for this round.
- Removes all production imports of `TodayDotField*` and `TodayDotMatrix*`.

- [ ] **Step 1: Rewrite golden states around the new visual contract**

Use forced fallback rendering so goldens are deterministic. Cover:

- idle standard background at `411 × 960`;
- dragging with visible tilted eyes at `411 × 960`;
- Reduce Motion at `411 × 960`;
- idle tall layout at `411 × 1080`.

Each golden test asserts:

```dart
expect(find.byKey(ThemeV2GlobalTopNav.floatingDockKey), findsOneWidget);
expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
expect(find.byKey(TodayDitheredReka.leftEyeKey), findsOneWidget);
expect(find.byKey(TodayDitheredReka.rightEyeKey), findsOneWidget);
```

- [ ] **Step 2: Run the new golden tests without updating images**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: failure because replacement golden files do not exist.

- [ ] **Step 3: Remove retired files and update naming comments**

Remove only files no longer imported by the active experiment. Update the `AppConfig.todayDotExperiment` doc comment to say the legacy environment name enables the reversible Today dithered Reka evaluation surface. In the app shell, rename local `continuousToday` to `immersiveToday` while keeping the behavior that enables `extendBodyBehindChrome` and the floating Top Dock for the light experiment.

- [ ] **Step 4: Generate and inspect replacement goldens**

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: four `today-reka-*.png` files are produced. Inspect every PNG before accepting it. Confirm the background is Theme V2 light background, the top and bottom docks match, no dot field is visible, and both eyes are present.

- [ ] **Step 5: Run all affected home tests**

```bash
cd mobile
flutter test test/theme_v2/home/today_reka_motion_controller_test.dart test/theme_v2/home/today_reka_renderer_assets_test.dart test/theme_v2/home/today_dithered_reka_test.dart test/theme_v2/home/today_reka_scene_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_dot_experiment_golden_test.dart test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit cleanup and visual baselines**

```bash
git add mobile/lib/config.dart mobile/lib/theme_v2/home mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home
git commit -m "refactor: retire today dot field"
```

---

### Task 6: Verify renderer behavior, static analysis, and physical-device minimum loop

**Files:**
- Modify only files implicated by verification failures.
- Record no generated APK, temporary npm package, browser capture, or device screenshot in git.

**Interfaces:**
- Consumes the completed Today experiment.
- Produces a physical-device-ready debug APK behind `TODAY_DOT_EXPERIMENT=true`.

- [ ] **Step 1: Format and analyze the affected Dart files**

```bash
cd mobile
dart format lib/theme_v2/home lib/config.dart lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home
flutter analyze lib/theme_v2/home lib/config.dart lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home
```

Expected: formatting changes are intentional and analysis reports no issue.

- [ ] **Step 2: Run the affected test suite twice**

Run the Task 5 affected-test command twice. Expected: both passes are green, demonstrating that lifecycle and animation cleanup do not leave cross-test state.

- [ ] **Step 3: Build the experiment APK**

```bash
cd mobile
flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced successfully.

- [ ] **Step 4: Install and launch on the current Android device**

Use device `RFCY71B21YK`, install the debug APK, reverse the API port when required, force-stop the app, and launch `com.eureka.mindapp`.

Expected: Today opens with the standard background, floating Top Dock, Bottom Dock, and one dithered 3D robot head.

- [ ] **Step 5: Complete the manual physical-device checklist**

Verify all of the following:

1. no full-page dot pattern appears;
2. the head reads as a robot, not a white sphere or page bulge;
3. both orange eyes remain visible during idle, drag, release, refresh, and Reduce Motion;
4. dragging starts only on Reka, follows the finger, and stays inside safe bounds;
5. velocity tilt remains subtle and returns to neutral;
6. a tap opens the existing three actions and a drag does not;
7. the menu anchor follows the moved Reka;
8. background/foreground and route switching do not duplicate the animation loop;
9. renderer failure shows the same-size static fallback rather than a blank surface;
10. five minutes of idle plus repeated dragging does not produce unacceptable heat or visible frame loss.

- [ ] **Step 6: Inspect the final diff and commit verification fixes**

```bash
git diff --check
git status --short
git diff --stat main...HEAD
```

If verification required fixes, commit only those fixes with:

```bash
git add mobile/lib/config.dart mobile/lib/theme_v2/home mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/assets/reka_dither mobile/test/theme_v2/home mobile/pubspec.yaml
git commit -m "fix: harden today dithered reka"
```

If no fixes were required, do not create an empty commit.
