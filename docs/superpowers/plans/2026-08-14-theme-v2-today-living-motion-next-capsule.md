# Theme V2 Today Living Motion and Next Capsule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the provisional Today header and fixed Signal pager with a date + live Next capsule, three continuous Reka discovery lanes, paired `Reka 发现` / `Reka 生成` watermarks, and lifecycle-aware Dither motion that follows Reka and animates Signal and Asset materials.

**Architecture:** Keep Today orchestration in `TodayLivingSurface`, but split the new header, watermark, and lane behavior into focused widgets. One page-level `AnimationController` drives all repeating Dither and lane phases; identity-derived seeds keep objects visually independent without per-object controllers. Existing output coordination and Asset physics stay authoritative for production handoff and collisions.

**Tech Stack:** Flutter/Dart, Material widgets, `CustomPainter`, `AnimationController`, Flutter widget/unit tests, existing Theme V2 tokens and Today repositories.

## Global Constraints

- Work only in the existing `首页-revamp` worktree and preserve unrelated uncommitted changes.
- Light-mode Today remains the only rollout surface; do not add Dark Mode or apply Dither to other pages.
- Do not add a full-page matrix/dot background or an independently interactive point field.
- The header displays `M月D日 · 周X`; it does not display `今日`.
- Next never shows `进行中`; reaching the displayed local minute immediately advances the whole minute group.
- Signals use at most three continuous left-to-right lanes and are not draggable.
- Watermark labels are exactly `Reka 发现` and `Reka 生成`.
- Reduce Motion stops lane travel and repeating Dither drift while preserving data changes and direct handoffs.
- Existing Asset gravity, tilt, collision, dragging, and hit-target behavior remain unchanged.

---

## File Structure

- Create `mobile/lib/theme_v2/home/today_next_capsule.dart`: date/Next selection helpers, countdown formatter, minute timer, and capsule UI.
- Create `mobile/lib/theme_v2/home/today_region_watermark.dart`: shared decorative count + label treatment with left/right alignment.
- Modify `mobile/lib/theme_v2/home/today_dither_material.dart`: accept a shared animation phase and derive stable drift/breath from identity.
- Rewrite `mobile/lib/theme_v2/home/today_signal_band.dart`: stable three-lane allocation, continuous travel, tap pause, and discovery watermark.
- Modify `mobile/lib/theme_v2/home/today_living_surface.dart`: own the shared animation clock, date/Next row, Reka-following field, and motion wiring.
- Modify `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`: consume the shared phase and use the shared `Reka 生成` watermark.
- Modify `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`: expose Agenda navigation and pass a real/frozen clock seam.
- Modify `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`: route Next capsule taps to Calendar/Today Agenda.
- Extend `mobile/test/theme_v2/home/today_dither_material_test.dart` and `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`.
- Create `mobile/test/theme_v2/home/today_next_capsule_test.dart` and `mobile/test/theme_v2/home/today_signal_band_test.dart`.
- Extend `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart` and `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`.

---

### Task 1: Shared Dynamic Dither and Region Watermark

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_dither_material.dart`
- Create: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Test: `mobile/test/theme_v2/home/today_dither_material_test.dart`

**Interfaces:**
- Consumes: optional page-level `Animation<double>` whose value repeats from `0` to `1`.
- Produces: `TodayDitherMaterial.motion`, `TodayDitherMaterial.flow`, `todayDitherDrift(...)`, and `TodayRegionWatermark(count:, label:, alignment:)`.

- [ ] **Step 1: Write failing deterministic motion and watermark tests**

```dart
test('identity seed offsets Dither drift without changing the mask', () {
  expect(todayDitherDrift(seed: 1, phase: .25, flow: 1),
      isNot(equals(todayDitherDrift(seed: 2, phase: .25, flow: 1))));
  expect(todayDitherDrift(seed: 1, phase: .25, flow: 0), Offset.zero);
});

testWidgets('region watermark is decorative and supports opposite anchors',
    (tester) async {
  await tester.pumpWidget(const MaterialApp(home: Stack(children: [
    TodayRegionWatermark(count: 5, label: 'Reka 发现', alignment: Alignment.bottomLeft),
    TodayRegionWatermark(count: 12, label: 'Reka 生成', alignment: Alignment.bottomRight),
  ])));
  expect(find.text('Reka 发现'), findsOneWidget);
  expect(find.text('Reka 生成'), findsOneWidget);
  expect(find.byType(IgnorePointer), findsNWidgets(2));
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `cd mobile && flutter test test/theme_v2/home/today_dither_material_test.dart`

Expected: compilation fails because `todayDitherDrift` and `TodayRegionWatermark` do not exist.

- [ ] **Step 3: Add the shared motion API and painter repaint wiring**

Implement the public shape below and keep existing call sites source-compatible:

```dart
Offset todayDitherDrift({
  required int seed,
  required double phase,
  required double flow,
}) {
  if (flow == 0) return Offset.zero;
  final offset = (seed & 0xFF) / 255;
  final angle = (phase + offset) * math.pi * 2;
  return Offset(math.sin(angle), math.cos(angle * .73)) * flow;
}

class TodayDitherMaterial extends StatelessWidget {
  const TodayDitherMaterial({
    super.key,
    required this.shape,
    required this.color,
    required this.strength,
    this.seed = 0,
    this.step = 4,
    this.dotSize = 2.2,
    this.motion,
    this.flow = 0,
    this.child,
  });
  final Animation<double>? motion;
  final double flow;
}
```

`TodayDitherPainter` must call `super(repaint: motion)`, offset its grid by `todayDitherDrift`, and apply a seed-offset low-amplitude density breath. Mask geometry remains unchanged.

- [ ] **Step 4: Add the shared decorative watermark**

```dart
class TodayRegionWatermark extends StatelessWidget {
  const TodayRegionWatermark({
    super.key,
    required this.count,
    required this.label,
    required this.alignment,
  });
  final int count;
  final String label;
  final Alignment alignment;
}
```

Return `SizedBox.shrink()` for zero. For positive counts, use `IgnorePointer` + `ExcludeSemantics`, Theme V2 accent at approximately `.07` for the number and `.28` for the label, `112`-scale Geist count typography, and monospaced 9px label typography.

- [ ] **Step 5: Run and format**

Run: `cd mobile && dart format lib/theme_v2/home/today_dither_material.dart lib/theme_v2/home/today_region_watermark.dart test/theme_v2/home/today_dither_material_test.dart`

Run: `cd mobile && flutter test test/theme_v2/home/today_dither_material_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the primitive**

```bash
git add mobile/lib/theme_v2/home/today_dither_material.dart mobile/lib/theme_v2/home/today_region_watermark.dart mobile/test/theme_v2/home/today_dither_material_test.dart
git commit -m "feat: add living today dither primitives"
```

---

### Task 2: Date Header and Live Next Capsule

**Files:**
- Create: `mobile/lib/theme_v2/home/today_next_capsule.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Create: `mobile/test/theme_v2/home/today_next_capsule_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Consumes: canonical `List<ChainItem>`, local `DateTime now`, optional `ValueListenable<DateTime>` test clock, and `VoidCallback onOpenAgenda`.
- Produces: `todayNextGroup`, `todayCountdownLabel`, and `TodayNextCapsule`.

- [ ] **Step 1: Write failing helper and widget tests**

Cover an item 20 seconds away (`1 分钟后`), exact-minute advancement, same-minute `+N`, empty `今天暂无安排`, absence of `今日`, and a tap callback. Use a `ValueNotifier<DateTime>` to advance the clock without waiting.

```dart
final clock = ValueNotifier(DateTime(2026, 8, 14, 14, 29, 40));
await tester.pumpWidget(host(TodayNextCapsule(
  items: items,
  now: clock.value,
  clock: clock,
  onOpenAgenda: () => opened++,
)));
expect(find.text('1 分钟后'), findsOneWidget);
clock.value = DateTime(2026, 8, 14, 14, 30);
await tester.pump();
expect(find.text('下一项'), findsOneWidget);
```

- [ ] **Step 2: Run the tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart`

Expected: compilation fails because `TodayNextCapsule` is missing and the old test expects the empty capsule to be absent.

- [ ] **Step 3: Implement pure selection and countdown helpers**

```dart
List<ChainItem> todayNextGroup(List<ChainItem> items, DateTime now) {
  final future = items.where((item) => item.timed && item.at.isAfter(now)).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  if (future.isEmpty) return const [];
  final minute = DateTime(future.first.at.year, future.first.at.month,
      future.first.at.day, future.first.at.hour, future.first.at.minute);
  return future.where((item) =>
    item.at.year == minute.year && item.at.month == minute.month &&
    item.at.day == minute.day && item.at.hour == minute.hour &&
    item.at.minute == minute.minute).toList(growable: false);
}

String todayCountdownLabel(DateTime target, DateTime now) {
  final seconds = target.difference(now).inSeconds;
  final minutes = math.max(1, (seconds / 60).ceil());
  if (minutes < 60) return '$minutes 分钟后';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours 小时后' : '$hours 小时 $remainder 分钟后';
}
```

- [ ] **Step 4: Implement the stable capsule and production timer**

`TodayNextCapsule` listens to the injected clock in tests. Without one it owns a `Timer.periodic(const Duration(seconds: 15), ...)` and samples `DateTime.now()`; cancel it in `dispose`. Use a 44px minimum tap target, stable capsule width, populated/empty semantics, one-line ellipsis, exact `今天暂无安排` copy, and no `进行中` branch.

- [ ] **Step 5: Replace the header and wire Agenda navigation**

In `TodayLivingSurface`, replace `_TodayHeading` and `_NextSchedule` with a single row containing localized date text and `TodayNextCapsule`. Add `onOpenAgenda` and optional clock parameters through `TodayDotExperimentPage`.

In the production shell pass:

```dart
onOpenAgenda: () => _selectDestination(1),
```

The shell test must tap the capsule and assert `ThemeV2CalendarPage` becomes active.

- [ ] **Step 6: Run focused tests and format**

Run: `cd mobile && dart format lib/theme_v2/home/today_next_capsule.dart lib/theme_v2/home/today_living_surface.dart lib/theme_v2/home/today_dot_experiment_page.dart lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart`

Run: `cd mobile && flutter test test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit the header slice**

```bash
git add mobile/lib/theme_v2/home/today_next_capsule.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_next_capsule_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "feat: add today next capsule"
```

---

### Task 3: Three Continuous Reka Discovery Lanes

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Create: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

**Interfaces:**
- Consumes: stable priority-ordered Signals, shared `Animation<double> motion`, Reduce Motion, and `Future<void> Function(TodayRekaItem)` detail opener.
- Produces: persistent ID-to-lane assignment, at most three visible lanes, and left `Reka 发现` watermark.

- [ ] **Step 1: Write failing lane tests**

Test 1/2/3 Signals use distinct lanes, 5 Signals still produce three lane keys, refresh with the same IDs preserves lane keys, no duplicate Signal text is created to fill lanes, the watermark count is `5`, and Reduce Motion stops position changes after pumping.

```dart
expect(find.byKey(const ValueKey('today-signal-lane-0')), findsOneWidget);
expect(find.byKey(const ValueKey('today-signal-lane-1')), findsOneWidget);
expect(find.byKey(const ValueKey('today-signal-lane-2')), findsOneWidget);
expect(find.text('Reka 发现'), findsOneWidget);
expect(find.text('5'), findsOneWidget);
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_signal_band_test.dart`

Expected: the old `PageView` has no lane or watermark keys.

- [ ] **Step 3: Replace `PageView` with a stateful lane allocator**

Maintain `Map<String, int> _laneById`. Existing IDs keep their lane. New IDs choose the lane with the smallest current load, starting from `id.hashCode.abs() % 3` to break ties. Remove departed IDs after reconciliation.

Use these stable lane bands:

```dart
const _laneSpeeds = <double>[24, 31, 27];
const _laneGaps = <double>[72, 104, 88];
```

Inside one `AnimatedBuilder(animation: motion)`, derive each strip's x-coordinate from phase, viewport width, lane speed, stable item offset, strip width, and gap. Wrap only after the strip clears the right edge. In Reduce Motion, place at most one strip statically in each lane.

- [ ] **Step 4: Add compact strip material and tap pause**

Use a 44px minimum strip target with kind label/icon plus a single-line title. The whole strip is Dithered; text remains solid. `onTapDown` snapshots that Signal's current x-coordinate, `onTapCancel` resumes it, and `onTap` awaits the Future detail callback before resuming in `finally`.

- [ ] **Step 5: Add the left discovery watermark**

Render below all strips:

```dart
TodayRegionWatermark(
  count: items.length,
  label: 'Reka 发现',
  alignment: Alignment.bottomLeft,
)
```

- [ ] **Step 6: Run focused and integration tests**

Run: `cd mobile && dart format lib/theme_v2/home/today_signal_band.dart lib/theme_v2/home/today_living_surface.dart test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart`

Run: `cd mobile && flutter test test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit the discovery lanes**

```bash
git add mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat: animate reka discovery lanes"
```

---

### Task 4: Reka-Following Field and Dynamic Reka Generation Material

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/test/theme_v2/home/today_output_overlay_test.dart`

**Interfaces:**
- Consumes: the shared page motion and `rekaCenter` already supplied by `TodayRekaScene`.
- Produces: moving local field, independently seeded bubble Dither, `TodayOutputOverlay.motion`, right `Reka 生成` watermark, and unchanged production handoff/physics APIs.

- [ ] **Step 1: Write failing field, watermark, and stable-geometry tests**

Pump with two Reka centers and assert the field center follows. Pump the shared phase and assert the bubble's `TodayDitherPainter` repaints while its `theme-v2-asset-bubble-*` target rect remains unchanged. Assert `今日生成` is absent and `Reka 生成` plus the canonical true count are present.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/today_output_overlay_test.dart`

Expected: the field still fills the whole content area and the Asset watermark still says `今日生成`.

- [ ] **Step 3: Own one lifecycle-aware motion controller in `TodayLivingSurface`**

Add `SingleTickerProviderStateMixin` and `WidgetsBindingObserver`. Create one 120-second repeating `AnimationController`. Start only when `widget.active`, app lifecycle is resumed, and Reduce Motion is false. Stop without resetting when inactive/backgrounded; resume from the retained value.

- [ ] **Step 4: Position the local field around Reka**

Replace `Positioned.fill` with a roughly 280px square `AnimatedPositioned` centered on `widget.rekaCenter`, using 140ms `easeOutCubic` lag or zero duration in Reduce Motion. Pass the shared phase to the field Dither and keep its strength below all object materials.

- [ ] **Step 5: Drive Asset Dither and replace the watermark**

Add `Animation<double>? motion` to `ThemeV2AssetBubbleField`, `_ThemeV2CompactAssetGrid`, and `_ThemeV2BubbleVisual`. Pass identity-derived seed (`asset.id.hashCode`) and low `flow` to each `TodayDitherMaterial` without changing the physics field, target rectangles, transforms, or gestures.

Replace the inline Asset number/`今日生成` widgets with:

```dart
TodayRegionWatermark(
  count: widget.trueCount,
  label: 'Reka 生成',
  alignment: Alignment.bottomRight,
)
```

- [ ] **Step 6: Keep production overlays compatible with shared motion**

Add `final Animation<double>? motion` to `TodayOutputOverlay`, pass it from `TodayLivingSurface`, and supply it to every Signal trail and output-body `TodayDitherMaterial`. Keep the overlay's bounded 620ms handoff and completion callback unchanged. Reduce Motion continues using the 140ms no-travel reveal.

- [ ] **Step 7: Run focused tests and format**

Run: `cd mobile && dart format lib/theme_v2/home/today_living_surface.dart lib/theme_v2/home/theme_v2_asset_bubble_field.dart lib/theme_v2/home/today_output_overlay.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/today_output_overlay_test.dart`

Run: `cd mobile && flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/today_output_overlay_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit the living material slice**

```bash
git add mobile/lib/theme_v2/home/today_living_surface.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/today_output_overlay.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/today_output_overlay_test.dart
git commit -m "feat: animate today reka materials"
```

---

### Task 5: Full Verification and Connected-Device Handoff

**Files:**
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_dither_material.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_next_capsule.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify, only if verification finds an in-scope regression: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`

**Interfaces:**
- Consumes: completed Today implementation.
- Produces: passing focused suite, clean targeted analysis, and an installed debug APK for user review.

- [ ] **Step 1: Run all affected Today and shell tests**

Run:

```bash
cd mobile && flutter test \
  test/theme_v2/home/today_dither_material_test.dart \
  test/theme_v2/home/today_next_capsule_test.dart \
  test/theme_v2/home/today_signal_band_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_output_coordinator_test.dart \
  test/theme_v2/home/today_output_overlay_test.dart \
  test/theme_v2/home/theme_v2_asset_bubble_field_test.dart \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run targeted static analysis**

Run:

```bash
cd mobile && flutter analyze \
  lib/theme_v2/home/today_dither_material.dart \
  lib/theme_v2/home/today_region_watermark.dart \
  lib/theme_v2/home/today_next_capsule.dart \
  lib/theme_v2/home/today_signal_band.dart \
  lib/theme_v2/home/today_living_surface.dart \
  lib/theme_v2/home/theme_v2_asset_bubble_field.dart \
  lib/theme_v2/home/today_output_overlay.dart \
  lib/theme_v2/home/today_dot_experiment_page.dart \
  lib/theme_v2/shell/theme_v2_app_shell.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Build and install on the connected Android device**

Run: `cd mobile && flutter devices`

Expected: device `RFCY71B21YK` is connected.

Run: `cd mobile && flutter build apk --debug`

Run:

```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$ADB -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s RFCY71B21YK reverse tcp:8000 tcp:8000
$ADB -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$ADB -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: install succeeds, reverse succeeds, and the launcher opens `com.eureka.mindapp` on Today.

- [ ] **Step 4: Perform device checks**

Verify date/capsule spacing, empty and populated Next, three independent left-to-right lanes, left/right watermark stagger, Reka field following drag, calm local Dither motion, Signal tap reliability, Asset collision stability, Dock clearance, background/resume, and Android Reduce Motion.

- [ ] **Step 5: Commit only verification fixes**

If fixes were required, stage only the in-scope paths that changed and commit:

```bash
git add mobile/lib/theme_v2/home/today_dither_material.dart mobile/lib/theme_v2/home/today_region_watermark.dart mobile/lib/theme_v2/home/today_next_capsule.dart mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/today_output_overlay.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_dither_material_test.dart mobile/test/theme_v2/home/today_next_capsule_test.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/home/today_output_overlay_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "fix: polish today living motion"
```

If no fixes were required, do not create an empty commit.
