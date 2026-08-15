# Theme V2 Reka Capture, Agenda, Calendar, and Seed Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

**Goal:** Make the Home Reka visibly mirror the existing capture pipeline, redesign the compact and expanded Today agenda, stabilize Calendar Flow content surfaces, and slow output seeds with distance-based motion.

**Architecture:** Keep `CaptureActivityCoordinator` as the single source of truth and derive a small Home-only visual cue that is passed through the existing Reka scene/render pipeline. Replace fixed Home agenda positioning with minute-grouped data rendered by a scrollable timeline. Move Calendar Flow pressure/background ownership from record rows to a single opaque day surface. Replace normalized seed timing with a pure distance-based motion plan consumed by the overlay controller.

**Tech Stack:** Flutter/Dart, ChangeNotifier/ValueListenable, WebView-hosted Three.js renderer, widget/unit/golden tests.

**Design spec:** `docs/superpowers/specs/2026-08-15-theme-v2-reka-capture-agenda-seed-motion-design.md`

---

## Task 1: Add a typed capture cue for Home Reka

**Files:**

- Create: `mobile/lib/theme_v2/home/today_reka_capture_cue.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Test: `mobile/test/theme_v2/home/today_reka_capture_cue_test.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

**Step 1: Write failing cue mapping tests**

Cover idle, each active phase, and terminal phases. The Home model retains `CaptureActivityPhase` identity but exposes visual families such as listen, receive, process, success, empty, and failed.

```dart
expect(TodayRekaCaptureCue.fromSnapshot(const CaptureActivitySnapshot()),
    const TodayRekaCaptureCue.idle());
expect(cue.phase, CaptureActivityPhase.transcribing);
expect(cue.isActive, isTrue);
```

Run:

```bash
cd mobile && flutter test test/theme_v2/home/today_reka_capture_cue_test.dart
```

Expected: FAIL because the cue does not exist.

**Step 2: Implement the immutable cue**

Create `TodayRekaCaptureCue` with equality, `idle`, `fromSnapshot`, `phase`, `source`, `isRealtime`, and `isActive`. Do not copy coordinator timing or create a second state machine.

**Step 3: Write failing page wiring test**

Inject a fresh `CaptureActivityCoordinator` into `TodayDotExperimentPage`, publish a capture event, and verify the scene receives the new cue without rebuilding the page or replacing the Reka scene.

**Step 4: Wire the coordinator lifecycle**

Add optional `captureActivityCoordinator` to `TodayDotExperimentPage`; default to `CaptureActivityCoordinator.instance`, attach/detach listeners in lifecycle methods, and derive the cue from `.snapshot`. Pass the Shell-owned coordinator in `ThemeV2AppShell._pages` so the nav and Reka observe the same injected instance in tests and production.

**Step 5: Run focused tests and commit**

```bash
cd mobile && flutter test test/theme_v2/home/today_reka_capture_cue_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
git add mobile/lib/theme_v2/home/today_reka_capture_cue.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_reka_capture_cue_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat(theme-v2): mirror capture state on Home Reka"
```

## Task 2: Render distinct capture actions on Reka

**Files:**

- Modify: `mobile/lib/theme_v2/home/today_reka_scene.dart`
- Modify: `mobile/lib/theme_v2/home/today_dithered_reka.dart`
- Modify: `mobile/lib/theme_v2/home/today_reka_fallback_painter.dart`
- Modify: `mobile/assets/reka_dither/reka_dither_engine.js`
- Test: `mobile/test/theme_v2/home/today_reka_scene_test.dart`
- Test: `mobile/test/theme_v2/home/today_dithered_reka_test.dart`
- Test: `mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart`

**Step 1: Write failing propagation and fallback tests**

Extend `TodayRekaBuilder` assertions to include `TodayRekaCaptureCue`. Add fallback keys/semantics or test-visible eye geometry state so listening, processing, success, empty, and failed are distinguishable. Verify drag pose remains the supplied pose while capture changes the eyes.

**Step 2: Extend the renderer contract**

Pass the capture cue from `TodayRekaScene` to `TodayDitheredReka`. Add `_sendCapture()` and invoke it on renderer ready and cue changes:

```dart
controller.runJavaScript(
  'window.RekaDither.setCapture(${jsonEncode(cue.toRendererPayload())});',
);
```

The WebView must remain mounted; this is an in-place renderer mutation.

**Step 3: Implement the Three.js behavior**

Track eye pixel meshes instead of anonymous meshes and implement `setCapture(payload)`:

- `listening`: eyes widen and gently scan/pulse.
- `receiving`: short inward moving eye bands.
- `transcribing`: alternating horizontal terminal bars.
- `understanding`: focused narrowed eyes with a slow convergence.
- `organizing`: ordered stepping pixel rows.
- `done`: brief bright eye lift.
- `empty`: subdued flat eyes.
- `failed`: brief asymmetric/glitch eye shape, then coordinator dwell returns to idle.

Use terminal green for all eye states. Capture affects eyes and low-amplitude idle motion; drag continues to own body yaw/pitch. Existing production cues temporarily own body direction and then reveal the current capture state again.

**Step 4: Match the Flutter fallback**

Add the same visual families to the fallback painter/eye widgets without text or icons.

**Step 5: Run tests and commit**

```bash
cd mobile && flutter test test/theme_v2/home/today_reka_scene_test.dart test/theme_v2/home/today_dithered_reka_test.dart test/theme_v2/home/today_reka_renderer_assets_test.dart
git add mobile/lib/theme_v2/home/today_reka_scene.dart mobile/lib/theme_v2/home/today_dithered_reka.dart mobile/lib/theme_v2/home/today_reka_fallback_painter.dart mobile/assets/reka_dither/reka_dither_engine.js mobile/test/theme_v2/home/today_reka_scene_test.dart mobile/test/theme_v2/home/today_dithered_reka_test.dart mobile/test/theme_v2/home/today_reka_renderer_assets_test.dart
git commit -m "feat(theme-v2): animate Reka capture actions"
```

## Task 3: Redesign the compact next-schedule capsule

**Files:**

- Modify: `mobile/lib/theme_v2/home/today_next_capsule.dart`
- Modify: `mobile/lib/theme_v2/home/today_living_surface.dart`
- Test: `mobile/test/theme_v2/home/today_next_capsule_test.dart`
- Test: `mobile/test/theme_v2/home/today_living_surface_test.dart`

**Step 1: Write failing layout/content tests**

Assert that the next minute group renders a fixed left metadata column (time above countdown), a flexible right title column, and `+N` for remaining same-minute items. Assert empty state remains actionable. Add an alignment test showing the capsule right edge matches the living surface content/dither edge.

**Step 2: Implement the two-column capsule**

Keep the existing next-future-minute selection. Replace the three-line `Column` with a horizontal layout:

```text
10:30       Design review +2  ›
18 分钟后
```

Use one title, not a two-title summary; `+N` counts every additional item in that same minute. Preserve accessibility label and countdown clock updates.

**Step 3: Align with the Home content grid**

Remove the independent right inset/width assumption from the current placement. Use the same horizontal content inset as the dither containers and allow the capsule to occupy the intended right-aligned slot.

**Step 4: Test and commit**

```bash
cd mobile && flutter test test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_living_surface_test.dart
git add mobile/lib/theme_v2/home/today_next_capsule.dart mobile/lib/theme_v2/home/today_living_surface.dart mobile/test/theme_v2/home/today_next_capsule_test.dart mobile/test/theme_v2/home/today_living_surface_test.dart
git commit -m "feat(theme-v2): refine Today next schedule"
```

## Task 4: Replace the fixed fishbone agenda with a scrollable timeline

**Files:**

- Modify: `mobile/lib/theme_v2/home/home_agenda_panel.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`

**Step 1: Write failing timeline tests**

Build more than five minute groups and verify all groups are reachable by scrolling. Build one minute containing multiple todos/events and verify each canonical icon/title is present. Tap todo and event rows and verify the existing canonical detail-opening callbacks/routes are used. Verify completed todos receive completed styling.

**Step 2: Implement grouped timeline data**

Keep `supportedHomeAgendaItems` and minute grouping, but remove `_agendaSlots.take(5)`, `_FishboneConnectorPainter`, and fixed positioned cards. Render:

- sticky/static header with date, count, current time, close button;
- one vertical scroll view;
- each minute group as left time label + center spine/node + right group surface;
- all items as compact rows using resolved todo/event metadata icons and titles.

Use existing asset-detail opening logic rather than introducing a new detail sheet.

**Step 3: Preserve responsive geometry**

Derive columns from available width rather than hard-coded 411px coordinates. Keep the panel’s existing external contract and radius.

**Step 4: Test, update only the intended Home agenda goldens, and commit**

```bash
cd mobile && flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/theme_v2_home_page_test.dart
cd mobile && flutter test --update-goldens test/theme_v2/home/theme_v2_home_golden_test.dart
git add mobile/lib/theme_v2/home/home_agenda_panel.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart mobile/test/theme_v2/home/theme_v2_home_golden_test.dart mobile/test/theme_v2/home/goldens/home-agenda-411-light.png mobile/test/theme_v2/home/goldens/home-agenda-411-dark.png
git commit -m "feat(theme-v2): rebuild Home agenda timeline"
```

## Task 5: Stabilize Calendar Flow with one opaque surface per date

**Files:**

- Modify: `mobile/lib/theme_v2/calendar/calendar_components.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`
- Test: `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart`

**Step 1: Write failing surface ownership tests**

Assert a populated date has exactly one `ThemeV2DitherSourceReporter` for its day surface, record rows do not create nested pressure sources, and the date content uses an opaque `tokens.surface`. Scroll far enough to recycle/translate days and verify the same date surface and row backgrounds remain attached.

Add empty-state painter assertions for opaque surface, 1.25px border, and the approved light/dark hatch opacity.

**Step 2: Make record pressure reporting optional**

Change `CalendarRecordRow.ditherSourceId` to nullable. Wrap with `ThemeV2DitherSourceReporter` only where an individual row is intentionally a dither obstacle; Calendar Flow rows pass no ID.

**Step 3: Build a day-owned surface**

For populated Flow days, wrap the whole date content with one `ThemeV2DitherSourceReporter` keyed by date, then an opaque `tokens.surface` container with standard radius and border. Replace the inner `ListView(NeverScrollableScrollPhysics)` with a `Column`, ensuring the reporter discovers the outer Flow scrollable.

Keep time bands and lightweight row layout inside the surface. Dither remains visible around the date surface.

**Step 4: Deepen empty date treatment**

Set `_EmptyDayHatch` to opaque `tokens.surface`; border width 1.25 and muted alpha `.45` light / `.55` dark; hatch muted alpha `.24` light / `.30` dark with 9px spacing.

**Step 5: Test, update only Calendar Flow goldens, and commit**

```bash
cd mobile && flutter test test/theme_v2/calendar/calendar_flow_test.dart
cd mobile && flutter test --update-goldens test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
git add mobile/lib/theme_v2/calendar/calendar_components.dart mobile/lib/theme_v2/calendar/calendar_flow_view.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart mobile/test/theme_v2/calendar/goldens/calendar-flow-*.png
git commit -m "fix(theme-v2): anchor Calendar Flow day surfaces"
```

## Task 6: Make output seed timing distance-based

**Files:**

- Create: `mobile/lib/theme_v2/home/today_output_motion_plan.dart`
- Modify: `mobile/lib/theme_v2/home/today_output_overlay.dart`
- Test: `mobile/test/theme_v2/home/today_output_motion_plan_test.dart`
- Test: `mobile/test/theme_v2/home/today_output_overlay_test.dart`

**Step 1: Write failing pure timing tests**

Test the approved constants and distance boundaries:

```dart
expect(plan.chargeDuration, const Duration(milliseconds: 300));
expect(short.travelDuration, const Duration(milliseconds: 1200));
expect(long.travelDuration, const Duration(milliseconds: 2400));
expect(mid.travelDuration.inMilliseconds,
    closeTo(mid.distance / 280 * 1000, 1));
expect(plan.handoffRecoveryDuration, const Duration(milliseconds: 350));
```

Also verify reduce-motion uses the short existing path and never starts a long travel.

**Step 2: Implement `TodayOutputMotionPlan`**

Create a pure model from source/destination distance. Expose total duration and normalized phase boundaries derived from charge, travel, and handoff/recovery durations. Clamp travel to 1200–2400ms at 280 logical px/s.

**Step 3: Start only after layout is known**

Do not start the controller in `initState`. In `LayoutBuilder`, calculate the clamped source, detached point, and destination; install/update the motion plan once; then start animation in a post-frame callback. This prevents a zero-destination first frame and makes signal/asset speeds perceptible.

Use the plan’s phase boundaries for charge, travel, unfold/handoff, and recovery. Keep the existing first-column signal handoff and asset-floor handoff behavior.

**Step 4: Test and commit**

```bash
cd mobile && flutter test test/theme_v2/home/today_output_motion_plan_test.dart test/theme_v2/home/today_output_overlay_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart
git add mobile/lib/theme_v2/home/today_output_motion_plan.dart mobile/lib/theme_v2/home/today_output_overlay.dart mobile/test/theme_v2/home/today_output_motion_plan_test.dart mobile/test/theme_v2/home/today_output_overlay_test.dart
git commit -m "feat(theme-v2): slow output seeds by distance"
```

The reported red-screen flash during downward travel is explicitly excluded until reproducible timing is supplied. If it appears during verification, capture evidence and report it without speculative fixes.

## Task 7: Integrated verification and device handoff

**Files:**

- Modify only if failures demand scoped fixes.

**Step 1: Format and inspect the diff**

```bash
cd mobile && dart format lib/theme_v2/home lib/theme_v2/calendar lib/theme_v2/shell test/theme_v2/home test/theme_v2/calendar
git diff --check
git status --short
```

Never stage the existing reminder, Reka signal Bottom Sheet, service, or unrelated dirty test changes.

**Step 2: Run focused suites**

```bash
cd mobile && flutter test test/theme_v2/home test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
```

**Step 3: Analyze only changed Dart files**

```bash
cd mobile && flutter analyze lib/theme_v2/home lib/theme_v2/calendar lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home test/theme_v2/calendar/calendar_flow_test.dart
```

Expected: no issues.

**Step 4: Build, install, and launch on the connected phone**

```bash
cd mobile && flutter devices
cd mobile && flutter build apk --debug
cd mobile && flutter run -d RFCY71B21YK --debug
```

Verify on device:

- nav capture state and Reka eye action change together;
- drag body orientation remains stronger than capture body motion;
- output production briefly redirects Reka, then capture eyes resume;
- next schedule aligns right and shows time/countdown left, title/`+N` right;
- agenda scrolls through every same-minute group with icons/titles;
- Calendar Flow date surfaces remain opaque and attached while scrolling;
- signal and asset seeds are visibly trackable at different distances;
- no new red-screen flash is introduced, while the existing deferred report is documented if reproduced.

**Step 5: Final exact-scope commit if verification required fixes**

```bash
git diff --check
git status --short
git commit -m "test(theme-v2): verify Home interaction revamp"
```

