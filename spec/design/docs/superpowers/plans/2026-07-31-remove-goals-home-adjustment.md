# Remove Goals and Adjust Theme V2 Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Goals from the current product source of truth and ship a Theme V2 Home that renders Today as its only visible layer while retaining an invisible generic secondary-layer boundary.

**Architecture:** The current codebase has no production Goal model, route, repository, or service, so this plan does not create deletion work for nonexistent code. It adds a focused Theme V2 Home module backed by the existing `TodayData` loader, represents the second layer as nullable generic state, mounts the new Home from `ThemeV2AppShell`, and archives Goal canvas/docs outside implementation sources.

**Tech Stack:** Flutter/Dart, `flutter_test`, Theme V2 tokens, existing `TodayData`/`loadToday`, Pencil `.pen` design tooling, golden image tests.

## Global Constraints

- Current viewport reference is exactly 411 × 960.
- Current Home renders Today only.
- Home panel geometry is `x=8, y=54, w=395, h=790` in full-screen coordinates.
- Dock geometry remains `x=121, y=865, w=169, h=60`.
- `secondary` is `null`, invisible, non-interactive, non-semantic, and has no reserved visible space.
- Do not add a Goal feature flag, placeholder, teaser, route, model, repository, API, cache, notification, or analytics event.
- Do not remove user-authored text merely because it contains `目标`.
- Do not alter the approved three-step Skill Builder behavior while cleaning historical layer names.
- Light and Dark must share one widget/component tree.
- Use existing Theme V2 tokens and the current Geist/Geist Mono typography.

---

## File Structure

### Create

- `mobile/lib/theme_v2/home/home_layer_state.dart` — generic primary/nullable-secondary Home state.
- `mobile/lib/theme_v2/home/home_controller.dart` — Today/Agenda presentation state only.
- `mobile/lib/theme_v2/home/home_repository.dart` — testable adapter around existing `loadToday`.
- `mobile/lib/theme_v2/home/theme_v2_home_page.dart` — data lifecycle and promoted panel geometry.
- `mobile/lib/theme_v2/home/home_today_panel.dart` — Today default surface.
- `mobile/lib/theme_v2/home/home_agenda_panel.dart` — Agenda/Fishbone surface.
- `mobile/test/theme_v2/home/home_layer_state_test.dart` — nullable-layer and controller tests.
- `mobile/test/theme_v2/home/theme_v2_home_page_test.dart` — geometry, semantics, and interaction tests.
- `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart` — 411 × 960 Light/Dark golden harness.
- `mobile/test/theme_v2/home/goldens/home-today-411-light.png`
- `mobile/test/theme_v2/home/goldens/home-today-411-dark.png`
- `mobile/test/theme_v2/home/goldens/home-agenda-411-light.png`
- `mobile/test/theme_v2/home/goldens/home-agenda-411-dark.png`

### Modify

- `spec/design/redesignureka.pen` — promote Today screens, archive Goal screens, replace Home motion contract, and clean Skill Builder layer names.
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart` — mount `ThemeV2HomePage` and hide global top nav for Home.
- `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart` — verify production Home shell chrome.
- `mobile/test/theme_v2/shell/theme_v2_shell_test.dart` — verify Home retains Dock and omits top nav.
- `spec/design/theme-v2-coding-handoff.md` — remove Goal phases/routes and describe Today-only Home.
- `spec/design/design-goal-core.md` — mark archive only.
- `spec/design/design-goals-proactive-reka.md` — mark archive only.
- `spec/design/design-habit-streak.md` — mark archive where it depends on the Goal implementation.

### Preserve

- `mobile/lib/pages/today_page.dart` — legacy shell continues to use it; do not mix Theme V2 Home work into the legacy page.
- `mobile/lib/today/today_data.dart` — reuse the current data contract; only change if a test exposes a genuine adapter defect.
- Asset tests asserting that `设定目标` is absent.

---

### Task 1: Update the Pencil Home implementation source

**Files:**

- Modify: `spec/design/redesignureka.pen`

**Interfaces:**

- Consumes: approved source nodes `WsOyv`, `PMCdg`, `vRy65`, `J5cpE`, `PYuZt`
  (`Section / Theme V2 / 40 Today / Implementation Source`).
- Produces: four current Home reference screens with promoted Today geometry and no visible Goal affordance.

- [ ] **Step 1: Record the current reference screenshots**

Use Pencil `get_screenshot` for:

```text
WsOyv  Light Today default
PMCdg  Dark Today default
vRy65  Light Today Agenda
J5cpE  Dark Today Agenda
```

Expected: each current screenshot has an exposed Goal header above a Today panel beginning at `y=104`.

- [ ] **Step 2: Promote the Light Today default panel**

Within `WsOyv`:

```text
Delete/disable wqNr2  Goals Back Page / Exposed Header
Delete/disable qLSvD  Home Kicker
Delete/disable B3Z1Cv Two Layer Switch / Today Active
Update WF8fM           x=8, y=54, width=395, height=790
Update YRDqv           width=395, height=790
```

Keep `cWZZJ` and `N3641j` unchanged.

- [ ] **Step 3: Promote the Dark Today default panel**

Within `PMCdg`:

```text
Delete/disable VTseo  Goals Back Page / Exposed Header
Delete/disable n7GLj  Home Kicker
Delete/disable AYuX9  Two Layer Switch / Today Active
Update zWoZO          x=8, y=54, width=395, height=790
Update rWGEY          width=395, height=790
```

Keep `LnpXF` and `t9gKI` unchanged.

- [ ] **Step 4: Promote the Light Agenda panel**

Within `vRy65`:

```text
Delete/disable q1WC2   Goals Back Page / Exposed Header
Delete/disable rZyNe   Home Kicker
Delete/disable Q2x4mM  Two Layer Switch / Today Active
Update SbbbL           x=8, y=54, width=395, height=790
Update FkbCD           width=395, height=790
Update xcnLs           y=40, width=395, height=750
```

Move the generated-asset chamber group down by 50 px so its base remains near the panel bottom:

```text
LKt86, oTjHh, z4EOLR, w7JLaf,
Oeb2v, t7aGX6, BXCl8, Z4S9G, c6BdO, k0HhKq,
VgrcQ, QGQ1n, iVpp0, hnWUw, Z9XZAr, JCFUO,
B8vv7w, nEc9a, GQbU6, y6x71R, kzAsA
```

For every listed node: `newY = oldY + 50`.

Extend `R9MiVZ` from height `556` to `606`; keep all event cards and their time meaning unchanged.

- [ ] **Step 5: Promote the Dark Agenda panel**

Within `J5cpE`:

```text
Delete/disable RVR4D   Goals Back Page / Exposed Header
Delete/disable hb8vs   Home Kicker
Delete/disable vxHCC   Two Layer Switch / Today Active
Update Vwra6           x=8, y=54, width=395, height=790
Update J1fRLq          width=395, height=790
Update foLYq           y=40, width=395, height=750
```

Move the Dark generated-asset chamber group down by 50 px:

```text
Q7j1ku, LbzxC, bDsl8, EsVka,
wWwU5, zFHoU, K3jeU, n3mlm8, gZvEg, NT7n7,
dVqmr, tlFRe, MT7Fw, HlzN1, tebqE, K4aAYq,
OofcO, sUPzi, bQstg, d12bA, RgYSC
```

For every listed node: `newY = oldY + 50`.

Extend `U3nEZ` from height `556` to `606`.

- [ ] **Step 6: Remove Goal-derived queue examples**

Within the four production Home frames, delete rows/cards whose visible content or semantic metadata represents:

```text
Goal progress
Goal settlement
Goal deadline
Goal check-in
Goal adjustment
Goal suggestion
```

Do not delete an ordinary Todo title such as `更新个人目标`.

- [ ] **Step 7: Archive Goal canvas sources**

Create or reuse one root archive frame named:

```text
ARCHIVE · DO NOT IMPLEMENT · Theme V2 Goals
```

Move or clearly group under it:

```text
N0ehb
SuznI
BNmyJ
all Goal Setting screens
all All Goals screens
all Goal Detail / adjustment screens
```

Set archive metadata:

```json
{
  "type": "archive",
  "implementation": false,
  "reason": "Goals removed from current product scope"
}
```

Do not delete the archived design work.

- [ ] **Step 8: Replace the Home interaction contract**

Update `VvGFs` to state:

```text
Current runtime: Today only.
secondaryLayer = null.
No exposed back header, horizontal layer switching, edge reveal, or placeholder.
Agenda expand/collapse remains active.
```

Update `PYuZt` description from a Today/Goals contract to a Today-only runtime contract.

- [ ] **Step 9: Clean Skill Builder layer names**

Inside `WLBLn`, rename layer names only:

```text
Goal Setting Header       → Skill Builder Header
Goal Step Segment         → Skill Step Segment
Goal Step Label           → Skill Step Label
Goal Natural Language Input → Skill Natural Language Input
Goal Direction            → Skill Example Direction
Goal Agent Note           → Skill Agent Note
Generate Goal Draft       → Generate Skill Draft
Confirm and Create Goal   → Confirm and Create Skill
Redescribe Goal           → Return to Fields
```

Do not change visible copy or the three-step Skill Builder behavior.

- [ ] **Step 10: Validate the canvas**

Use Pencil `Get` visitors to assert:

```text
Today panels: x=8, y=54, width=395, height=790
Dock nodes: unchanged
No layout problem on the four production Home screens
No visible text named 目标 inside the four production Home screens
```

Take final screenshots of `WsOyv`, `PMCdg`, `vRy65`, and `J5cpE`.

Expected: Light/Dark Today and Agenda are visually balanced, Goal affordances are absent, and the generated chamber remains bottom-aligned.

- [ ] **Step 11: Commit**

```bash
git add spec/design/redesignureka.pen
git commit -m "design(theme-v2): remove goals and promote today home"
```

---

### Task 2: Add the generic Home layer and controller contracts

**Files:**

- Create: `mobile/lib/theme_v2/home/home_layer_state.dart`
- Create: `mobile/lib/theme_v2/home/home_controller.dart`
- Test: `mobile/test/theme_v2/home/home_layer_state_test.dart`

**Interfaces:**

- Consumes: no Goal types.
- Produces: `HomeLayerState.current`, `ThemeV2HomeController`, and `HomePresentation`.

- [ ] **Step 1: Write the failing state tests**

```dart
import 'package:eureka/theme_v2/home/home_controller.dart';
import 'package:eureka/theme_v2/home/home_layer_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current Home exposes Today only', () {
    expect(HomeLayerState.current.primary, HomeSurface.today);
    expect(HomeLayerState.current.secondary, isNull);
    expect(HomeLayerState.current.hasSecondary, isFalse);
  });

  test('controller toggles Agenda without creating a second layer', () {
    final controller = ThemeV2HomeController();
    addTearDown(controller.dispose);

    expect(controller.presentation, HomePresentation.today);
    controller.openAgenda();
    expect(controller.presentation, HomePresentation.agenda);
    expect(controller.layers.secondary, isNull);
    controller.closeAgenda();
    expect(controller.presentation, HomePresentation.today);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/home_layer_state_test.dart
```

Expected: FAIL because the Home contracts do not exist.

- [ ] **Step 3: Implement `HomeLayerState`**

```dart
enum HomeSurface { today }

class HomeLayerState {
  const HomeLayerState({
    this.primary = HomeSurface.today,
    this.secondary,
  });

  final HomeSurface primary;
  final HomeSurface? secondary;

  bool get hasSecondary => secondary != null;

  static const current = HomeLayerState();
}
```

- [ ] **Step 4: Implement `ThemeV2HomeController`**

```dart
import 'package:flutter/foundation.dart';

import 'home_layer_state.dart';

enum HomePresentation { today, agenda }

class ThemeV2HomeController extends ChangeNotifier {
  ThemeV2HomeController({
    this.layers = HomeLayerState.current,
    HomePresentation initialPresentation = HomePresentation.today,
  }) : _presentation = initialPresentation;

  final HomeLayerState layers;
  HomePresentation _presentation;

  HomePresentation get presentation => _presentation;

  void openAgenda() => _setPresentation(HomePresentation.agenda);
  void closeAgenda() => _setPresentation(HomePresentation.today);

  void _setPresentation(HomePresentation value) {
    if (_presentation == value) return;
    _presentation = value;
    notifyListeners();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/home_layer_state_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/home/home_layer_state.dart \
  mobile/lib/theme_v2/home/home_controller.dart \
  mobile/test/theme_v2/home/home_layer_state_test.dart
git commit -m "feat(theme-v2): add today-only home state"
```

---

### Task 3: Add a testable Home data adapter

**Files:**

- Create: `mobile/lib/theme_v2/home/home_repository.dart`
- Test: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**

- Consumes: `TodayData`, `loadToday(ApiClient)`.
- Produces: `ThemeV2HomeRepository.load()` and `ApiThemeV2HomeRepository`.

- [ ] **Step 1: Add a failing repository seam test**

Add to `theme_v2_home_page_test.dart`:

```dart
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake repository returns supported Today data without Goal state', () async {
    const expected = TodayData.empty;
    final repository = _FakeHomeRepository(expected);

    expect(await repository.load(), same(expected));
  });
}

class _FakeHomeRepository implements ThemeV2HomeRepository {
  const _FakeHomeRepository(this.value);
  final TodayData value;

  @override
  Future<TodayData> load() async => value;
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: FAIL because `ThemeV2HomeRepository` does not exist.

- [ ] **Step 3: Implement the repository adapter**

```dart
import '../../api/api_client.dart';
import '../../today/today_data.dart';

abstract interface class ThemeV2HomeRepository {
  Future<TodayData> load();
}

class ApiThemeV2HomeRepository implements ThemeV2HomeRepository {
  ApiThemeV2HomeRepository({ApiClient? api})
      : _api = api ?? ApiClient(),
        _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<TodayData> load() => loadToday(_api);

  void dispose() {
    if (_ownsApi) _api.close();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/home/home_repository.dart \
  mobile/test/theme_v2/home/theme_v2_home_page_test.dart
git commit -m "feat(theme-v2): add home data adapter"
```

---

### Task 4: Implement the promoted Today and Agenda panels

**Files:**

- Create: `mobile/lib/theme_v2/home/home_today_panel.dart`
- Create: `mobile/lib/theme_v2/home/home_agenda_panel.dart`
- Create: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**

- Consumes: `TodayData`, `ThemeV2HomeController`, `ThemeV2HomeRepository`.
- Produces: `ThemeV2HomePage`, `HomeTodayPanel`, `HomeAgendaPanel`.

- [ ] **Step 1: Write failing geometry and absence tests**

Add:

```dart
testWidgets('Home promotes Today and exposes no secondary layer', (tester) async {
  final controller = ThemeV2HomeController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    _HomeHost(
      child: ThemeV2HomePage(
        controller: controller,
        repository: const _FakeHomeRepository(TodayData.empty),
      ),
    ),
  );
  await tester.pump();

  final panel = find.byKey(ThemeV2HomePage.panelKey);
  expect(tester.getTopLeft(panel), const Offset(8, 54));
  expect(tester.getSize(panel), const Size(395, 790));
  expect(find.text('目标'), findsNothing);
  expect(find.bySemanticsLabel('打开目标'), findsNothing);
});

testWidgets('Agenda uses the same promoted panel geometry', (tester) async {
  final controller = ThemeV2HomeController(
    initialPresentation: HomePresentation.agenda,
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    _HomeHost(
      child: ThemeV2HomePage(
        controller: controller,
        repository: const _FakeHomeRepository(TodayData.empty),
      ),
    ),
  );
  await tester.pump();

  expect(find.byType(HomeAgendaPanel), findsOneWidget);
  expect(
    tester.getSize(find.byKey(ThemeV2HomePage.panelKey)),
    const Size(395, 790),
  );
});
```

Use a host with exact screen padding:

```dart
class _HomeHost extends StatelessWidget {
  const _HomeHost({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(
        size: Size(411, 960),
        devicePixelRatio: 1,
        padding: EdgeInsets.only(top: 44),
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            bottom: false,
            child: child,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: FAIL because Home widgets do not exist.

- [ ] **Step 3: Implement responsive reference geometry**

In `ThemeV2HomePage` define:

```dart
import 'dart:math' as math;

static const panelKey = ValueKey<String>('theme-v2-home-panel');
static const referencePanelSize = Size(395, 790);
static const referenceLeft = 8.0;
static const referenceTopAfterSafeArea = 10.0;

Size _panelSize(BoxConstraints constraints) {
  final width = constraints.maxWidth >= 411
      ? referencePanelSize.width
      : math.max(0, constraints.maxWidth - 16);
  final height = math.min(
    referencePanelSize.height,
    math.max(0, constraints.maxHeight - referenceTopAfterSafeArea),
  );

  return Size(
    width.toDouble(),
    height.toDouble(),
  );
}
```

Position the panel with:

```dart
Positioned(
  key: panelKey,
  left: referenceLeft,
  top: referenceTopAfterSafeArea,
  width: panelSize.width,
  height: panelSize.height,
  child: presentation == HomePresentation.today
      ? HomeTodayPanel(data: data, onOpenAgenda: controller.openAgenda)
      : HomeAgendaPanel(data: data, onCloseAgenda: controller.closeAgenda),
)
```

The host SafeArea supplies the first 44 px, so the panel’s full-screen top is `44 + 10 = 54`.

- [ ] **Step 4: Implement page data lifecycle**

`ThemeV2HomePage` must:

```dart
class ThemeV2HomePage extends StatefulWidget {
  const ThemeV2HomePage({
    super.key,
    this.controller,
    this.repository,
  });

  final ThemeV2HomeController? controller;
  final ThemeV2HomeRepository? repository;
}
```

Lifecycle rules:

```text
Own and dispose the controller only when it was not injected.
Own and dispose ApiThemeV2HomeRepository only when repository was not injected.
Reload on dataRevision changes.
Show ThemeV2AsyncState.loading while no prior data exists.
Keep prior data during refresh.
Show ThemeV2AsyncState.error with retry only when the initial load fails.
Never request Goal data.
```

- [ ] **Step 5: Implement `HomeTodayPanel`**

Structure:

```text
Panel surface / radius 18 / Theme V2 border
Header: 今日 + localized date summary
Next Moment section from data.chain
Reka Queue section from supported Today data
Asset bubble field from data.pool
Agenda expand action with 44 × 44 target
```

The widget API is:

```dart
class HomeTodayPanel extends StatelessWidget {
  const HomeTodayPanel({
    super.key,
    required this.data,
    required this.onOpenAgenda,
  });

  final TodayData data;
  final VoidCallback onOpenAgenda;
}
```

Do not add a Goal count, Goal CTA, secondary-layer switch, or horizontal gesture detector.

- [ ] **Step 6: Implement `HomeAgendaPanel`**

The widget API is:

```dart
class HomeAgendaPanel extends StatelessWidget {
  const HomeAgendaPanel({
    super.key,
    required this.data,
    required this.onCloseAgenda,
  });

  final TodayData data;
  final VoidCallback onCloseAgenda;
}
```

Structure:

```text
Header and 44 × 44 collapse action
Expanded agenda/fishbone viewport
Generated asset chamber pinned to the bottom
No Home-layer horizontal gesture
```

Use an `Expanded` agenda region and a fixed-height generated chamber so the reclaimed 50 px benefits the agenda rather than moving the bottom chamber upward.

- [ ] **Step 7: Run tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/home_layer_state_test.dart \
  test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/theme_v2/home \
  mobile/test/theme_v2/home/home_layer_state_test.dart \
  mobile/test/theme_v2/home/theme_v2_home_page_test.dart
git commit -m "feat(theme-v2): add promoted today home"
```

---

### Task 5: Mount Theme V2 Home in the app shell

**Files:**

- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

**Interfaces:**

- Consumes: `ThemeV2HomePage`.
- Produces: production Theme V2 tab 0 with no top nav, persistent Dock, and no Goal layer.

- [ ] **Step 1: Write the failing shell test**

Add:

```dart
testWidgets('production shell mounts Today-only Theme V2 Home', (tester) async {
  await tester.pumpWidget(
    const _ThemeHost(
      child: ThemeV2AppShell(
        initialIndex: 0,
        showStartupOverlays: false,
      ),
    ),
  );
  await tester.pump();

  expect(find.byType(ThemeV2HomePage), findsOneWidget);
  expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
  expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
  expect(find.text('目标'), findsNothing);
});
```

- [ ] **Step 2: Run the shell test to verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: FAIL because the shell still mounts legacy `TodayPage` and shows the top nav.

- [ ] **Step 3: Replace the Theme V2 tab-0 body**

In `theme_v2_app_shell.dart`:

```dart
import '../home/theme_v2_home_page.dart';
```

Replace:

```dart
ThemeV2PageScaffold(body: TodayPage(active: _index == 0))
```

with:

```dart
const ThemeV2PageScaffold(
  body: ThemeV2HomePage(),
  showTopNav: false,
)
```

Remove the now-unused Theme V2 shell import of `../../pages/today_page.dart`.

- [ ] **Step 4: Verify shell persistence**

Keep the existing `IndexedStack` and keyed page behavior. Add an assertion that switching Calendar → Home does not recreate Home state:

```dart
expect(find.byType(ThemeV2HomePage), findsOneWidget);
await tester.tap(find.bySemanticsLabel('日历'));
await tester.pump();
await tester.tap(find.bySemanticsLabel('今日'));
await tester.pump();
expect(find.byType(ThemeV2HomePage), findsOneWidget);
```

- [ ] **Step 5: Run shell tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart \
  mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat(theme-v2): mount today-only home"
```

---

### Task 6: Add Home visual regression coverage

**Files:**

- Create: `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`
- Create: four files under `mobile/test/theme_v2/home/goldens/`

**Interfaces:**

- Consumes: `ThemeV2HomePage`, fake `ThemeV2HomeRepository`, fixed 411 × 960 fixtures.
- Produces: Light/Dark Today and Agenda golden baselines.

- [ ] **Step 1: Create deterministic fixtures**

Build one fixed `TodayData` with:

```text
one timed event
one unscheduled Todo
three pool assets
flashCount = 2
todoDone = 1
todoTotal = 3
fixed timestamps on 2026-07-31
```

Do not include any Goal item or Goal-derived field.

- [ ] **Step 2: Write the golden test**

Use the project’s existing golden pattern:

```dart
testWidgets('Theme V2 Home matches 411 Light and Dark', (tester) async {
  for (final brightness in Brightness.values) {
    for (final presentation in HomePresentation.values) {
      final controller = ThemeV2HomeController(
        initialPresentation: presentation,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _GoldenHomeHost(
          brightness: brightness,
          child: ThemeV2HomePage(
            controller: controller,
            repository: _FakeHomeRepository(homeFixture),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mode = brightness == Brightness.light ? 'light' : 'dark';
      final state =
          presentation == HomePresentation.today ? 'today' : 'agenda';
      await expectLater(
        find.byType(ThemeV2HomePage),
        matchesGoldenFile('goldens/home-$state-411-$mode.png'),
      );
    }
  }
});
```

- [ ] **Step 3: Generate the goldens**

Run:

```bash
cd mobile
flutter test --update-goldens \
  test/theme_v2/home/theme_v2_home_golden_test.dart
```

Expected: four PNG files generated.

- [ ] **Step 4: Inspect every golden**

Verify:

```text
no Goal header/count/arrow
panel top = 54 in full-screen coordinates
panel bottom = 844
Dock center and bottom clearance unchanged
Agenda generated chamber remains near the bottom
Light/Dark geometry is identical
```

- [ ] **Step 5: Run without updating**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_golden_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/test/theme_v2/home
git commit -m "test(theme-v2): add today home goldens"
```

---

### Task 7: Remove Goal from active handoffs and mark archives

**Files:**

- Modify: `spec/design/theme-v2-coding-handoff.md`
- Modify: `spec/design/design-goal-core.md`
- Modify: `spec/design/design-goals-proactive-reka.md`
- Modify: `spec/design/design-habit-streak.md`
- Reference: `spec/design/docs/superpowers/specs/2026-07-31-remove-goals-home-adjustment-design.md`

**Interfaces:**

- Consumes: approved Goal-removal spec.
- Produces: current implementation documents with no Goal phase or production source ambiguity.

- [ ] **Step 1: Update the primary coding handoff**

In `theme-v2-coding-handoff.md`:

```text
Remove P5 Goal Core.
Remove Goal screens from the implementation whitelist.
Remove Today/Goals switching rules.
Remove + Goal, Goal detail, Goal history, Goal calculation, and Goal Evidence requirements.
Describe Home runtime as Today only.
Document secondaryLayer = null and no horizontal cross-layer gesture.
Keep Dock destinations Today / Calendar / Library.
```

- [ ] **Step 2: Add archive banners**

At the beginning of each Goal-dependent document add:

```markdown
> **ARCHIVE · DO NOT IMPLEMENT**
>
> Goals are outside the current product and implementation scope as of
> 2026-07-31. This document is retained for historical reference only and must
> not be used as a coding source.
```

For `design-habit-streak.md`, limit the archive warning to sections whose implementation depends on the removed Goal module; do not incorrectly archive independent habit research.

- [ ] **Step 3: Verify active documents**

Run:

```bash
cd spec/design
rg -n "P5|Goals Layer|Goal Setting|\\+ Goal|设定目标|目标详情" \
  theme-v2-coding-handoff.md theme-v2-library-assets-handoff.md
```

Expected:

- no active implementation requirement for Goals;
- historical archive links are allowed only when explicitly labeled archive;
- asset tests and handoff still permit ordinary user text containing `目标`.

- [ ] **Step 4: Validate Markdown**

Run:

```bash
cd spec/design
git diff --check -- \
  theme-v2-coding-handoff.md \
  design-goal-core.md \
  design-goals-proactive-reka.md \
  design-habit-streak.md
```

Expected: no whitespace errors.

- [ ] **Step 5: Commit**

```bash
git add spec/design/theme-v2-coding-handoff.md \
  spec/design/design-goal-core.md \
  spec/design/design-goals-proactive-reka.md \
  spec/design/design-habit-streak.md
git commit -m "docs(theme-v2): archive goals and update home scope"
```

---

### Task 8: Run the Goal-absence and full Theme V2 regression gate

**Files:**

- Verify: `mobile/lib/`
- Verify: `mobile/test/theme_v2/`
- Verify: current design and handoff files

**Interfaces:**

- Consumes: all preceding tasks.
- Produces: evidence that Home is Today-only and existing Calendar, Library, Asset, Session, and shell behavior remains intact.

- [ ] **Step 1: Confirm no Goal production module was introduced**

Run:

```bash
rg -n -i "class .*Goal|GoalRepository|GoalRoute|GoalService|GoalApi|GoalCache" \
  mobile/lib
```

Expected: no production Goal domain implementation.

- [ ] **Step 2: Confirm existing asset entry tests remain green**

Run:

```bash
cd mobile
flutter test \
  test/theme_v2/library/asset/asset_list_page_test.dart \
  test/theme_v2/library/asset/asset_detail_test.dart
```

Expected: PASS, including existing assertions that `设定目标` is absent.

- [ ] **Step 3: Run Home and shell tests**

Run:

```bash
cd mobile
flutter test \
  test/theme_v2/home \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run the complete Theme V2 suite**

Run:

```bash
cd mobile
flutter test test/theme_v2
```

Expected: PASS.

- [ ] **Step 5: Run static analysis on touched code**

Run:

```bash
cd mobile
dart format --output=none --set-exit-if-changed \
  lib/theme_v2/home \
  lib/theme_v2/shell/theme_v2_app_shell.dart \
  test/theme_v2/home \
  test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  test/theme_v2/shell/theme_v2_shell_test.dart
flutter analyze \
  lib/theme_v2/home \
  lib/theme_v2/shell/theme_v2_app_shell.dart \
  test/theme_v2/home
```

Expected: no formatting or analysis errors.

- [ ] **Step 6: Perform final canvas inspection**

Use Pencil screenshots for:

```text
WsOyv
PMCdg
vRy65
J5cpE
PYuZt
```

Expected: current Home source contains only Today runtime screens; Goal work is visibly archived and not mixed with the implementation source.

- [ ] **Step 7: Commit final verification fixes**

If verification required tracked fixes:

```bash
git add \
  mobile/lib/theme_v2/home \
  mobile/lib/theme_v2/shell/theme_v2_app_shell.dart \
  mobile/test/theme_v2/home \
  mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart \
  mobile/test/theme_v2/shell/theme_v2_shell_test.dart \
  spec/design/redesignureka.pen \
  spec/design/theme-v2-coding-handoff.md \
  spec/design/design-goal-core.md \
  spec/design/design-goals-proactive-reka.md \
  spec/design/design-habit-streak.md
git commit -m "fix(theme-v2): complete goal removal verification"
```

If no files changed, do not create an empty commit.
