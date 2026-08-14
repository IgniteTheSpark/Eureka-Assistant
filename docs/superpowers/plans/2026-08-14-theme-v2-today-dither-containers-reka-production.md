# Theme V2 Today Dither Containers and Reka Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-object Dither bodies with two ReactBits-inspired displaced container fields and make the larger terminal-green Reka perform synchronized Signal/Asset seed production.

**Architecture:** Flutter owns both container shaders, all object geometry, gestures, accessibility, and Asset physics. A shared `TodayOutputCoordinator` exposes one FIFO production phase to the Signal band, seed overlay, and the existing bounded Three.js Reka renderer. Reka remains the only WebView; its renderer receives serialized production cues and blends them with drag motion.

**Tech Stack:** Flutter 3.38+ runtime fragment shaders, Dart/Flutter widgets and tests, forge2d Asset physics, local Three.js r185 WebView renderer, Android foldable device QA.

## Global Constraints

- Light-mode Today experiment only; Dark tuning stays out of scope.
- Keep a solid page background and two independently clipped Dither fields; never create a page-wide field.
- Signal/Asset records, gestures, semantics, and canonical detail routes remain Flutter-owned.
- Reka is the only WebView/WebGL surface.
- Initial hydration, refresh, and route return must not replay existing IDs.
- At most one production runs at a time and queued IDs use FIFO order.
- Reduce Motion removes seed flight, shake, recoil, and repeated ambient motion.
- Preserve all unrelated dirty worktree changes and stage only files owned by each task.

## File Structure

- `mobile/shaders/today_dither_field.frag`: procedural noise, Bayer quantization, directional flow, and circle/capsule pressure sources.
- `mobile/lib/theme_v2/home/today_dither_field.dart`: shader configuration, displacement value objects, loading/fallback, and painter uniform binding.
- `mobile/lib/theme_v2/home/today_signal_band.dart`: Signal geometry sources, transparent strips, and first-track birth behavior.
- `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`: physics-derived circle sources and transparent Asset visuals.
- `mobile/lib/theme_v2/home/today_region_watermark.dart`: center-axis watermark placement API.
- `mobile/lib/theme_v2/home/today_output_coordinator.dart`: FIFO production phases and shared cue state.
- `mobile/lib/theme_v2/home/today_output_overlay.dart`: neutral side seed, boundary handoff, and phase callbacks.
- `mobile/lib/theme_v2/home/today_living_surface.dart`: two container composition, shared coordinator, boundary geometry, and local Reka field removal.
- `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`: coordinator ownership and Reka/content synchronization.
- `mobile/lib/theme_v2/home/today_dithered_reka.dart`: production cue serialization and terminal-green fallback eyes.
- `mobile/lib/theme_v2/home/today_dithered_reka_config.dart`: larger render/hit extents.
- `mobile/lib/theme_v2/home/today_reka_scene.dart`: passes the shared production cue to Reka.
- `mobile/assets/reka_dither/reka_dither_engine.js`: green eye groups and blended charge/emit/follow/recover 3D motion.

---

### Task 1: Runtime Dither Field and Pressure Model

**Files:**
- Create: `mobile/shaders/today_dither_field.frag`
- Create: `mobile/lib/theme_v2/home/today_dither_field.dart`
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/test/theme_v2/home/today_dither_field_test.dart`

**Interfaces:**
- Produces: `TodayDitherFlow`, `TodayDitherSource`, `TodayDitherFieldConfig`, `TodayDitherField`, and `todayDitherPressureAt(Offset, TodayDitherSource)`.
- `TodayDitherSource.circle` consumes a center, radius, and energy; `TodayDitherSource.capsule` consumes a center, size, and energy.
- `TodayDitherField` consumes `Animation<double> motion`, a config, and at most 24 visible sources.

- [ ] **Step 1: Write failing pressure-model and widget tests**

```dart
test('circle pressure is strongest at center and zero outside feather', () {
  const source = TodayDitherSource.circle(
    center: Offset(40, 40),
    radius: 20,
    energy: .7,
  );
  expect(todayDitherPressureAt(const Offset(40, 40), source), greaterThan(.9));
  expect(todayDitherPressureAt(const Offset(80, 40), source), 0);
});

test('capsule pressure covers its body but not its exterior', () {
  const source = TodayDitherSource.capsule(
    center: Offset(120, 30),
    size: Size(180, 48),
    energy: .2,
  );
  expect(todayDitherPressureAt(const Offset(60, 30), source), greaterThan(.8));
  expect(todayDitherPressureAt(const Offset(120, 80), source), 0);
});
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `cd mobile && flutter test test/theme_v2/home/today_dither_field_test.dart`

Expected: FAIL because `today_dither_field.dart` and its types do not exist.

- [ ] **Step 3: Add the shader asset and immutable Dart contract**

Add to `mobile/pubspec.yaml`:

```yaml
  shaders:
    - shaders/today_dither_field.frag
```

Implement the source contract with explicit shapes:

```dart
enum TodayDitherSourceShape { circle, capsule }

@immutable
class TodayDitherSource {
  const TodayDitherSource.circle({
    required this.center,
    required double radius,
    this.energy = 0,
  }) : shape = TodayDitherSourceShape.circle,
       size = Size.square(radius * 2);

  const TodayDitherSource.capsule({
    required this.center,
    required this.size,
    this.energy = 0,
  }) : shape = TodayDitherSourceShape.capsule;

  final TodayDitherSourceShape shape;
  final Offset center;
  final Size size;
  final double energy;
}
```

The fragment shader must use `FlutterFragCoord()`, four coherent-noise octaves, an 8 x 8 Bayer threshold, a `uFlowDirection` vector, and fixed uniforms for 24 sources. Circle and capsule signed-distance functions subtract pressure from the wave intensity before quantization. Output uses transparent neutral dots over the Flutter page background, not an opaque black field.

- [ ] **Step 4: Bind uniforms and provide a deterministic fallback**

`TodayDitherField` loads `shaders/today_dither_field.frag` once, repaints from the supplied animation, fills unused source uniforms with zeros, and falls back to `TodayDitherMaterial(shape: TodayDitherShape.field, ...)` if shader loading fails. Clamp source count to 24 in stable visual order and expose `TodayDitherField.shaderKey` for tests.

- [ ] **Step 5: Run tests and analysis**

Run: `cd mobile && flutter test test/theme_v2/home/today_dither_field_test.dart test/theme_v2/home/today_dither_material_test.dart`

Run: `cd mobile && flutter analyze lib/theme_v2/home/today_dither_field.dart`

Expected: all tests pass and analysis reports no issues.

- [ ] **Step 6: Commit the shader foundation**

```bash
git add mobile/pubspec.yaml mobile/shaders/today_dither_field.frag mobile/lib/theme_v2/home/today_dither_field.dart mobile/test/theme_v2/home/today_dither_field_test.dart
git commit -m "feat: add displaced today dither fields"
```

### Task 2: Signal Container and First-Track Birth

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Modify: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dither_material_test.dart`

**Interfaces:**
- Consumes: `TodayDitherField`, `TodayDitherFieldConfig.signal`, and `TodayDitherSource.capsule`.
- Produces: `TodaySignalBirthState { idle, clearing, unfolding }`, `birthSignalId`, and stable first-lane ordering.

- [ ] **Step 1: Write failing tests for transparent strips, field sources, and birth clearing**

```dart
expect(find.byKey(const ValueKey('today-signal-dither-field')), findsOneWidget);
expect(
  find.descendant(
    of: find.byKey(const ValueKey('today-signal-band')),
    matching: find.byWidgetPredicate(
      (widget) => widget is TodayDitherMaterial &&
          widget.shape == TodayDitherShape.strip,
    ),
  ),
  findsNothing,
);

await tester.pumpWidget(host(
  TodaySignalBand(
    items: items,
    birthState: TodaySignalBirthState.clearing,
    birthSignalId: 'new-signal',
  ),
));
expect(find.byKey(const ValueKey('today-signal-lane-0-cleared')), findsOneWidget);
expect(find.byKey(const ValueKey('today-signal-lane-1')), findsOneWidget);
expect(find.byKey(const ValueKey('today-signal-lane-2')), findsOneWidget);
```

- [ ] **Step 2: Run the Signal tests and confirm failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_signal_band_test.dart`

Expected: FAIL because the field key and birth state do not exist and strips still own Dither bodies.

- [ ] **Step 3: Put one shared Dither field behind all lanes**

Inside the existing motion `AnimatedBuilder`, compute every visible strip center and extent from the same `x`, `laneHeight`, `_stripWidth`, and `_stripHeight` used for layout. Pass capsule sources to one `TodayDitherField` before the lane widgets. Use the Signal config with flow approximately `Offset(1, .08)` and speed `1.5x` the Asset field.

- [ ] **Step 4: Remove the strip body and implement the Birth Lane**

Replace `_SignalStrip`'s `TodayDitherMaterial` wrapper with transparent `Material` plus `InkWell`. During `clearing` and `unfolding`, replace lane 0's visible strips with `ValueKey('today-signal-lane-0-cleared')`; lanes 1 and 2 continue. When `birthSignalId` becomes stable, force it to lane 0 and order it first so older lane-0 items re-enter after one normal gap.

- [ ] **Step 5: Move the discovery watermark to the center seam**

Extend `TodayRegionWatermark` with explicit `EdgeInsets padding` and `MainAxisAlignment`/alignment behavior. Place `Reka 发现` at the lower-left of the Signal region with padding that keeps it just above the seam.

- [ ] **Step 6: Run tests and commit**

Run: `cd mobile && flutter test test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/today_dither_material_test.dart`

Expected: PASS; existing tap/pause/open tests remain green.

```bash
git add mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/today_region_watermark.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/today_dither_material_test.dart
git commit -m "feat: move signal dither into its container"
```

### Task 3: Asset Container Displacement

**Files:**
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_gravity_chamber.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

**Interfaces:**
- Consumes: `TodayDitherFieldConfig.asset` and `TodayDitherSource.circle`.
- Produces: circle sources based on each forge2d body's real center, radius, velocity, and grabbed state.

- [ ] **Step 1: Replace the existing per-ball Dither assertion with failing container assertions**

```dart
expect(find.byKey(const ValueKey('today-asset-dither-field')), findsOneWidget);
expect(
  find.descendant(
    of: find.byKey(const ValueKey('theme-v2-asset-bubble-rotation-asset-1')),
    matching: find.byWidgetPredicate(
      (widget) => widget is TodayDitherMaterial &&
          widget.shape == TodayDitherShape.circle,
    ),
  ),
  findsNothing,
);
```

Add a test that advances the supplied gravity stream and verifies the field's `sources.single.center` follows the rendered bubble center.

- [ ] **Step 2: Run the focused Asset tests and confirm failure**

Run: `cd mobile && flutter test test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

Expected: FAIL because the shared field does not exist and `_ThemeV2BubbleVisual` still paints a Dither circle.

- [ ] **Step 3: Build physics-derived pressure sources inside the repaint builder**

For each visible `Bubble`, create:

```dart
TodayDitherSource.circle(
  center: Offset(bubble.x, bubble.y),
  radius: bubble.r,
  energy: math.min(
    1,
    bubble.body.linearVelocity.length / 12 +
        (_grabbedAssetId == bubble.id ? .55 : 0),
  ),
)
```

Render one `TodayDitherField` behind the watermark and bubble targets. Use downward flow approximately `Offset(.10, 1)` with the slower base speed.

- [ ] **Step 4: Remove per-ball body material without changing gestures or semantics**

Replace `_ThemeV2BubbleVisual`'s `TodayDitherMaterial` with a transparent `Material`/`InkResponse` that only centers the existing Asset icon. Preserve target sizes, rotation keys, tap callbacks, compact Reduce Motion grid, retirement animation, and highlighted icon colors.

- [ ] **Step 5: Move the generated watermark and simplify chamber fill**

Place `Reka 生成` at the upper-right of the Asset region, just below the seam. Remove the opaque lower gradient from `ThemeV2GravityChamber`; keep its clipping and invisible collision geometry.

- [ ] **Step 6: Run tests and commit**

Run: `cd mobile && flutter test test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

Expected: PASS, including dragging, rotation, compact-grid, removal, and 50-item coverage.

```bash
git add mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/theme_v2_gravity_chamber.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
git commit -m "feat: displace asset container dither with physics"
```

### Task 4: Shared Production Phases and Neutral Seed Handoff

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_output_coordinator.dart`
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/test/theme_v2/home/today_output_coordinator_test.dart`
- Modify: `mobile/test/theme_v2/home/today_output_overlay_test.dart`
- Modify: `mobile/test/theme_v2/home/today_living_surface_test.dart`

**Interfaces:**
- Produces: `TodayOutputPhase { idle, charge, emit, handoff, recover }`, `TodayOutputSide { left, right }`, and `TodayOutputCue`.
- `TodayOutputCoordinator.cue` is the shared source read by Reka, Signal band, and overlay.
- `TodayOutputOverlay` reports phase changes and exact boundary handoff coordinates.

- [ ] **Step 1: Write failing phase, side, and handoff tests**

```dart
expect(coordinator.cue.phase, TodayOutputPhase.idle);
coordinator.reconcile(
  assetIds: const ['asset-1'],
  signalIds: const [],
  rekaCenter: const Offset(280, 420),
);
expect(coordinator.cue.phase, TodayOutputPhase.charge);
coordinator.updatePhase(TodayOutputPhase.emit);
expect(coordinator.cue.kind, TodayOutputKind.asset);
expect(coordinator.cue.phase, TodayOutputPhase.emit);
```

Add overlay tests asserting a Signal seed ends at `signalBoundaryY` and an Asset seed ends at `assetFloorY`, and that Reduce Motion calls handoff without an animated seed.

- [ ] **Step 2: Run the three focused test files and confirm failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_coordinator_test.dart test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/today_living_surface_test.dart`

Expected: FAIL because the phase/cue and exact boundary inputs do not exist.

- [ ] **Step 3: Extend the coordinator without changing ID ownership rules**

Store phase on the active item, expose immutable `cue`, keep initial hydration and duplicate suppression unchanged, and reset to `idle` only after `completeCurrent`. Add `lastCompletedSignalId` so `TodaySignalBand` can force the newborn item into lane 0.

- [ ] **Step 4: Replace the Dither object overlay with a neutral seed**

Render a small terminal-green point cluster beside Reka. Choose the right side when `source.dx + renderExtent / 2 + 32 <= viewportWidth - 18`, otherwise choose left. Animate only vertical travel after detachment. Signal handoff unfolds a transparent content strip at the Signal upper boundary; Asset handoff supplies the chamber-floor spawn center. Remove the old circle/strip Dither bodies and Signal trail.

- [ ] **Step 5: Lift coordinator ownership to the experiment page**

Create one `TodayOutputCoordinator` in `_TodayDotExperimentPageState`, dispose it with the page, pass it into `TodayLivingSurface`, and rebuild `TodayRekaScene` from `Listenable.merge([_sceneRekaController, _outputCoordinator])`. This guarantees one cue drives Reka, lane clearing, and the overlay.

- [ ] **Step 6: Remove the local Reka Dither field and insert a solid seam**

Delete `today-local-dither-field-position` and `today-local-dither-field` from `TodayLivingSurface`. Keep header height, split the remaining content into Signal `1`, a `12-18 px` solid seam, and Asset `2`, and pass the computed Signal upper boundary and Asset floor to the overlay.

- [ ] **Step 7: Run tests and commit**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_coordinator_test.dart test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/today_living_surface_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart`

Expected: PASS with no initial replay, no duplicate stable object, and synchronized direct handoff under Reduce Motion.

```bash
git add mobile/lib/theme_v2/home/today_output_coordinator.dart mobile/lib/theme_v2/home/today_output_overlay.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/test/theme_v2/home/today_output_coordinator_test.dart mobile/test/theme_v2/home/today_output_overlay_test.dart mobile/test/theme_v2/home/today_living_surface_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat: synchronize reka output handoffs"
```

### Task 5: Larger Terminal-Green Reka Production Motion

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dithered_reka_config.dart`
- Modify: `mobile/lib/theme_v2/home/today_dithered_reka.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Modify: `mobile/assets/reka_dither/reka_dither_engine.js`
- Modify: `mobile/test/theme_v2/home/today_dithered_reka_test.dart`
- Modify: `mobile/test/theme_v2/home/today_reka_motion_controller_test.dart`
- Modify: `mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart`
- Modify: `mobile/test/theme_v2/home/today_reka_scene_test.dart`

**Interfaces:**
- Consumes: `TodayOutputCue` from Task 4.
- Produces: `window.RekaRenderer.setProduction(cue)` with `{kind, phase, side}` and fallback eye-direction behavior.

- [ ] **Step 1: Write failing size, color, and renderer-contract tests**

```dart
expect(const TodayDitheredRekaConfig().renderExtent, 288);
expect(const TodayDitheredRekaConfig().hitExtent, 220);
expect(engine, contains('setProduction'));
expect(engine, contains('0x78ff74'));
expect(engine, contains('eyeGroup'));
```

Add a fallback widget test that pumps an upward Signal cue and asserts both eye widgets use terminal green and shift upward relative to idle.

- [ ] **Step 2: Run the Reka test group and confirm failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_dithered_reka_test.dart test/theme_v2/home/today_reka_motion_controller_test.dart test/theme_v2/home/today_reka_renderer_assets_test.dart test/theme_v2/home/today_reka_scene_test.dart`

Expected: FAIL on the old `248/200` size, orange renderer eyes, and missing production API.

- [ ] **Step 3: Enlarge the real renderer and make eyes addressable**

Set default extents to `288/220`. In Three.js, put all eye pixels in `eyeGroup`, change the material/emissive color to `0x78ff74`, slightly increase `motionGroup` scale or move the camera closer, and verify the shell remains inside the canvas during the maximum production/drag blend.

- [ ] **Step 4: Add the production cue bridge**

`TodayDitheredReka` accepts `TodayOutputCue cue`, serializes it to `setProduction`, sends the latest cue after WebView readiness, and mirrors direction in the Flutter fallback. `TodayRekaScene` passes the cue through its default builder and updated `TodayRekaBuilder` signature.

- [ ] **Step 5: Blend 3D production motion with drag motion**

In `tick`:

- `charge`: yaw `6-9 degrees` toward the seed side and apply one decaying micro-shake;
- Signal `emit/follow`: pitch upward `8-12 degrees`, shift `eyeGroup` upward, and add a small downward recoil;
- Asset `emit/follow`: pitch downward `10-14 degrees`, shift eyes downward, and add a small upward recoil;
- `recover`: exponentially return production offsets to zero over `350-450 ms`;
- `idle`: retain only slow three-axis sway and breathing.

Clamp the additive result so drag plus production never exceeds a controlled robot-like range. `setReduceMotion(true)` zeros shake/recoil and retains only a brief directional eye offset.

- [ ] **Step 6: Run tests and commit**

Run: `cd mobile && flutter test test/theme_v2/home/today_dithered_reka_test.dart test/theme_v2/home/today_reka_motion_controller_test.dart test/theme_v2/home/today_reka_renderer_assets_test.dart test/theme_v2/home/today_reka_scene_test.dart`

Expected: PASS with green permanent eyes, larger geometry, and production cue serialization.

```bash
git add mobile/lib/theme_v2/home/today_dithered_reka_config.dart mobile/lib/theme_v2/home/today_dithered_reka.dart mobile/lib/theme_v2/home/today_reka_scene.dart mobile/assets/reka_dither/reka_dither_engine.js mobile/test/theme_v2/home/today_dithered_reka_test.dart mobile/test/theme_v2/home/today_reka_motion_controller_test.dart mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart mobile/test/theme_v2/home/today_reka_scene_test.dart
git commit -m "feat: animate reka through output production"
```

### Task 6: Integrated Regression, Visual Baselines, and Device QA

**Files:**
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Modify: `mobile/test/theme_v2/home/goldens/today-reka-idle-411-light.png`
- Modify: `mobile/test/theme_v2/home/goldens/today-reka-dragging-411-light.png`
- Modify: `mobile/test/theme_v2/home/goldens/today-reka-reduce-motion-411-light.png`
- Modify only if required by intentional layout output: other Today light golden files under `mobile/test/theme_v2/home/goldens/`

**Interfaces:**
- Consumes all prior task interfaces.
- Produces verified light-mode behavior on automated tests and connected foldable hardware.

- [ ] **Step 1: Add integrated widget assertions before updating goldens**

Assert the composed Today scene has exactly two `TodayDitherField` widgets, no `today-local-dither-field`, a `288` Reka render extent, correct center-seam watermarks, and transparent stable objects. Add a production fixture that advances a new Signal and Asset through FIFO handoff.

- [ ] **Step 2: Run the complete focused Today suite**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/home/today_dither_field_test.dart \
  test/theme_v2/home/today_dither_material_test.dart \
  test/theme_v2/home/today_signal_band_test.dart \
  test/theme_v2/home/theme_v2_asset_bubble_field_test.dart \
  test/theme_v2/home/today_output_coordinator_test.dart \
  test/theme_v2/home/today_output_overlay_test.dart \
  test/theme_v2/home/today_living_surface_test.dart \
  test/theme_v2/home/today_dithered_reka_test.dart \
  test/theme_v2/home/today_reka_motion_controller_test.dart \
  test/theme_v2/home/today_reka_renderer_assets_test.dart \
  test/theme_v2/home/today_reka_scene_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: all focused tests pass before any golden is accepted.

- [ ] **Step 3: Regenerate and inspect only intentional light-mode goldens**

Run: `cd mobile && flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart`

Inspect every changed PNG. Confirm Reka is larger without clipping, eyes are terminal green, local halo is absent, watermarks straddle the seam, and content remains readable over the fields. Do not update Dark baselines for this light-only scope.

- [ ] **Step 4: Analyze all modified Dart files**

Run: `cd mobile && flutter analyze lib/theme_v2/home test/theme_v2/home`

Expected: no errors or warnings introduced by this feature.

- [ ] **Step 5: Build, install, and launch on the connected foldable**

Run: `cd mobile && flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true`

Install the generated APK on `RFCY71B21YK`, restore the backend reverse mapping, and launch `com.eureka.mindapp`. Verify portrait and unfolded layouts, drag Reka through both regions, drag and collide Assets, and trigger one new Signal and one new Asset.

- [ ] **Step 6: Capture device evidence and tune only exposed config values**

Capture the clean Today screen plus Signal birth and Asset settling states. Adjust only field config values, Reka scale/camera, and motion amplitudes; do not change the approved interaction model during tuning. Re-run the focused suite after each tuning commit.

- [ ] **Step 7: Commit verification artifacts and final tuning**

```bash
git add mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart mobile/test/theme_v2/home/goldens mobile/lib/theme_v2/home mobile/assets/reka_dither mobile/shaders mobile/pubspec.yaml
git commit -m "test: verify today dither production world"
```

## Self-Review Results

- Spec coverage: all container, watermark, pressure, Reka, seed, FIFO, first-track, Reduce Motion, lifecycle, fallback, and device requirements map to Tasks 1-6.
- Placeholder scan: no `TBD`, implementation placeholder, or unspecified test step remains.
- Type consistency: `TodayDitherSource`, `TodayDitherField`, `TodayOutputCue`, `TodayOutputPhase`, `TodayOutputSide`, and `TodaySignalBirthState` are introduced once and consumed under the same names in later tasks.
- Scope: Signal-detail and reminder-domain dirty changes are deliberately excluded from all task commits.
