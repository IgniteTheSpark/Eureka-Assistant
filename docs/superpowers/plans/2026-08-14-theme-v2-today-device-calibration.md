# Theme V2 Today Device Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both Today watermarks useful navigation entrances, let Reka move and turn across the full safe world, make Signal/Asset production readable on device, share the floating Top Dock across root pages, and calibrate light/dark contrast independently.

**Architecture:** The app shell owns root navigation and passes two explicit callbacks through the Today experiment composition. Reka bounds are calculated from visible-body extents while the transparent renderer remains oversized; drag pose uses nonlinear per-axis response. The production overlay owns one longer phase timeline and decorative trail, while stable Signal/Asset content remains owned by existing Flutter widgets. Brightness-specific presentation values stay local to the Dither and watermark components.

**Tech Stack:** Flutter/Dart widget tests and goldens, local Three.js r185 WebView renderer, runtime fragment shader, forge2d Asset physics, Android foldable device QA.

## Global Constraints

- Preserve all unrelated reminder, Signal-detail, Bottom Sheet, and service-layer dirty changes; stage only files listed by the active task.
- `Reka 发现` opens the complete `RekaSignalsPage`; `Reka 生成` selects the Asset Library root.
- Individual Signal and Asset gestures keep their canonical behavior.
- Watermark visuals remain borderless with a minimum 44 x 44 logical-pixel semantic target.
- Reka may cross the date, Signal, seam, and Asset regions but must keep its visible body outside the Top and Bottom Docks.
- Whole-object yaw stays bounded near 32 degrees; whole-object pitch stays bounded near 22-24 degrees.
- Normal production lasts 1.35-1.50 seconds; Reduce Motion keeps direct handoff.
- Light Dither opacity is Signal `.40` and Asset `.38`; dark remains Signal `.32` and Asset `.30`.
- Light watermark opacity is count `.07` and label `.44`; dark is count `.14` and label `.68`.

---

### Task 1: Clickable Watermark Entrances and Root Navigation

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/test/theme_v2/home/today_living_surface_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

**Interfaces:**
- `TodayRegionWatermark` consumes `VoidCallback? onPressed` and `String? semanticLabel`.
- `TodaySignalBand` consumes `VoidCallback? onOpenAll`.
- `ThemeV2AssetBubbleField` consumes `VoidCallback? onOpenLibrary`.
- `TodayLivingSurface` consumes and forwards both callbacks.
- `TodayDotExperimentPage` consumes `VoidCallback? onOpenReka` and `VoidCallback? onOpenAssetLibrary`.

- [ ] **Step 1: Write failing watermark and callback propagation tests**

Add tests that pump a non-empty Signal/Asset region and assert:

```dart
expect(find.bySemanticsLabel('查看全部 Reka 发现'), findsOneWidget);
await tester.tap(find.bySemanticsLabel('查看全部 Reka 发现'));
expect(openAllCalls, 1);

expect(find.bySemanticsLabel('打开资产库'), findsOneWidget);
await tester.tap(find.bySemanticsLabel('打开资产库'));
expect(openLibraryCalls, 1);
```

Keep an existing individual Signal tap in the same suite and assert it increments only `openSignalCalls`, proving the watermark callback does not replace canonical item opening.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/home/today_signal_band_test.dart \
  test/theme_v2/home/theme_v2_asset_bubble_field_test.dart \
  test/theme_v2/home/today_living_surface_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: FAIL because the watermark is ignored by pointers and the callback parameters do not exist.

- [ ] **Step 3: Implement a compact semantic watermark button**

Replace `IgnorePointer`/`ExcludeSemantics` with an aligned `Semantics(button: true)` plus a transparent `InkResponse` or `GestureDetector`. Preserve the existing count/label layout and constrain the interactive group to at least 44 x 44:

```dart
Semantics(
  button: onPressed != null,
  label: semanticLabel,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onPressed,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: watermarkContent,
    ),
  ),
)
```

When `onPressed` is null, preserve decorative behavior and exclude duplicate text semantics.

- [ ] **Step 4: Propagate the two callbacks through Today**

Wire `onOpenAll` into `Reka 发现`, and `onOpenLibrary` into `Reka 生成`. Pass them through `TodayLivingSurface` and `TodayDotExperimentPage` without changing individual-object callbacks.

- [ ] **Step 5: Wire shell destinations**

Construct the experiment page with:

```dart
onOpenReka: () => _openRekaSignals(context),
onOpenAssetLibrary: () => _selectDestination(2),
```

Add a shell test using injected callbacks/repository fixtures: tap discovery and assert `RekaSignalsPage` is pushed; tap generation and assert the selected Bottom Dock destination becomes index `2`.

- [ ] **Step 6: Run tests and commit**

Run the Task 1 test set plus `test/theme_v2/shell/theme_v2_shell_test.dart`. Expected: PASS.

```bash
git add mobile/lib/theme_v2/home/today_region_watermark.dart mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/today_living_surface_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat: open today discovery and library watermarks"
```

### Task 2: Shared Floating Top Dock on Root Pages

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Produces one shell-owned `rootFloatingDock` boolean used by all three root destinations.
- Preserves `showTopNav` and `showDock` decisions for nested Calendar/Library surfaces.

- [ ] **Step 1: Write failing root-Dock tests**

Pump the production page set at indices 0, 1, and 2. For each root surface assert:

```dart
final nav = tester.widget<ThemeV2GlobalTopNav>(
  find.byType(ThemeV2GlobalTopNav),
);
expect(nav.floatingDock, isTrue);
expect(nav.transparentSurface, isTrue);
```

Navigate the Library controller to a nested detail and verify its existing chrome flags still hide or replace shell chrome as before.

- [ ] **Step 2: Run the shell tests and verify failure**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/shell/theme_v2_shell_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: Calendar and Asset Library root assertions FAIL because `todayFloatingDock` is limited to `_index == 0`.

- [ ] **Step 3: Centralize floating root chrome**

Replace the Today-only boolean with a root-page decision. Set `extendBodyBehindChrome: true` on the three production root scaffolds where their current chrome flags show Top Nav, and pass the same floating/transparent values into `ThemeV2GlobalTopNav`. Capture activity still replaces the nav through the existing `AnimatedSwitcher`; injected test pages retain their explicit scaffold configuration.

- [ ] **Step 4: Run tests and commit**

Run the Task 2 test set. Expected: PASS, including capture/top-nav replacement and nested navigation state.

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "feat: share floating top dock across root pages"
```

### Task 3: Full Safe-World Reka Drag and Strong Vertical Pitch

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dithered_reka_config.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_motion_controller.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Modify: `mobile/lib/theme_v2/home/today_dithered_reka.dart`
- Modify: `mobile/assets/reka_dither/reka_dither_engine.js`
- Modify: `mobile/test/theme_v2/home/today_reka_motion_controller_test.dart`
- Modify: `mobile/test/theme_v2/home/today_reka_scene_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dithered_reka_test.dart`
- Modify: `mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart`

**Interfaces:**
- `TodayDitheredRekaConfig` exposes visible-body extents used only for safe bounds: `visibleBodyWidth = 196`, `visibleBodyHeight = 132`.
- `TodayRekaMotionController.layout` applies half visible-body dimensions instead of half `renderExtent`.
- `TodayRekaPose.tiltXDegrees` uses the same nonlinear response family as horizontal yaw.

- [ ] **Step 1: Write failing safe-bound and vertical-pose tests**

For a `411 x 891` scene with top/bottom insets, assert the safe rectangle is based on `98/66` body half-extents and that a slow upward drag is readable:

```dart
controller.layout(
  const Size(411, 891),
  reservedInsets: const EdgeInsets.fromLTRB(4, 96, 4, 112),
);
expect(controller.safeBounds.left, 102);
expect(controller.safeBounds.right, 309);

controller.beginDrag(controller.rekaCenter);
controller.updateDrag(
  controller.rekaCenter - const Offset(0, 6),
  const Duration(milliseconds: 16),
);
expect(controller.pose.tiltXDegrees.abs(), greaterThan(2));
expect(controller.pose.tiltXDegrees.abs(), lessThanOrEqualTo(6));
```

Add scene tests proving date/Signal/Asset geometry does not change safe bounds and only the two chrome inset inputs do.

- [ ] **Step 2: Run focused Reka tests and verify failure**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/home/today_reka_motion_controller_test.dart \
  test/theme_v2/home/today_reka_scene_test.dart \
  test/theme_v2/home/today_dithered_reka_test.dart \
  test/theme_v2/home/today_reka_renderer_assets_test.dart
```

Expected: FAIL on render-extent bounds and weak linear vertical tilt.

- [ ] **Step 3: Calculate bounds from the visible robot**

Add visible-body dimensions to config and use independent x/y margins in `layout`. In `TodayRekaScene`, change reservations to a small side breathing gap plus exact `topChromeInset`/`bottomChromeInset`; remove the `+88` and `+38` barriers.

- [ ] **Step 4: Apply nonlinear pitch and whole-object rotation**

Extract one signed eased ratio helper using `pow(abs(velocity) / maxDragSpeed, .4)`. Keep the pose's base `maxTiltDegrees = 8`, then render vertical drag with a `3.0` multiplier while keeping horizontal drag at `4.0`. This yields approximately 24-degree pitch and 32-degree yaw at maximum drag speed. Apply the same multipliers in Three.js and Flutter fallback; settling uses reduced multipliers.

- [ ] **Step 5: Run tests and commit**

Run the Task 3 suite. Expected: PASS with bounded nonlinear pitch, wider safe bounds, fallback/WebGL parity, and no detached eye transform.

```bash
git add mobile/lib/theme_v2/home/today_dithered_reka_config.dart mobile/lib/theme_v2/home/today_reka_motion_controller.dart mobile/lib/theme_v2/home/today_reka_scene.dart mobile/lib/theme_v2/home/today_dithered_reka.dart mobile/assets/reka_dither/reka_dither_engine.js mobile/test/theme_v2/home/today_reka_motion_controller_test.dart mobile/test/theme_v2/home/today_reka_scene_test.dart mobile/test/theme_v2/home/today_dithered_reka_test.dart mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart
git commit -m "feat: expand and strengthen today reka drag"
```

### Task 4: Legible Signal Rise and Asset Fall

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/test/theme_v2/home/today_output_overlay_test.dart`
- Modify: `mobile/test/theme_v2/home/today_living_surface_test.dart`

**Interfaces:**
- Normal duration is `1440 ms` with phase thresholds charge `.21`, handoff `.72`, recover `.91`.
- `_TerminalSeed` is 20 px, iconless, dark-edged, terminal-green-cored.
- Asset handoff uses a destination 16 px inside the Asset chamber floor.

- [ ] **Step 1: Write failing timing, trail, and destination tests**

Assert no handoff before about one second, the phase order remains charge/emit/handoff/recover, and the normal overlay contains one seed plus three decorative trail keys. For Asset output:

```dart
await tester.pump(const Duration(milliseconds: 1000));
expect(handoffs, isEmpty);
await tester.pump(const Duration(milliseconds: 60));
expect(handoffs.single.dy, assetFloorY - 16);
expect(find.byKey(const ValueKey('today-output-trail-0')), findsOneWidget);
```

Retain the existing Reduce Motion test and assert it performs direct handoff without seed or trail.

- [ ] **Step 2: Run focused output tests and verify failure**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/home/today_output_overlay_test.dart \
  test/theme_v2/home/today_living_surface_test.dart
```

Expected: FAIL because duration is 720 ms, seed is 14 px, no trail exists, and Asset handoff is exactly on the floor.

- [ ] **Step 3: Implement the longer production timeline**

Set the normal controller duration to `1440 ms`. Keep charge at `.21`; use travel `.21-.72`, handoff `.72-.91`, and recover `.91-1`. Increase detached offset modestly to preserve the beside-Reka origin.

- [ ] **Step 4: Render seed structure and short afterimages**

Render a 20 px seed with a neutral foreground edge and terminal-green core. Add three non-semantic, non-interactive copies sampled behind travel at progress offsets `.035`, `.07`, and `.105`, with descending opacity and size. Do not add icons or a continuous comet line.

- [ ] **Step 5: Move Asset handoff inside the chamber**

Return `assetFloorY - 16` from `_handoffPoint` for Asset output. Keep the existing conversion into chamber-local spawn coordinates so forge2d receives the visible collision point.

- [ ] **Step 6: Run tests and commit**

Run the Task 4 tests. Expected: PASS, including lifecycle pause/resume and Reduce Motion direct handoff.

```bash
git add mobile/lib/theme_v2/home/today_output_overlay.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/test/theme_v2/home/today_output_overlay_test.dart mobile/test/theme_v2/home/today_living_surface_test.dart
git commit -m "feat: clarify today output travel"
```

### Task 5: Theme-Specific Dither and Watermark Contrast

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Modify: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Modify: intentional files under `mobile/test/theme_v2/home/goldens/`

**Interfaces:**
- Signal selects opacity `dark ? .32 : .40`.
- Asset selects opacity `dark ? .30 : .38`.
- Watermark selects count opacity `dark ? .14 : .07` and label opacity `dark ? .68 : .44`.

- [ ] **Step 1: Write failing brightness-specific component tests**

Pump each component under light and dark `ThemeData`. Read the rendered `TodayDitherField.config.opacity` and watermark `Text.style.color.a` values, asserting the exact four theme-specific pairs.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/home/today_signal_band_test.dart \
  test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: light Dither and dark watermark assertions FAIL because values are currently brightness-agnostic.

- [ ] **Step 3: Implement local brightness selection**

Use `Theme.of(context).brightness == Brightness.dark` at the three component boundaries. Do not change `ThemeV2Tokens`, shader uniforms other than opacity, field flow, or pressure energy.

- [ ] **Step 4: Run tests, update and inspect goldens**

Run the focused component tests, then:

```bash
cd mobile && flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Inspect every changed PNG and keep only intentional Today light/dark contrast changes.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/today_region_watermark.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart mobile/test/theme_v2/home/goldens
git commit -m "tune: calibrate today contrast by theme"
```

### Task 6: Integrated Regression and Foldable QA

**Files:**
- Modify only if a verified regression requires a scoped fix: files listed in Tasks 1-5.

**Interfaces:**
- Consumes all prior tasks and produces a debug APK installed on device `RFCY71B21YK`.

- [ ] **Step 1: Run the complete Today and shell regression suites**

Run:

```bash
cd mobile && flutter test test/theme_v2/home
cd mobile && flutter test \
  test/theme_v2/shell/theme_v2_shell_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Analyze only owned Dart files**

Run `flutter analyze` with the modified Dart file list from `git diff --name-only 0a3554d..HEAD`, excluding unrelated dirty reminder files. Expected: no issues.

- [ ] **Step 3: Build and install the debug APK**

Run:

```bash
cd mobile && flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true
```

Install on `RFCY71B21YK`, restore reverse port `8000`, force-stop, and launch `com.eureka.mindapp`.

- [ ] **Step 4: Verify device behavior**

On the device, verify both watermark destinations, Calendar/Library floating Top Dock, slow and fast four-direction Reka drag, one Signal rise, one Asset fall/collision, light Dither visibility, and dark watermark readability. Capture clean screenshots for light Today, dark Today, maximum upward pitch, Signal travel, and Asset handoff.

- [ ] **Step 5: Final status check**

Run `git status --short` and confirm unrelated dirty files remain unstaged. If no further code is needed, report the task commits, test counts, APK/device result, and screenshot paths.

## Self-Review Results

- Spec coverage: Tasks 1-6 cover symmetric entrances, root Top Dock, visible-body bounds, nonlinear pitch/yaw, longer output travel, theme-specific contrast, Reduce Motion, and device verification.
- Completeness scan: every step names its code, test command, expected result, and commit boundary.
- Type consistency: callback names, brightness values, body extents, pose multipliers, phase thresholds, and destination offset are introduced once and reused consistently.
- Scope: reminder, Bottom Sheet, Signal-detail, and service-layer work remains outside every stage/commit list.
