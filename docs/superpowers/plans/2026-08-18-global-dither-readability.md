# Global Dither Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render one continuous Dither background behind page chrome while isolating dense content so grids and text remain crisp.

**Architecture:** Move page-level Dither ownership into the Theme V2 shell, make top Nav and bottom Dock translucent glass over that shared field, and use a shared high-opacity content surface for dense regions. Remove nested calendar/library page backgrounds.

**Tech Stack:** Flutter, Dart, FragmentProgram shader, Material, flutter_test, golden tests.

## Global Constraints

- One global Dither field covers top Nav, page body, and bottom Dock.
- Top Nav and Dock do not create separate Dither painters.
- Dither intensity stays globally consistent in light and dark modes.
- Dense text/grid/list regions use high-opacity content surfaces.
- Reduced motion freezes the field without reducing foreground contrast.
- Use TDD and commit each independently passing task.

---

### Task 1: Add a global Dither configuration and shell ownership

**Files:**
- Modify: `mobile/lib/theme_v2/foundation/theme_v2_dither_field.dart`
- Modify: `mobile/lib/theme_v2/foundation/theme_v2_dither_surface.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Test: `mobile/test/theme_v2/foundation/theme_v2_dither_surface_test.dart`
- Create: `mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart`

**Interfaces:**
- Produces: `const ThemeV2DitherFieldConfig.global()`.
- Extends: `ThemeV2PageScaffold(ditherActive: bool = true)`.
- Guarantees: one `ThemeV2DitherField.shaderSurfaceKey` in a rendered primary shell.

- [ ] **Step 1: Write failing shell ownership tests**

```dart
testWidgets('page scaffold owns one dither behind body and chrome', (tester) async {
  await tester.pumpWidget(shellHarness());
  expect(find.byKey(ThemeV2DitherField.shaderSurfaceKey), findsOneWidget);
  final dither = tester.getTopLeft(find.byKey(ThemeV2DitherField.shaderSurfaceKey));
  final topNav = tester.getTopLeft(find.byKey(const ValueKey('test-top-nav')));
  expect(dither.dy, lessThanOrEqualTo(topNav.dy));
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/foundation/theme_v2_dither_surface_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart`

Expected: FAIL because page scaffold does not own a Dither surface and the shell test file is absent.

- [ ] **Step 3: Implement shell-level Dither**

```dart
const ThemeV2DitherFieldConfig.global({
  this.waveColor = const Color(0xFF69717B),
  this.colorNum = 4,
  this.pixelSize = 4,
  this.waveAmplitude = .24,
  this.waveFrequency = 2.7,
  this.waveSpeed = .032,
  this.flowDirection = const Offset(.72, .34),
  this.opacity = .28,
  this.displacementStrength = .84,
});
```

Wrap the complete `ThemeV2PageScaffold` safe-area composition—including injected top Nav and Dock—in one `ThemeV2DitherSurface`. Stop overriding the config opacity inside `ThemeV2DitherSurface`; choose light/dark opacity in the global configuration. Remove the outer `ThemeV2DitherSurface` from Calendar and Library.

- [ ] **Step 4: Run shell, Calendar, and Library tests**

Run: `cd mobile && flutter test test/theme_v2/foundation/theme_v2_dither_surface_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart test/theme_v2/library/library_repository_test.dart`

Expected: PASS with one shell Dither painter.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/foundation/theme_v2_dither_field.dart mobile/lib/theme_v2/foundation/theme_v2_dither_surface.dart mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/test/theme_v2/foundation/theme_v2_dither_surface_test.dart mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart
git commit -m "feat: move dither into the global page shell"
```

### Task 2: Make top Nav and bottom Dock glass surfaces

**Files:**
- Create: `mobile/lib/theme_v2/shell/theme_v2_glass_chrome.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_global_top_nav_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart`

**Interfaces:**
- Produces: `ThemeV2GlassChrome(borderRadius:, child:, elevation:)`.

- [ ] **Step 1: Write failing glass material tests**

```dart
testWidgets('floating top nav and dock use shared glass chrome', (tester) async {
  await tester.pumpWidget(chromeHarness());
  expect(find.byType(ThemeV2GlassChrome), findsNWidgets(2));
  expect(find.byType(BackdropFilter), findsNWidgets(2));
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/shell/theme_v2_global_top_nav_test.dart test/theme_v2/shell/theme_v2_floating_dock_test.dart`

Expected: FAIL because `ThemeV2GlassChrome` is undefined.

- [ ] **Step 3: Implement the shared glass material**

```dart
class ThemeV2GlassChrome extends StatelessWidget {
  const ThemeV2GlassChrome({
    super.key,
    required this.borderRadius,
    required this.child,
    this.elevation = 8,
  });
  final BorderRadius borderRadius;
  final Widget child;
  final double elevation;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Material(
        elevation: elevation,
        color: context.themeV2.surface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .88 : .82,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: context.themeV2.border),
        ),
        child: child,
      ),
    ),
  );
}
```

Use it in both floating chrome components while preserving keys, semantics, dimensions, and hit targets.

- [ ] **Step 4: Run tests and analysis**

Run: `cd mobile && flutter test test/theme_v2/shell`

Run: `cd mobile && flutter analyze lib/theme_v2/shell test/theme_v2/shell`

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_glass_chrome.dart mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart mobile/test/theme_v2/shell/theme_v2_global_top_nav_test.dart mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart
git commit -m "feat: render theme v2 chrome as glass"
```

### Task 3: Isolate dense Calendar content from Dither

**Files:**
- Create: `mobile/lib/theme_v2/foundation/theme_v2_content_surface.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_day_detail.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_components.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_schedule_grid_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`

**Interfaces:**
- Produces: `ThemeV2ContentSurface(opacity: ThemeV2ContentOpacity.dense, child:)`.

- [ ] **Step 1: Write failing Calendar isolation tests**

```dart
testWidgets('schedule grid owns an opaque dense content surface', (tester) async {
  await tester.pumpWidget(scheduleHarness());
  final surface = tester.widget<ThemeV2ContentSurface>(
    find.byKey(const ValueKey('calendar-schedule-content-surface')),
  );
  expect(surface.opacity, ThemeV2ContentOpacity.dense);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/calendar/calendar_schedule_grid_test.dart test/theme_v2/calendar/calendar_flow_test.dart`

Expected: FAIL because the content-surface contract does not exist.

- [ ] **Step 3: Implement content isolation and contrast floors**

```dart
enum ThemeV2ContentOpacity { dense, card }

class ThemeV2ContentSurface extends StatelessWidget {
  const ThemeV2ContentSurface({
    super.key,
    required this.child,
    this.opacity = ThemeV2ContentOpacity.dense,
  });
  final Widget child;
  final ThemeV2ContentOpacity opacity;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.themeV2.surface.withValues(
      alpha: opacity == ThemeV2ContentOpacity.dense ? .96 : .90,
    ),
    child: child,
  );
}
```

Wrap the schedule canvas, each flow date section, and day-detail reading panel. Paint row backgrounds inside scrolling rows. Raise grid/border alpha and time/secondary label colors to `tokens.muted` without additional alpha. Keep outer margins transparent.

- [ ] **Step 4: Run Calendar tests and goldens**

Run: `cd mobile && flutter test test/theme_v2/calendar`

Expected: PASS; update only Calendar goldens whose intended surface/contrast changed.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/foundation/theme_v2_content_surface.dart mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart mobile/lib/theme_v2/calendar/calendar_flow_view.dart mobile/lib/theme_v2/calendar/calendar_day_detail.dart mobile/lib/theme_v2/calendar/calendar_components.dart mobile/test/theme_v2/calendar
git commit -m "fix: isolate calendar content from dither"
```

### Task 4: Apply dense content surfaces to Library and Report pages

**Files:**
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/lib/theme_v2/library/library_components.dart`
- Modify: `mobile/lib/theme_v2/report/report_container_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`
- Test: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Interfaces:**
- Consumes: `ThemeV2ContentSurface` from Task 3.

- [ ] **Step 1: Write failing list/report surface tests**

```dart
testWidgets('asset rows carry their own content background while scrolling', (tester) async {
  await tester.pumpWidget(assetListHarness(count: 20));
  expect(find.byKey(const ValueKey('asset-list-content-surface')), findsOneWidget);
  await tester.drag(find.byType(Scrollable), const Offset(0, -500));
  await tester.pumpAndSettle();
  expect(find.byType(ThemeV2ContentSurface), findsWidgets);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_list_page_test.dart test/theme_v2/report/report_run_page_test.dart`

Expected: FAIL because dense surfaces are not used.

- [ ] **Step 3: Add content-owned surfaces**

Wrap asset rows/cards and report reading/form panels, not the entire page. Preserve exposed Dither in gutters and between major sections. Remove any outer-positioned row background that does not move with its list item.

- [ ] **Step 4: Run Theme V2 page tests and analysis**

Run: `cd mobile && flutter test test/theme_v2/calendar test/theme_v2/library test/theme_v2/report`

Run: `cd mobile && flutter analyze lib/theme_v2/foundation lib/theme_v2/shell lib/theme_v2/calendar lib/theme_v2/library lib/theme_v2/report`

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/lib/theme_v2/library/library_components.dart mobile/lib/theme_v2/report/report_container_page.dart mobile/lib/theme_v2/report/report_run_page.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "fix: protect dense pages from dither interference"
```
