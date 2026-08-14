# Theme V2 Dither Surfaces and Today Agenda Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the renewed Today page's in-page agenda timeline and extend one pressure-reactive dither surface across every Calendar and Library view without changing existing content interaction.

**Architecture:** Move the existing Today dither field into Theme V2 foundation and place a single long-lived `ThemeV2DitherSurface` around each Calendar and Library navigation stack. Lightweight reporters translate visible semantic content bounds into a deterministic, capped source list. The renewed Today page owns a local living/agenda presentation switch and reuses the already-shipped `HomeAgendaPanel` with the same loaded `TodayData` snapshot.

**Tech Stack:** Flutter/Dart, CustomPainter and runtime fragment shader (`shaders/today_dither_field.frag`), Theme V2 widgets/tokens, flutter_test, golden tests.

## Global Constraints

- Keep exactly one dither field mounted for Calendar and exactly one for Library.
- Cap each page at 24 active pressure sources, selected by priority, viewport-center distance, then stable ID.
- Calendar preset: `pixelSize 4`, `colorNum 4`, `waveAmplitude .24`, `waveFrequency 2.8`, `waveSpeed .035`, `flowDirection Offset(1, .08)`, light opacity `.28`, dark opacity `.26`, displacement `.84`.
- Library preset: `pixelSize 4`, `colorNum 4`, `waveAmplitude .24`, `waveFrequency 2.6`, `waveSpeed .028`, `flowDirection Offset(.1, 1)`, light opacity `.28`, dark opacity `.26`, displacement `.84`.
- All Calendar and Library content sources use energy `0`; taps, drags, scrolling, selection, and hover never boost pressure.
- Dither is `IgnorePointer`, excluded from semantics, frozen at phase `0` under Reduce Motion, paused on inactive tabs or a non-resumed lifecycle, and resumed without reconstructing the page field.
- Keep asset-detail, event-detail, editor, picker, and other bottom sheets free of dither.
- Keep existing card surfaces near opaque; expose the field through page whitespace by removing only page-root opaque fills.
- Today banner is right-aligned, never cycles titles, never shows an in-progress state, and advances to the next strictly future minute group.
- Tapping the Today banner expands the Todo/Event timeline inside Today and never selects Calendar.
- Preserve all unrelated dirty-worktree changes; stage only files named by the current task.

---

### Task 1: Shared Theme V2 dither field and source-reporting surface

**Files:**
- Create: `mobile/lib/theme_v2/foundation/theme_v2_dither_field.dart`
- Create: `mobile/lib/theme_v2/foundation/theme_v2_dither_surface.dart`
- Delete: `mobile/lib/theme_v2/home/today_dither_field.dart`
- Modify: `mobile/lib/theme_v2/home/today_signal_band.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/test/theme_v2/home/today_dither_field_test.dart`
- Modify: `mobile/test/theme_v2/home/today_living_surface_test.dart`
- Modify: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Create: `mobile/test/theme_v2/foundation/theme_v2_dither_surface_test.dart`

**Interfaces:**
- Produces: `ThemeV2DitherFieldConfig.calendar(...)` and `.library(...)`.
- Produces: `ThemeV2DitherSource.circle(...)`, `.capsule(...)`, and `ThemeV2DitherSourceShape`.
- Produces: `ThemeV2DitherSurface({required config, required active, required child})`.
- Produces: `ThemeV2DitherSourceReporter({required id, required shape, priority, energy, required child})`.
- Produces: `selectThemeV2DitherRegistrations(...)` for deterministic source selection.

- [ ] **Step 1: Write failing foundation tests for presets, ordering, cap, and reporter geometry**

Add tests that specify the public behavior before moving production code:

```dart
test('Calendar and Library presets match the approved motion contract', () {
  const calendar = ThemeV2DitherFieldConfig.calendar();
  const library = ThemeV2DitherFieldConfig.library();
  expect(calendar.flowDirection, const Offset(1, .08));
  expect(calendar.waveFrequency, 2.8);
  expect(calendar.waveSpeed, .035);
  expect(calendar.displacementStrength, .84);
  expect(library.flowDirection, const Offset(.1, 1));
  expect(library.waveFrequency, 2.6);
  expect(library.waveSpeed, .028);
  expect(library.displacementStrength, .84);
});

test('source selection prioritizes priority, center distance, and stable id', () {
  final selected = selectThemeV2DitherRegistrations(
    registrations: [
      const ThemeV2DitherRegistration(
        id: 'z', rect: Rect.fromLTWH(45, 45, 10, 10),
        shape: ThemeV2DitherSourceShape.capsule,
      ),
      const ThemeV2DitherRegistration(
        id: 'a', rect: Rect.fromLTWH(45, 45, 10, 10),
        shape: ThemeV2DitherSourceShape.capsule,
      ),
      const ThemeV2DitherRegistration(
        id: 'priority', rect: Rect.fromLTWH(0, 0, 10, 10),
        shape: ThemeV2DitherSourceShape.circle, priority: 10,
      ),
    ],
    viewport: const Rect.fromLTWH(0, 0, 100, 100),
    limit: 2,
  );
  expect(selected.map((source) => source.id), ['priority', 'a']);
});

testWidgets('surface converts a visible reporter into one local source', (
  tester,
) async {
  await tester.pumpWidget(_host(
    const SizedBox(
      width: 200,
      height: 200,
      child: ThemeV2DitherSurface(
        active: true,
        config: ThemeV2DitherFieldConfig.calendar(),
        child: Align(
          alignment: Alignment.topLeft,
          child: ThemeV2DitherSourceReporter(
            id: 'record',
            shape: ThemeV2DitherSourceShape.capsule,
            child: SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  final field = tester.widget<ThemeV2DitherField>(
    find.byType(ThemeV2DitherField),
  );
  expect(field.sources, hasLength(1));
  expect(field.sources.single.center, const Offset(40, 20));
  expect(field.sources.single.size, const Size(80, 40));
});

testWidgets('surface pauses without losing phase when inactive', (tester) async {
  Widget surface(bool active) => _host(ThemeV2DitherSurface(
    active: active,
    config: const ThemeV2DitherFieldConfig.calendar(),
    child: const SizedBox.expand(),
  ));
  await tester.pumpWidget(surface(true));
  final running = tester.widget<ThemeV2DitherField>(
    find.byType(ThemeV2DitherField),
  ).motion! as AnimationController;
  await tester.pump(const Duration(milliseconds: 40));
  final phase = running.value;
  expect(running.isAnimating, isTrue);
  await tester.pumpWidget(surface(false));
  expect(running.isAnimating, isFalse);
  expect(running.value, phase);
});

testWidgets('Reduce Motion freezes phase and dark mode uses .26 opacity', (
  tester,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildThemeV2Theme(Brightness.dark),
    home: const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: ThemeV2DitherSurface(
        active: true,
        config: ThemeV2DitherFieldConfig.library(),
        child: SizedBox.expand(),
      ),
    ),
  ));
  final field = tester.widget<ThemeV2DitherField>(
    find.byType(ThemeV2DitherField),
  );
  expect(field.reduceMotion, isTrue);
  expect(field.config.opacity, .26);
});

Widget _host(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(body: child),
);
```

- [ ] **Step 2: Run the foundation tests and confirm the new API is missing**

Run:

```bash
cd mobile
flutter test test/theme_v2/foundation/theme_v2_dither_surface_test.dart test/theme_v2/home/today_dither_field_test.dart
```

Expected: FAIL because the foundation files and renamed Theme V2 symbols do not exist.

- [ ] **Step 3: Move and rename the dither primitive, preserving the shader contract**

Move the existing implementation and rename every public `TodayDither*` symbol to `ThemeV2Dither*`. Keep `shaderAsset = 'shaders/today_dither_field.frag'`, `maxSources = 24`, uniform order, fallback painter, and pressure math unchanged. Add these exact preset constructors and broaden `copyWith`:

```dart
const ThemeV2DitherFieldConfig.calendar({
  this.waveColor = const Color(0xFF6D7480),
  this.colorNum = 4,
  this.pixelSize = 4,
  this.waveAmplitude = .24,
  this.waveFrequency = 2.8,
  this.waveSpeed = .035,
  this.flowDirection = const Offset(1, .08),
  this.opacity = .28,
  this.displacementStrength = .84,
});

const ThemeV2DitherFieldConfig.library({
  this.waveColor = const Color(0xFF69717B),
  this.colorNum = 4,
  this.pixelSize = 4,
  this.waveAmplitude = .24,
  this.waveFrequency = 2.6,
  this.waveSpeed = .028,
  this.flowDirection = const Offset(.1, 1),
  this.opacity = .28,
  this.displacementStrength = .84,
});

const ThemeV2DitherFieldConfig.raw({
  required this.waveColor,
  required this.colorNum,
  required this.pixelSize,
  required this.waveAmplitude,
  required this.waveFrequency,
  required this.waveSpeed,
  required this.flowDirection,
  required this.opacity,
  required this.displacementStrength,
});

ThemeV2DitherFieldConfig copyWith({
  Color? waveColor,
  double? opacity,
  double? waveSpeed,
}) => ThemeV2DitherFieldConfig.raw(
  waveColor: waveColor ?? this.waveColor,
  colorNum: colorNum,
  pixelSize: pixelSize,
  waveAmplitude: waveAmplitude,
  waveFrequency: waveFrequency,
  waveSpeed: waveSpeed ?? this.waveSpeed,
  flowDirection: flowDirection,
  opacity: opacity ?? this.opacity,
  displacementStrength: displacementStrength,
);
```

Keep `.signal()` and `.asset()` with their current approved Today values so the move cannot alter Today visuals.

- [ ] **Step 4: Implement the page surface, deterministic registry, and reporter**

Create `theme_v2_dither_surface.dart` with these concrete public types and lifecycle rules:

```dart
@immutable
class ThemeV2DitherRegistration {
  const ThemeV2DitherRegistration({
    required this.id,
    required this.rect,
    required this.shape,
    this.priority = 0,
    this.energy = 0,
  });
  final String id;
  final Rect rect;
  final ThemeV2DitherSourceShape shape;
  final int priority;
  final double energy;

  ThemeV2DitherSource toSource() => switch (shape) {
    ThemeV2DitherSourceShape.circle => ThemeV2DitherSource.circle(
      center: rect.center,
      radius: math.min(rect.width, rect.height) / 2,
      energy: energy,
    ),
    ThemeV2DitherSourceShape.capsule => ThemeV2DitherSource.capsule(
      center: rect.center,
      size: rect.size,
      energy: energy,
    ),
  };
}

List<ThemeV2DitherRegistration> selectThemeV2DitherRegistrations({
  required Iterable<ThemeV2DitherRegistration> registrations,
  required Rect viewport,
  int limit = ThemeV2DitherField.maxSources,
}) {
  final center = viewport.center;
  final visible = registrations.where((entry) => entry.rect.overlaps(viewport)).toList();
  visible.sort((a, b) {
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    final distance = (a.rect.center - center).distanceSquared.compareTo(
      (b.rect.center - center).distanceSquared,
    );
    return distance != 0 ? distance : a.id.compareTo(b.id);
  });
  return visible.take(limit).toList(growable: false);
}
```

`ThemeV2DitherSurfaceController` stores registrations by ID, coalesces `notifyListeners()` to one post-frame callback, unregisters on reporter disposal, and exposes `sourcesFor(Rect viewport)` using the selector above.

`ThemeV2DitherSurface` must use `LayoutBuilder` to derive its viewport without
calling `setState` during build:

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    final viewport = Size(constraints.maxWidth, constraints.maxHeight);
    return ColoredBox(
      color: tokens.background,
      child: Stack(
        key: _surfaceKey,
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _sources,
            builder: (context, _) => ThemeV2DitherField(
              config: widget.config.copyWith(
                waveColor: tokens.foreground,
                opacity: brightness == Brightness.dark ? .26 : .28,
              ),
              sources: _sources.sourcesFor(Offset.zero & viewport),
              motion: _motion,
              reduceMotion: _reduceMotion,
            ),
          ),
          _ThemeV2DitherScope(
            controller: _sources,
            surfaceKey: _surfaceKey,
            child: widget.child,
          ),
        ],
      ),
    );
  },
);
```

It mixes in `SingleTickerProviderStateMixin` and `WidgetsBindingObserver`; `_motion.repeat()` runs only when `widget.active`, lifecycle is resumed, and Reduce Motion is false. Stopping uses `stop(canceled: false)` so phase is retained.

`ThemeV2DitherSourceReporter` owns a `GlobalKey`, attaches to `Scrollable.maybeOf(context)?.position`, schedules geometry after build/size/scroll changes, translates its render rect into `_surfaceKey` coordinates, and registers energy `0` by default. Wrap the child in `SizeChangedLayoutNotifier` without adding hit testing or semantics.

- [ ] **Step 5: Migrate Today imports and tests to Theme V2 foundation names**

Replace imports of `today_dither_field.dart` with:

```dart
import '../foundation/theme_v2_dither_field.dart';
```

Use `../../lib/...`-appropriate relative paths in tests and rename `TodayDitherField`, `TodayDitherSource`, `TodayDitherSourceShape`, and `TodayDitherFieldConfig` references. Do not change Today configs, source energy behavior, or widget keys other than the class-static shader key owner.

- [ ] **Step 6: Run all migrated dither tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/foundation/theme_v2_dither_surface_test.dart test/theme_v2/home/today_dither_field_test.dart test/theme_v2/home/today_living_surface_test.dart test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the shared foundation**

```bash
git add mobile/lib/theme_v2/foundation/theme_v2_dither_field.dart mobile/lib/theme_v2/foundation/theme_v2_dither_surface.dart mobile/lib/theme_v2/home/today_dither_field.dart mobile/lib/theme_v2/home/today_signal_band.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/test/theme_v2/foundation/theme_v2_dither_surface_test.dart mobile/test/theme_v2/home/today_dither_field_test.dart mobile/test/theme_v2/home/today_living_surface_test.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
git commit -m "refactor(theme-v2): share dither surface foundation"
```

### Task 2: Right-aligned Today agenda banner and local timeline presentation

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_next_capsule.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Test: `mobile/test/theme_v2/home/today_next_capsule_test.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Consumes: existing `HomeAgendaPanel`, `TodayData`, and `openAssetDetail` behavior.
- Produces: `todayNextGroup(...)` filtered and deterministically sorted for Todo/Event.
- Produces: `todayNextSummary(List<ChainItem>) -> String`.
- Produces: local `_TodayPresentation.living/agenda` state in `TodayDotExperimentPage`.

- [ ] **Step 1: Replace the old banner/navigation tests with the approved contract**

Add or update tests with these assertions:

```dart
test('next group filters unsupported kinds and sorts event before todo', () {
  final now = DateTime(2026, 8, 14, 9);
  final at = DateTime(2026, 8, 14, 10, 30);
  final group = todayNextGroup([
    _item('todo', '提交方案', at, kind: 'todo'),
    _item('note', '会议笔记', at, kind: 'note'),
    _item('event', '周会', at, kind: 'event'),
  ], now);
  expect(group.map((item) => item.id), ['event', 'todo']);
  expect(todayNextSummary(group), '周会、提交方案');
});

ChainItem _item(
  String id,
  String title,
  DateTime at, {
  String kind = 'event',
  bool timed = true,
}) => ChainItem(kind: kind, id: id, title: title, at: at, timed: timed);

testWidgets('same-minute banner is right aligned and summarizes two titles', (
  tester,
) async {
  final at = DateTime(2026, 8, 14, 10, 30);
  await tester.pumpWidget(_host(TodayNextCapsule(
    items: [
      _item('a-todo', '提交方案', at, kind: 'todo'),
      _item('event', '周会', at, kind: 'event'),
      _item('z-todo', '客户沟通', at, kind: 'todo'),
    ],
    now: DateTime(2026, 8, 14, 9),
    onOpenAgenda: () {},
  )));
  expect(find.text('10:30 · 3 项'), findsOneWidget);
  expect(find.text('周会、提交方案 +1'), findsOneWidget);
  final title = tester.widget<Text>(find.text('周会、提交方案 +1'));
  expect(title.textAlign, TextAlign.right);
});

testWidgets('Today banner opens and closes the local agenda without refetch', (
  tester,
) async {
  final repository = _ImmediateRepository(TodayData(
    chain: [
      _item(
        'event',
        '周会',
        DateTime(2026, 8, 14, 10, 30),
        kind: 'event',
      ),
      _item(
        'todo',
        '提交方案',
        DateTime(2026, 8, 14, 10, 30),
        kind: 'todo',
      ),
    ],
    noTimeTodos: const [],
    pool: const [],
    poolTrueCount: 0,
    flashCount: 0,
  ));
  await tester.pumpWidget(_Host(child: TodayDotExperimentPage(
    repository: repository,
    now: DateTime(2026, 8, 14, 9),
  )));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
  await tester.pumpAndSettle();
  expect(find.byType(HomeAgendaPanel), findsOneWidget);
  expect(find.byType(TodayLivingSurface), findsNothing);
  expect(find.byKey(TodayRekaScene.rekaRenderKey), findsNothing);
  expect(repository.loadCount, 1);
  await tester.tap(find.bySemanticsLabel('收起日程'));
  await tester.pumpAndSettle();
  expect(find.byType(TodayLivingSurface), findsOneWidget);
});
```

Change the shell regression from “opens Calendar” to the local-presentation
assertions below. Do not assert that `ThemeV2CalendarPage` is absent because
the shell intentionally keeps all three destinations mounted in an
`IndexedStack`:

```dart
await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
await tester.pumpAndSettle();
expect(find.byType(HomeAgendaPanel), findsOneWidget);
expect(tester.widget<ThemeV2FloatingDock>(find.byType(ThemeV2FloatingDock)).selectedIndex, 0);
```

- [ ] **Step 2: Run the focused tests and confirm the current Calendar jump fails them**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: FAIL because the banner shows only one title, the experiment page has no agenda presentation, and the shell still selects Calendar.

- [ ] **Step 3: Implement deterministic grouping and the compact right-aligned banner**

Update selection and summary helpers:

```dart
final future = items.where((item) {
  if (item.kind != 'event' && item.kind != 'todo') return false;
  return item.timed && _minuteOf(item.at).isAfter(nowMinute);
}).toList()
  ..sort((a, b) {
    final time = _minuteOf(a.at).compareTo(_minuteOf(b.at));
    if (time != 0) return time;
    final kind = _kindRank(a.kind).compareTo(_kindRank(b.kind));
    return kind != 0 ? kind : a.id.compareTo(b.id);
  });

String todayNextSummary(List<ChainItem> group) {
  final visible = group.take(2).map((item) => item.title).join('、');
  final remainder = group.length - 2;
  return remainder > 0 ? '$visible +$remainder' : visible;
}
```

Render the non-empty capsule as one `Column(crossAxisAlignment: CrossAxisAlignment.end)` containing countdown, `HH:mm` or `HH:mm · N 项`, and `todayNextSummary(group)`. Set `textAlign: TextAlign.right` on every `Text`, keep `maxLines: 1`, and preserve the existing 44-point hit target and semantic button. For a one-item group omit `· 1 项`. Apply the same right alignment to `今天暂无安排`.

- [ ] **Step 4: Add local Today presentation state and reuse `HomeAgendaPanel`**

In `TodayDotExperimentPage`:

```dart
enum _TodayPresentation { living, agenda }

_TodayPresentation _presentation = _TodayPresentation.living;

void _openAgenda() => setState(() => _presentation = _TodayPresentation.agenda);
void _closeAgenda() => setState(() => _presentation = _TodayPresentation.living);
```

Extract the current `TodayRekaScene` subtree into `_livingPresentation(...)`. Pass `_openAgenda` to `TodayLivingSurface`. For agenda mode, render the same `_data ?? TodayData.empty` without `TodayRekaScene` or output overlay:

```dart
Widget _agendaPresentation(double topInset, double bottomInset) => Padding(
  padding: EdgeInsets.fromLTRB(18, topInset, 18, bottomInset),
  child: SingleChildScrollView(
    key: const ValueKey('today-agenda-scroll'),
    child: SizedBox(
      height: 720,
      child: HomeAgendaPanel(
        data: _data ?? TodayData.empty,
        date: widget.now,
        onCloseAgenda: _closeAgenda,
      ),
    ),
  ),
);
```

Switch presentations with Theme V2 standard fade/short vertical slide. Use `Duration.zero` when `MediaQuery.disableAnimationsOf(context)` is true. Do not call `_refresh`, recreate `_outputCoordinator`, or dispose `_sceneRekaController` during the switch.

- [ ] **Step 5: Remove shell ownership of the agenda action**

Delete `onOpenAgenda` from `TodayDotExperimentPage`'s public constructor and remove this shell argument:

```dart
onOpenAgenda: () => _selectDestination(1),
```

Keep Calendar reselect behavior unchanged for the actual Calendar dock destination.

- [ ] **Step 6: Run the focused Today and shell tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the Today agenda behavior**

```bash
git add mobile/lib/theme_v2/home/today_next_capsule.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_next_capsule_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "feat(theme-v2): restore today agenda timeline"
```

### Task 3: Calendar-wide dither surface and semantic pressure sources

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_components.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_day_detail.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_month_view.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_year_view.dart`
- Test: `mobile/test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_day_detail_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_schedule_grid_test.dart`
- Test: `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart`

**Interfaces:**
- Consumes: Task 1 `ThemeV2DitherSurface`, reporter, config, and source shape.
- Produces: `ThemeV2CalendarPage.active` with default `true`.
- Produces: one stable Calendar dither surface across flow/month/year/day/schedule.

- [ ] **Step 1: Write failing Calendar surface and source tests**

Add focused widget tests:

```dart
expect(find.byType(ThemeV2DitherSurface), findsOneWidget);
final surface = tester.widget<ThemeV2DitherSurface>(find.byType(ThemeV2DitherSurface));
expect(surface.config.flowDirection, const Offset(1, .08));

await tester.pump();
final field = tester.widget<ThemeV2DitherField>(find.byType(ThemeV2DitherField));
expect(field.sources, isNotEmpty);
expect(field.sources.length, lessThanOrEqualTo(24));
expect(field.sources.every((source) => source.energy == 0), isTrue);
```

In the controller-driven page test, capture `tester.state(find.byType(ThemeV2DitherField))`, open a day, open schedule, and assert the same state identity after each surface transition. Add a month test asserting empty dates create no reporter and Today/selected date reporters use `circle`. Add a year test asserting at most 12 month-panel capsule reporters rather than individual day reporters.

- [ ] **Step 2: Run focused Calendar tests and confirm no dither surface exists**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart test/theme_v2/calendar/calendar_schedule_grid_test.dart
```

Expected: FAIL because Calendar has no shared dither root or source reporters.

- [ ] **Step 3: Install one transparent Calendar root surface**

Add `this.active = true` and `final bool active` to `ThemeV2CalendarPage`. Replace its outer root fill with:

```dart
ThemeV2DitherSurface(
  key: const ValueKey('calendar-dither-surface'),
  active: widget.active,
  config: const ThemeV2DitherFieldConfig.calendar(),
  child: currentCalendarContent,
)
```

Keep the surface outside `_dataBody` and outside the `CalendarSurface` switch so its State survives overview/day/schedule and PageView scale changes. Change only these page-root fills to transparent:

- `CalendarDayDetail` outer `ColoredBox`.
- `CalendarScheduleGrid` outer `ColoredBox`.
- `CalendarMonthView` outer `Container.color`.
- `CalendarYearView` outer `Container.color`.
- `_CalendarScheduleRoute` outer root in `theme_v2_calendar_page.dart`.

Do not make cards, trays, headers, or error overlays transparent.

- [ ] **Step 4: Report Calendar record and date geometry**

Add a required `ditherSourceId` to `CalendarRecordRow` and wrap its rendered
body. Requiring the namespace prevents adjacent PageView modes from
registering the same record ID:

```dart
return ThemeV2DitherSourceReporter(
  id: ditherSourceId,
  shape: ThemeV2DitherSourceShape.capsule,
  child: recordRow,
);
```

Update every call site with these IDs:

- Flow timed and untimed rows: `calendar-flow-${calendarDayKey(day)}-${record.id}`;
  pass the day key through `_FlowBandSection`.
- Month selected-day summary: `calendar-month-summary-${calendarDayKey(day)}-${record.id}`.
- Day Detail `_DayRecordRow`: wrap its complete semantic row directly as
  `calendar-day-detail-${record.id}`, capsule.

Add reporters at these exact render boundaries:

- `_ScheduleEventBlock`: `calendar-schedule-event-${entry.id}`, capsule.
- `_TodoBandBlock`: `calendar-schedule-todo-band-${calendarDayKey(band.startAt)}-${band.startAt.hour}-${band.startAt.minute}`, capsule.
- `_MonthCell`: wrap only when `today || selected`, ID `calendar-month-day-${calendarDayKey(day)}`, circle, priority `100` for selected and `90` for Today.
- `_YearMonthCell`: `calendar-year-month-$year-$month`, capsule, priority `100` for selected and `90` for the month containing Today.

Headers, navigation buttons, empty hatches, time labels, separators, flashes, and individual Year day cells must not use reporters.

- [ ] **Step 5: Run Calendar tests, then update and verify Calendar goldens**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart test/theme_v2/calendar/calendar_schedule_grid_test.dart
flutter test --update-goldens test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
flutter test test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
```

Expected: all PASS; the light and dark goldens show the same card hierarchy over a calm horizontal dither field.

- [ ] **Step 6: Commit Calendar dither**

```bash
git add mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/lib/theme_v2/calendar/calendar_components.dart mobile/lib/theme_v2/calendar/calendar_flow_view.dart mobile/lib/theme_v2/calendar/calendar_day_detail.dart mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart mobile/lib/theme_v2/calendar/calendar_month_view.dart mobile/lib/theme_v2/calendar/calendar_year_view.dart mobile/test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart mobile/test/theme_v2/calendar/calendar_day_detail_test.dart mobile/test/theme_v2/calendar/calendar_schedule_grid_test.dart mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart
git add -u mobile/test/theme_v2/calendar/goldens
git commit -m "feat(theme-v2): add dither field across calendar"
```

### Task 4: Library-wide dither surface and semantic pressure sources

**Files:**
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/library_components.dart`
- Modify: `mobile/lib/theme_v2/library/library_hub.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Test: `mobile/test/theme_v2/library/library_components_test.dart`
- Test: `mobile/test/theme_v2/library/library_navigation_test.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`
- Test: `mobile/test/theme_v2/library/theme_v2_library_golden_test.dart`

**Interfaces:**
- Consumes: Task 1 shared surface and reporters.
- Produces: `ThemeV2LibraryPage.active` with default `true`.
- Produces: one stable Library dither surface across hub/index/all/pinned/asset-list navigation.

- [ ] **Step 1: Write failing Library surface, continuity, and geometry tests**

Add assertions that the hub owns one Library preset, visible container cards report capsules, recent 55-point asset cards report circles, and an asset-list rich card reports a capsule. Capture the `ThemeV2DitherField` State, navigate hub → index → pinned → hub, and assert the same State identity with no second field.

```dart
expect(find.byType(ThemeV2DitherSurface), findsOneWidget);
final surface = tester.widget<ThemeV2DitherSurface>(find.byType(ThemeV2DitherSurface));
expect(surface.config.flowDirection, const Offset(.1, 1));
await tester.pump();
final sources = tester.widget<ThemeV2DitherField>(
  find.byType(ThemeV2DitherField),
).sources;
expect(sources, isNotEmpty);
expect(sources.length, lessThanOrEqualTo(24));
expect(sources.every((source) => source.energy == 0), isTrue);
```

- [ ] **Step 2: Run focused Library tests and confirm the surface is missing**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_components_test.dart test/theme_v2/library/library_navigation_test.dart test/theme_v2/library/asset/asset_list_page_test.dart
```

Expected: FAIL because Library has no shared dither root or reporters.

- [ ] **Step 3: Install one Library root surface around every state**

Add `this.active = true` and `final bool active` to `ThemeV2LibraryPage`. Refactor `build` so loading, offline/error, and normal `PageStorage` content are selected into `currentContent`, then return:

```dart
ThemeV2DitherSurface(
  key: const ValueKey('library-dither-surface'),
  active: widget.active,
  config: const ThemeV2DitherFieldConfig.library(),
  child: currentContent,
)
```

The surface must remain outside `_navigation.surface` and status switches. Replace only page-root background fills in `ThemeV2LibraryPage` and `ThemeV2AssetListPage` with transparent fills. Keep cards, search fields, state cards, and refresh indicators surfaced. Do not wrap `openAssetDetail`, report routes, editors, or sheets.

- [ ] **Step 4: Add reporters to shared Library content primitives**

Wrap these exact components:

```dart
ThemeV2DitherSourceReporter(
  id: 'library-container-${container.id}',
  shape: ThemeV2DitherSourceShape.capsule,
  child: containerTile,
)
```

- `_LibraryPinnedTile`: capsule, ID `library-pinned-${container.id}`.
- `_ContainerRowBase`: capsule, ID `library-container-${container.id}`.
- `LibraryAvailableContainerTile`: capsule, ID `library-available-${container.id}`.
- `_RecentAssets` item: circle, ID `library-recent-${asset.id}` around its 55×54 `SizedBox`.
- `_AssetRecordRow`: capsule, ID `library-asset-${record.id}` around the complete row, including the Todo completion control.

Do not report stats bars, headers, search fields, section labels, create buttons, drag handles, or empty-state copy. Reporter energy remains omitted so it is exactly `0` during press, drag, scroll, and selection.

- [ ] **Step 5: Run Library tests, then update and verify Library goldens**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_components_test.dart test/theme_v2/library/library_navigation_test.dart test/theme_v2/library/asset/asset_list_page_test.dart
flutter test --update-goldens test/theme_v2/library/theme_v2_library_golden_test.dart
flutter test test/theme_v2/library/theme_v2_library_golden_test.dart
```

Expected: all PASS; the field flows downward and remains behind nearly opaque content surfaces.

- [ ] **Step 6: Commit Library dither**

```bash
git add mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/theme_v2/library/library_components.dart mobile/lib/theme_v2/library/library_hub.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/test/theme_v2/library/library_components_test.dart mobile/test/theme_v2/library/library_navigation_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart mobile/test/theme_v2/library/theme_v2_library_golden_test.dart
git add -u mobile/test/theme_v2/library/goldens
git commit -m "feat(theme-v2): add dither field across library"
```

### Task 5: Shell activity wiring, regression verification, and device handoff

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Test: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Test: Calendar and Library golden files changed by Tasks 3–4.

**Interfaces:**
- Consumes: `ThemeV2CalendarPage.active` and `ThemeV2LibraryPage.active`.
- Produces: only the selected bottom-navigation page animates its page dither field.

- [ ] **Step 1: Write a failing shell activity test**

Pump the production pages in the `IndexedStack`, select each dock destination, and assert:

```dart
expect(tester.widget<ThemeV2CalendarPage>(find.byType(ThemeV2CalendarPage)).active, isFalse);
expect(tester.widget<ThemeV2LibraryPage>(find.byType(ThemeV2LibraryPage)).active, isFalse);
await tester.tap(find.bySemanticsLabel('日历'));
await tester.pump();
expect(tester.widget<ThemeV2CalendarPage>(find.byType(ThemeV2CalendarPage)).active, isTrue);
expect(tester.widget<ThemeV2LibraryPage>(find.byType(ThemeV2LibraryPage)).active, isFalse);
await tester.tap(find.bySemanticsLabel('资产'));
await tester.pump();
expect(tester.widget<ThemeV2CalendarPage>(find.byType(ThemeV2CalendarPage)).active, isFalse);
expect(tester.widget<ThemeV2LibraryPage>(find.byType(ThemeV2LibraryPage)).active, isTrue);
```

- [ ] **Step 2: Pass explicit activity into Calendar and Library**

Update production page construction:

```dart
ThemeV2CalendarPage(
  active: _index == 1,
  controller: _calendarController,
),
ThemeV2LibraryPage(
  active: _index == 2,
  navigation: _libraryNavigation,
),
```

Do not special-case injected `widget.pages`.

- [ ] **Step 3: Run the complete affected test suite and analyzer**

Run:

```bash
cd mobile
flutter test test/theme_v2/foundation/theme_v2_dither_surface_test.dart test/theme_v2/home/today_dither_field_test.dart test/theme_v2/home/today_next_capsule_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_living_surface_test.dart test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/calendar test/theme_v2/library test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter analyze lib/theme_v2/foundation lib/theme_v2/home lib/theme_v2/calendar lib/theme_v2/library lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/foundation test/theme_v2/home test/theme_v2/calendar test/theme_v2/library test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: all tests PASS and analyzer reports `No issues found!`.

- [ ] **Step 4: Refresh Today experiment goldens only if the approved header/timeline changes alter them**

Run:

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
flutter test test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: PASS. Inspect generated light/dark images before staging; do not accept unrelated visual movement in Reka, signal, or asset geometry.

- [ ] **Step 5: Build the correct experiment APK and verify on the connected phone**

Run:

```bash
cd mobile
flutter devices
flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true
flutter run --debug --dart-define=TODAY_DOT_EXPERIMENT=true
```

Device QA checklist:

- Today date remains left; the complete agenda summary is visibly right-aligned.
- Simultaneous records show one time/count, two titles maximum, and `+N`.
- The banner expands and collapses the in-page timeline without moving the dock to Calendar.
- Reka does not cover the expanded timeline and returns to its retained position afterward.
- Calendar Flow, Month, Year, Day, and Schedule share one calm horizontal field.
- Library Hub, Index, All, Pinned, and Asset List share one downward field.
- Content pressure stays uniform during tap, scroll, drag, and selection.
- Light/dark contrast is readable; sheets remain free of dither.
- Switching tabs produces no full-field mechanical reset.

- [ ] **Step 6: Commit shell wiring and verified goldens**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/test/theme_v2/home/goldens mobile/test/theme_v2/calendar/goldens mobile/test/theme_v2/library/goldens
git commit -m "test(theme-v2): verify agenda and dither rollout"
```
