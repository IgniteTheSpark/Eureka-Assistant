# Theme V2 Today Dot-Matrix Experiment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an opt-in Light Today empty-scene experiment with a passive dot background, locally breathing Reka, three working quick actions, dot-only pull-to-refresh feedback, and an unchanged legacy Home fallback.

**Architecture:** Add a compile-time rollout seam at the Theme V2 shell boundary. Keep the current `ThemeV2HomePage` untouched and implement the experiment as focused scene, painter, quick-action, and page-state units. The painter owns only rendering; the page owns repository refresh; the shell owns mature route construction.

**Tech Stack:** Flutter, Dart, Material, `CustomPainter`, `AnimationController`, `RefreshIndicator.noSpinner`, widget tests, painter raster tests, Flutter golden tests.

## Global Constraints

- The Pencil visual source is `redesignureka.pen`, node `zjzLR` (`UReka · Theme V2 / Light / Today Renew / Empty / 411`).
- Reference viewport is `411 × 860` logical pixels.
- The experiment is enabled with `--dart-define=TODAY_DOT_EXPERIMENT=true` and defaults to `false`.
- The experiment always uses its explicit Light palette; Dark visual design is out of scope.
- Base grid interval is exactly `8 logical px`.
- Base dots never respond to tap, drag, tilt, parallax, scroll, or business data.
- Only dots inside Reka's `86–95 px` influence radius move autonomously.
- Reka breathes over `4.5–6 s`, changes radius by no more than `±4 px`, and drifts by no more than `1–2 px`.
- Tapping Reka never deforms the dots; it opens exactly Create Asset, Create Report, and Start New Chat.
- Reka's hit target is at least `64 × 64 px`.
- Pull-to-refresh changes top-band opacity only and settles in approximately `320 ms`.
- Reduce Motion stops Reka deformation and keeps refresh feedback opacity-only.
- Do not render schedule, signals, or asset balls in this tranche.
- Do not add dependencies.
- Preserve every unrelated dirty-worktree change.

---

## File Structure

Create:

- `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart` — immutable scene geometry, palette, and physical-pixel-aligned dot painting.
- `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart` — Reka ticker lifecycle, responsive scene placement, authored copy, and the semantic Reka hotspot.
- `mobile/lib/theme_v2/home/today_reka_quick_actions.dart` — compact three-item menu and injected route callbacks.
- `mobile/lib/theme_v2/home/today_dot_experiment_page.dart` — repository lifecycle, no-spinner pull refresh, failure/retry, and scene composition.
- `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart` — deterministic raster/geometry behavior.
- `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart` — interactions, refresh, accessibility, and failure behavior.
- `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart` — `411 × 860` and tall-viewport visual contracts.
- `mobile/test/theme_v2/home/goldens/today-dot-experiment-empty-411-light.png` — approved Light reference output.
- `mobile/test/theme_v2/home/goldens/today-dot-experiment-empty-tall-light.png` — safe-area extension output.

Modify:

- `mobile/lib/config.dart` — compile-time experiment flag.
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart` — select experiment/fallback and inject mature routes.
- `mobile/test/theme_v2/theme_v2_rollout_test.dart` — flag default contract.
- `mobile/test/theme_v2/shell/theme_v2_shell_test.dart` — shell selection seam.

Do not modify:

- `mobile/lib/theme_v2/home/home_today_panel.dart`;
- `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`;
- current Home golden files;
- Pencil source or Today Active design.

---

### Task 1: Add the opt-in Home selection seam

**Files:**

- Modify: `mobile/lib/config.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/theme_v2_rollout_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

**Interfaces:**

- Produces: `AppConfig.todayDotExperiment: bool`.
- Produces: `ThemeV2AppShell.todayDotExperimentOverride: bool?`.
- Consumes later: `TodayDotExperimentPage` constructor from Task 4.

- [ ] **Step 1: Write the failing flag and shell-selection tests**

Add to the rollout test:

```dart
test('Today dot experiment is opt-in', () {
  const expected = bool.fromEnvironment(
    'TODAY_DOT_EXPERIMENT',
    defaultValue: false,
  );
  expect(AppConfig.todayDotExperiment, expected);
});
```

Add a shell constructor contract test that verifies the override remains injectable without reading process state:

```dart
testWidgets('Today experiment override preserves explicit false', (tester) async {
  const shell = ThemeV2AppShell(
    todayDotExperimentOverride: false,
    showStartupOverlays: false,
  );
  expect(shell.todayDotExperimentOverride, isFalse);
});
```

- [ ] **Step 2: Run the tests and verify the missing members fail**

Run:

```bash
cd mobile
flutter test test/theme_v2/theme_v2_rollout_test.dart test/theme_v2/shell/theme_v2_shell_test.dart
```

Expected: compilation fails because `AppConfig.todayDotExperiment` and `todayDotExperimentOverride` do not exist.

- [ ] **Step 3: Add the compile-time flag and constructor seam**

Add to `AppConfig`:

```dart
/// Enables the reversible Light Today dot-matrix evaluation surface.
static const todayDotExperiment = bool.fromEnvironment(
  'TODAY_DOT_EXPERIMENT',
  defaultValue: false,
);
```

Add to `ThemeV2AppShell`:

```dart
this.todayDotExperimentOverride,

/// Test/evaluation seam. Production follows AppConfig.todayDotExperiment.
final bool? todayDotExperimentOverride;

bool get usesTodayDotExperiment =>
    todayDotExperimentOverride ?? AppConfig.todayDotExperiment;
```

Import `../../config.dart`. Do not change `_pages()` until Task 5, because the experiment page does not exist yet.

- [ ] **Step 4: Run the focused tests**

Run the Task 1 command again.

Expected: PASS.

- [ ] **Step 5: Commit the rollout seam**

```bash
git add mobile/lib/config.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/theme_v2_rollout_test.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat: add today dot experiment seam"
```

---

### Task 2: Build the passive dot painter and Reka deformation

**Files:**

- Create: `mobile/lib/theme_v2/home/today_dot_matrix_painter.dart`
- Create: `mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart`

**Interfaces:**

- Produces: `TodayDotMatrixPalette.light`.
- Produces: `TodayDotSceneGeometry.forSize(Size size)`.
- Produces: `TodayDotMatrixPainter({required double rekaPhase, required double refreshEmphasis, required bool reduceMotion, required double devicePixelRatio})`.
- Consumes later: `TodayDotMatrixScene` from Task 3.

- [ ] **Step 1: Write failing geometry and repaint tests**

```dart
test('reference geometry keeps an 8 px grid and bounded Reka', () {
  final geometry = TodayDotSceneGeometry.forSize(const Size(411, 860));
  expect(geometry.gridInterval, 8);
  expect(geometry.rekaCenter.dx, closeTo(78, 2));
  expect(geometry.rekaCenter.dy, closeTo(505, 4));
  expect(geometry.rekaInfluenceRadius, inInclusiveRange(86, 95));
});

test('unrelated painter inputs do not force repaint', () {
  const first = TodayDotMatrixPainter(
    rekaPhase: 0,
    refreshEmphasis: 0,
    reduceMotion: true,
    devicePixelRatio: 1,
  );
  const same = TodayDotMatrixPainter(
    rekaPhase: 0,
    refreshEmphasis: 0,
    reduceMotion: true,
    devicePixelRatio: 1,
  );
  expect(same.shouldRepaint(first), isFalse);
});
```

Add a raster test that proves idle motion stays local:

```dart
Future<ui.Image> paintPhase(double phase) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(411, 860);
  TodayDotMatrixPainter(
    rekaPhase: phase,
    refreshEmphasis: 0,
    reduceMotion: false,
    devicePixelRatio: 1,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

Future<int> rgbaAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  return data!.getUint32(offset);
}

test('idle phase changes only the local Reka region', () async {
  final rest = await paintPhase(0);
  final breath = await paintPhase(.25);
  expect(await rgbaAt(rest, 320, 320), await rgbaAt(breath, 320, 320));
  expect(await rgbaAt(rest, 78, 505), isNot(await rgbaAt(breath, 78, 505)));
});
```

- [ ] **Step 2: Run the painter test and verify it fails**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_matrix_painter_test.dart
```

Expected: compilation fails because the painter types do not exist.

- [ ] **Step 3: Implement immutable palette and geometry**

```dart
@immutable
class TodayDotMatrixPalette {
  const TodayDotMatrixPalette({
    required this.surface,
    required this.dot,
    required this.rekaDot,
    required this.eye,
    required this.foreground,
    required this.muted,
  });

  static const light = TodayDotMatrixPalette(
    surface: Color(0xFFE3EAE5),
    dot: Color(0x8974837A),
    rekaDot: Color(0xFF607269),
    eye: Color(0xFFC6532F),
    foreground: Color(0xFF18211C),
    muted: Color(0xFF66746C),
  );

  final Color surface;
  final Color dot;
  final Color rekaDot;
  final Color eye;
  final Color foreground;
  final Color muted;
}

@immutable
class TodayDotSceneGeometry {
  const TodayDotSceneGeometry({
    required this.size,
    required this.rekaCenter,
    required this.rekaInfluenceRadius,
    this.gridInterval = 8,
  });

  factory TodayDotSceneGeometry.forSize(Size size) {
    final heightDelta = math.max(0.0, size.height - 860);
    return TodayDotSceneGeometry(
      size: size,
      rekaCenter: Offset(78, 505 + heightDelta * 0.20),
      rekaInfluenceRadius: 92,
    );
  }

  final Size size;
  final Offset rekaCenter;
  final double rekaInfluenceRadius;
  final double gridInterval;
}
```

- [ ] **Step 4: Implement the physical-pixel-aligned painter**

Use one `CustomPainter`, not one Widget per dot. Cache no mutable business state. For every `8 px` grid point:

```dart
final delta = point - animatedRekaCenter;
final distance = delta.distance;
final t = (1 - distance / animatedRadius).clamp(0.0, 1.0);
final falloff = t * t * (3 - 2 * t);
final direction = distance == 0 ? Offset.zero : delta / distance;
final displaced = point + direction * (falloff * 5.5);
final radius = 0.9 + falloff * 1.5;
```

Outside the Reka radius, paint `point` with the base radius and base color. Inside, paint `displaced` with interpolated radius and color. Derive animation from `sin(rekaPhase * 2π)` with maximum radius variation `4 px` and vertical drift `1.5 px`. When `reduceMotion` is true, force the phase contribution to zero.

Apply refresh emphasis only to dots in the top `96 px` with a vertical falloff. Increase alpha without changing position or radius.

Snap every painted center to the nearest physical pixel using:

```dart
double snap(double value) =>
    (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
```

Paint the two orange-red eye clusters after the membrane dots. Keep their coordinates relative to the animated Reka center.

- [ ] **Step 5: Run the painter tests**

Run the Task 2 test command.

Expected: PASS, including the local-motion raster assertion.

- [ ] **Step 6: Commit the painter**

```bash
git add mobile/lib/theme_v2/home/today_dot_matrix_painter.dart mobile/test/theme_v2/home/today_dot_matrix_painter_test.dart
git commit -m "feat: paint passive today dot matrix"
```

---

### Task 3: Compose the living scene and Reka quick actions

**Files:**

- Create: `mobile/lib/theme_v2/home/today_dot_matrix_scene.dart`
- Create: `mobile/lib/theme_v2/home/today_reka_quick_actions.dart`
- Create: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

**Interfaces:**

- Produces: `TodayDotMatrixScene({required double refreshEmphasis, required VoidCallback onRekaTap})`.
- Produces: `Future<void> showTodayRekaQuickActions(BuildContext context, {required Rect anchor, required VoidCallback? onCreateAsset, required VoidCallback? onCreateReport, required VoidCallback? onStartChat})`.
- Consumes: palette, geometry, and painter from Task 2.
- Consumes later: experiment page from Task 4.

- [ ] **Step 1: Write failing scene and menu tests**

Mount the scene at `411 × 860` with `disableAnimations: true`. Assert:

```dart
final reka = find.bySemanticsLabel('Reka 快捷操作');
expect(reka, findsOneWidget);
expect(tester.getSize(reka).width, greaterThanOrEqualTo(64));
expect(tester.getSize(reka).height, greaterThanOrEqualTo(64));
expect(find.text('今天很安静，我在这里。'), findsOneWidget);
expect(find.byType(CustomPaint), findsWidgets);
```

Tap Reka and assert exactly one each of `创建资产`, `创建报告`, and `开始新聊天`. Select every item in separate pumps and verify only its injected callback increments.

- [ ] **Step 2: Run the focused test and verify it fails**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: compilation fails because the scene/menu APIs do not exist.

- [ ] **Step 3: Implement the scene ticker and responsive composition**

Use `SingleTickerProviderStateMixin` and a `5.2 s` repeating controller. Do not start the controller when `MediaQuery.disableAnimationsOf(context)` is true. Reconcile the controller in `didChangeDependencies` so runtime accessibility changes take effect.

The scene must be a `ColoredBox` plus `RepaintBoundary`/`CustomPaint` stack. Place the title/date at the Pencil coordinates, the authored line adjacent to Reka, and a `64 × 64 px` transparent semantic hotspot over `TodayDotSceneGeometry.rekaCenter`.

The hotspot uses:

```dart
Semantics(
  label: 'Reka 快捷操作',
  button: true,
  expanded: _menuOpen,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onRekaTap,
    child: const SizedBox.square(dimension: 64),
  ),
)
```

Do not attach a gesture detector to the background painter.

- [ ] **Step 4: Implement the compact anchored quick-action menu**

Define:

```dart
enum TodayRekaAction { createAsset, createReport, startChat }
```

Use `showMenu<TodayRekaAction>` anchored to the Reka `Rect`. Build three `PopupMenuItem`s with stable keys and labels. Disable an item when its callback is null. After the route returns, invoke exactly the selected callback. Do not mutate data or animate the dot painter.

- [ ] **Step 5: Run the focused interaction tests**

Run the Task 3 command.

Expected: PASS.

- [ ] **Step 6: Commit scene and menu**

```bash
git add mobile/lib/theme_v2/home/today_dot_matrix_scene.dart mobile/lib/theme_v2/home/today_reka_quick_actions.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat: add living reka dot scene"
```

---

### Task 4: Add no-spinner refresh and recoverable repository state

**Files:**

- Create: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

**Interfaces:**

- Produces: `TodayDotExperimentPage({ThemeV2HomeRepository? repository, VoidCallback? onCreateAsset, VoidCallback? onCreateReport, VoidCallback? onStartChat})`.
- Consumes: `TodayDotMatrixScene` and `showTodayRekaQuickActions` from Task 3.
- Consumes: existing `ThemeV2HomeRepository.load()`.
- Consumes later: Theme V2 shell from Task 5.

- [ ] **Step 1: Add failing refresh tests**

Use a fake repository with a queued `Completer<TodayData>`. Verify:

```dart
await tester.drag(find.byKey(TodayDotExperimentPage.scrollKey), const Offset(0, 180));
await tester.pump();
expect(repository.loadCount, 1);
expect(find.bySemanticsLabel('正在刷新今日'), findsOneWidget);
```

Complete the request and assert the semantics disappears while the empty scene remains. Add a failure case that asserts `刷新失败，已保留当前场景` and a `重试` action. Tap Retry and assert `loadCount == 2`. Drag twice during an unresolved request and assert calls remain coalesced at one.

- [ ] **Step 2: Run the focused test and verify it fails**

Run the Task 3 test command.

Expected: compilation fails because `TodayDotExperimentPage` does not exist.

- [ ] **Step 3: Implement repository ownership and serial request protection**

Mirror the established Home ownership pattern:

```dart
late ThemeV2HomeRepository _repository;
late bool _ownsRepository;
int _requestSerial = 0;
bool _refreshing = false;
bool _refreshFailed = false;
```

`_refresh()` returns the in-flight `Future<void>` when already refreshing. It calls `load()`, ignores late serials, preserves the experiment scene, and changes only refresh/error state. Dispose an owned `ApiThemeV2HomeRepository` exactly as the current Home does.

- [ ] **Step 4: Implement no-spinner pull refresh and dot emphasis**

Use:

```dart
RefreshIndicator.noSpinner(
  onRefresh: _refresh,
  onStatusChange: _handleRefreshStatus,
  child: CustomScrollView(
    key: TodayDotExperimentPage.scrollKey,
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: TodayDotMatrixScene(...),
      ),
    ],
  ),
)
```

Map drag/armed/snap/refresh statuses to refresh emphasis `1`; animate back to `0` over `320 ms` after completion/cancel. The painter changes top-band alpha only.

Overlay a polite live-region semantic label while refreshing. On failure, show a compact Material message with Retry; never replace the scene with an initial full-screen error.

- [ ] **Step 5: Run the experiment page tests**

Run the Task 3 test command.

Expected: PASS.

- [ ] **Step 6: Commit refresh behavior**

```bash
git add mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat: add today dot refresh loop"
```

---

### Task 5: Wire mature routes and prove fallback isolation

**Files:**

- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**

- Consumes: `TodayDotExperimentPage` from Task 4.
- Consumes: `showCreateMenu(BuildContext context)`.
- Consumes: `ReportContainerPage(autoStartCreate: true)`.
- Consumes: `ChatPage(startBlank: true, themeV2Override: true)`.

- [ ] **Step 1: Write failing shell selection tests**

Mount the production shell with `showStartupOverlays: false`, a fake Home repository, and explicit overrides:

```dart
await tester.pumpWidget(
  ThemeV2TestApp(
    child: ThemeV2AppShell(
      homeRepository: const _FakeHomeRepository(TodayData.empty),
      todayDotExperimentOverride: true,
      showStartupOverlays: false,
    ),
  ),
);
await tester.pump();
expect(find.byType(TodayDotExperimentPage), findsOneWidget);
expect(find.byType(ThemeV2HomePage), findsNothing);
```

Repeat with `todayDotExperimentOverride: false` and reverse the expectations. Also run the existing Home test file unchanged to prove fallback isolation.

- [ ] **Step 2: Run shell and fallback tests and verify selection fails**

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: the new selection assertion fails because `_pages()` still always constructs `ThemeV2HomePage`; existing Home tests remain green.

- [ ] **Step 3: Add route adapters and select the page at the shell boundary**

Import `create_asset.dart`, `chat_page.dart`, and the experiment page. Add:

```dart
void _openBlankChat(BuildContext context) {
  Navigator.of(context).push(
    themeV2Route<void>(
      context: context,
      builder: (_) => const ChatPage(
        startBlank: true,
        themeV2Override: true,
      ),
    ),
  );
}
```

In the Today page slot:

```dart
body: widget.usesTodayDotExperiment
    ? TodayDotExperimentPage(
        repository: widget.homeRepository,
        onCreateAsset: () => showCreateMenu(context),
        onCreateReport: () => _openReports(context, startCreate: true),
        onStartChat: () => _openBlankChat(context),
      )
    : ThemeV2HomePage(
        active: _index == 0,
        repository: widget.homeRepository,
        rekaSignals: widget.rekaSignalRepository,
        onOpenReka: () => _openRekaSignals(context),
        onOpenReports: () => _openReports(context),
        onCreateReport: () => _openReports(context, startCreate: true),
      ),
```

Do not modify Calendar or Library selection.

- [ ] **Step 4: Run shell, fallback, and interaction tests**

```bash
cd mobile
flutter test \
  test/theme_v2/theme_v2_rollout_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart \
  test/theme_v2/home/theme_v2_home_page_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit shell integration**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat: wire today dot experiment routes"
```

---

### Task 6: Lock visual output and validate on the target device

**Files:**

- Create: `mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-experiment-empty-411-light.png`
- Create: `mobile/test/theme_v2/home/goldens/today-dot-experiment-empty-tall-light.png`

**Interfaces:**

- Consumes: completed experiment surface from Tasks 2–5.
- Produces: deterministic visual baselines and a device-build validation record in the task handoff.

- [ ] **Step 1: Write the golden host**

Create a deterministic Light host with `devicePixelRatio: 1`, `disableAnimations: true`, no text scaling, injected fake repository, canonical top navigation, and canonical Dock. Cover `411 × 860` and `411 × 960`.

```dart
await expectLater(
  find.byKey(surfaceKey),
  matchesGoldenFile('goldens/today-dot-experiment-empty-411-light.png'),
);
```

Use a second filename for the tall viewport.

- [ ] **Step 2: Generate and inspect the Goldens**

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: two PNGs are generated. Inspect them visually against Pencil `zjzLR`; adjust only experiment constants, never the Pencil source or current Home.

- [ ] **Step 3: Run focused and regression verification**

```bash
cd mobile
dart format lib/config.dart lib/theme_v2/home lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/theme_v2_rollout_test.dart
flutter analyze lib/config.dart lib/theme_v2/home lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/theme_v2_rollout_test.dart
flutter test \
  test/theme_v2/theme_v2_rollout_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart \
  test/theme_v2/home/theme_v2_home_page_test.dart \
  test/theme_v2/home/theme_v2_home_golden_test.dart \
  test/theme_v2/home/today_dot_matrix_painter_test.dart \
  test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/theme_v2/home/today_dot_experiment_golden_test.dart
```

Expected: analyzer has no issues and every test passes.

- [ ] **Step 4: Build the experiment APK**

```bash
cd mobile
flutter build apk --debug --dart-define=TODAY_DOT_EXPERIMENT=true --dart-define=START_THEME=light
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced successfully.

- [ ] **Step 5: Install and launch on the connected Android device**

Run the exact target-device commands:

```bash
cd mobile
flutter devices
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Verify:

- the empty dot scene is visible;
- Reka breathes locally without moving the full grid;
- tapping Reka opens three actions;
- every action opens the existing target flow;
- pull refresh produces top-band opacity feedback with no spinner;
- the scene remains responsive for at least two minutes;
- disabling the flag and rebuilding restores the existing Home.

- [ ] **Step 6: Commit visual baselines**

```bash
git add mobile/test/theme_v2/home/today_dot_experiment_golden_test.dart mobile/test/theme_v2/home/goldens/today-dot-experiment-empty-411-light.png mobile/test/theme_v2/home/goldens/today-dot-experiment-empty-tall-light.png
git commit -m "test: lock today dot experiment visuals"
```
