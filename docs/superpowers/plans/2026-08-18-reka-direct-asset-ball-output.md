# Reka Direct Asset Ball Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the downward terminal Seed with a normal final Asset ball that emerges behind Reka and falls directly into the physics field.

**Architecture:** Keep the coordinator phases and upward signal renderer, but split the overlay visual by output kind. Pass the actual Asset visual into the overlay and hand its final center plus velocity into the bubble field so the same material continues into physics.

**Tech Stack:** Flutter/Dart animation, existing Forge2D bubble field, flutter_test.

## Global Constraints

- Upward signal behavior remains unchanged.
- Downward Asset output never paints a terminal Seed or trail.
- The Asset ball starts at normal final size behind Reka.
- Physics handoff occurs exactly once without a replacement flash.
- Reduced motion fades the Asset into the field.
- Use TDD and commit each independently passing task.

---

### Task 1: Model an Asset handoff with velocity

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Test: `mobile/test/theme_v2/home/today_output_overlay_test.dart`
- Test: `mobile/test/theme_v2/home/today_asset_bubble_field_test.dart`

**Interfaces:**
- Produces: `TodayAssetHandoff(center: Offset, velocity: Offset)`.
- Changes: `TodayOutputOverlay.onAssetHandoff: ValueChanged<TodayAssetHandoff>?`.
- Changes: `ThemeV2AssetBubbleField.spawnStates: Map<String, TodayAssetHandoff>`.

- [ ] **Step 1: Write failing handoff tests**

```dart
testWidgets('asset handoff contains one downward velocity', (tester) async {
  TodayAssetHandoff? handoff;
  await tester.pumpWidget(assetOverlayHarness(
    onAssetHandoff: (value) => handoff = value,
  ));
  await tester.pumpAndSettle();
  expect(handoff, isNotNull);
  expect(handoff!.velocity.dy, greaterThan(0));
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/today_asset_bubble_field_test.dart`

Expected: FAIL because the handoff only exposes an `Offset` center.

- [ ] **Step 3: Implement the handoff value and physics spawn velocity**

```dart
@immutable
class TodayAssetHandoff {
  const TodayAssetHandoff({required this.center, required this.velocity});
  final Offset center;
  final Offset velocity;
}
```

At handoff, compute velocity from the last segment of the gravity curve. When creating the Forge2D body for a newly spawned Asset, convert that pixel velocity to world units and assign `body.linearVelocity` exactly once. Remove the spawn state after insertion.

- [ ] **Step 4: Run focused tests**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/today_asset_bubble_field_test.dart`

Expected: PASS with one consumed spawn state.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/home/today_output_overlay.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/test/theme_v2/home/today_output_overlay_test.dart mobile/test/theme_v2/home/today_asset_bubble_field_test.dart
git commit -m "feat: preserve velocity across asset output handoff"
```

### Task 2: Render a final Asset ball instead of a Seed

**Files:**
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Test: `mobile/test/theme_v2/home/today_output_overlay_test.dart`

**Interfaces:**
- Produces: public `ThemeV2AssetBubbleVisual(asset:, skills:, diameter:, motion:)`.
- Extends: `TodayOutputOverlay.assetVisual: Widget?`.

- [ ] **Step 1: Write failing visual tests**

```dart
testWidgets('asset output paints final bubble and no terminal seed or trail', (tester) async {
  await tester.pumpWidget(assetOverlayHarness(
    assetVisual: const SizedBox(key: ValueKey('final-ball')),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byKey(const ValueKey('final-ball')), findsOneWidget);
  expect(find.byKey(const ValueKey('today-output-seed')), findsNothing);
  expect(find.byKey(const ValueKey('today-output-trail-0')), findsNothing);
});
```

- [ ] **Step 2: Run the test and verify failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_overlay_test.dart -n 'asset output paints final bubble'`

Expected: FAIL because both output kinds use `_TerminalSeed`.

- [ ] **Step 3: Split signal and Asset rendering**

Keep the current signal trail/Seed/unfold branch unchanged. In the Asset branch:

```dart
final progress = ((raw - plan.chargeEnd) /
        (plan.travelEnd - plan.chargeEnd)).clamp(0.0, 1.0);
final gravity = progress * progress;
final center = Offset(
  detached.dx,
  lerpDouble(detached.dy, destination.dy, gravity)!,
);
return Positioned(
  key: ValueKey('today-output-asset-ball-${widget.item.id}'),
  left: center.dx - assetDiameter / 2,
  top: center.dy - assetDiameter / 2,
  width: assetDiameter,
  height: assetDiameter,
  child: widget.assetVisual!,
);
```

Use the matching `PoolAsset` and `skills` in `TodayLivingSurface` to build the same public bubble visual used by the physics field. Insert the Asset overlay below the Reka scene layer so the ball starts behind the robot and becomes visible while falling.

- [ ] **Step 4: Run output and home tests**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/today_living_surface_test.dart`

Expected: PASS; signal snapshots remain unchanged.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/today_output_overlay.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/test/theme_v2/home/today_output_overlay_test.dart
git commit -m "feat: emit final asset balls from reka"
```

### Task 3: Tune Reka cue and reduced-motion behavior

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_output_motion_plan.dart`
- Modify: `mobile/lib/theme_v2/home/today_dithered_reka.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Test: `mobile/test/theme_v2/home/today_output_motion_plan_test.dart`
- Test: `mobile/test/theme_v2/home/today_dithered_reka_test.dart`

**Interfaces:**
- Consumes: existing `TodayOutputCue` phases.
- Guarantees: Asset emit/handoff uses a visibly downward Reka rotation/eye offset.

- [ ] **Step 1: Write failing cue and duration tests**

```dart
test('asset travel is slow enough to perceive and accelerates into handoff', () {
  final plan = todayOutputMotionPlan(
    kind: TodayOutputKind.asset,
    source: const Offset(200, 320),
    destination: const Offset(200, 720),
    reduceMotion: false,
  );
  expect(
    plan.travelDuration,
    greaterThanOrEqualTo(const Duration(milliseconds: 900)),
  );
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/home/today_output_motion_plan_test.dart test/theme_v2/home/today_dithered_reka_test.dart`

Expected: FAIL because motion planning has no output kind and Asset timing is shared with signals.

- [ ] **Step 3: Tune Asset-only timing and Reka look-down**

Extend `todayOutputMotionPlan` with `TodayOutputKind kind` so signal timing stays unchanged. Set Asset travel duration from distance with a 900–1800 ms clamp. Increase downward cue rotation/eye offset during `emit` and `handoff`; add a short production pulse during `charge`. In reduced motion, skip travel, fade the final ball at the field boundary, and hand off once.

- [ ] **Step 4: Run all home tests and analyze**

Run: `cd mobile && flutter test test/theme_v2/home`

Run: `cd mobile && flutter analyze lib/theme_v2/home test/theme_v2/home`

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/home/today_output_motion_plan.dart mobile/lib/theme_v2/home/today_dithered_reka.dart mobile/lib/theme_v2/home/today_reka_scene.dart mobile/test/theme_v2/home/today_output_motion_plan_test.dart mobile/test/theme_v2/home/today_dithered_reka_test.dart
git commit -m "fix: make reka asset production perceptible"
```
