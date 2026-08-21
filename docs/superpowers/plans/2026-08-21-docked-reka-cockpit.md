# Docked Reka Cockpit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Replace the flat mini Reka above the Theme V2 Dock with one native 3D Reka seated in a raised central cockpit, make tap resume the latest Session, preserve long-press Flash capture, and hand one Reka between Today and Dock pages.

**Architecture:** ThemeV2FloatingDock owns the glass shell and cockpit geometry while a focused RekaDockCockpit projection listens to the existing Shell-owned companion controller. RekaMini renders native depth without a WebView; ThemeV2AppShell owns direct Session routing and a bounded 260 ms visual-proxy handoff that suppresses both source hit targets during transition. Existing voice, Terminal, Session, and Flash pipelines remain unchanged.

**Tech Stack:** Flutter/Dart, CustomPainter, AnimationController, existing RekaCompanionController and RekaVoiceCaptureCoordinator, Theme V2 tokens, Flutter widget/golden tests, Android build and ADB.

## Global Constraints

- The glass Dock shell is exactly 248 × 64 logical pixels; bottom safe-area padding remains outside the shell.
- The cockpit hit target is exactly 76 × 72; native Reka is 66 × 48 with 14 pixels visually seated inside the Dock.
- Today and Calendar keep 44 × 44 targets on the left; Library keeps at least 44 × 44 in the right region; no fourth destination is added.
- Today renders only its full Three.js/fallback Reka; Calendar and Library render only the native cockpit Reka.
- Tap opens ChatPage(themeV2Override: true) without startBlank, so existing resumeLast() restores the latest Session or shows the existing empty surface.
- Long press begins Flash capture, upward movement uses the existing cancellation threshold, release sends once, and an armed release creates no Flash.
- The quick-action menu is deleted and is not moved to another gesture.
- Terminal state, dwell durations, ASR protocol, Flash pipeline, Session data model, and single global microphone owner do not change.
- The visual handoff lasts 260 ms; reduced motion uses a zero-travel crossfade.
- At most one Reka hit target is active; during the bounded handoff the native proxy is visual-only.
- Dock-free routes and Bottom Sheets render neither cockpit Reka nor Terminal.
- State color is redundant with eye shape and Terminal copy; color never carries state alone.

---

## File Structure

**Create:**
- mobile/test/theme_v2/shell/reka_mini_test.dart — native body, eye-state, motion, semantics, and gesture contract.
- mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart — exact cockpit geometry, navigation targets, state light, and safe-area behavior.

**Modify:**
- mobile/lib/theme_v2/shell/reka_mini.dart — native 3D renderer and provider-neutral Reka gestures.
- mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart — expanded glass shell, navigation regions, neutral central recess, and clearance constants.
- mobile/lib/theme_v2/shell/reka_shell_companion.dart — controller-listening Dock projection, Terminal anchor, and handoff proxy.
- mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart — content clearance from Dock composition geometry.
- mobile/lib/theme_v2/shell/theme_v2_app_shell.dart — direct Session resume, transition state, and unified callbacks.
- mobile/lib/theme_v2/home/today_dot_experiment_page.dart — direct tap and explicit Reka visibility.
- mobile/lib/theme_v2/home/today_reka_scene.dart — suppress render and hit target during handoff.
- mobile/test/theme_v2/shell/reka_shell_companion_test.dart
- mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart
- mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
- mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
- mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
- mobile/test/theme_v2/home/today_reka_scene_test.dart
- nearest Shell golden harness and affected images under mobile/test/theme_v2/**/goldens/.

**Delete:**
- mobile/lib/theme_v2/home/today_reka_quick_actions.dart — obsolete menu implementation.

---

### Task 1: Render a native 3D mini Reka

**Files:**
- Modify: mobile/lib/theme_v2/shell/reka_mini.dart
- Create: mobile/test/theme_v2/shell/reka_mini_test.dart

**Interfaces:**
- Consumes: RekaTerminalPhase? from reka_terminal_models.dart.
- Produces: RekaMini.phase, visualSize == Size(66, 48), targetExtent == 72, rekaMiniEyePattern(), and a reduced-motion-safe native renderer.

- [ ] **Step 1: Write failing visual-state and geometry tests**

~~~dart
testWidgets('native mini Reka keeps exact visual and target geometry', (
  tester,
) async {
  await tester.pumpWidget(_host(RekaMini(
    phase: null,
    onTap: (_) {},
    onLongPressStart: () {},
    onLongPressMove: (_) {},
    onLongPressEnd: () {},
    onLongPressCancel: () {},
  )));

  expect(tester.getSize(find.byKey(RekaMini.targetKey)), const Size.square(72));
  expect(tester.getSize(find.byKey(RekaMini.visualKey)), const Size(66, 48));
  expect(find.byKey(RekaMini.shellKey), findsOneWidget);
  expect(find.byKey(RekaMini.visorKey), findsOneWidget);
});

test('eye patterns distinguish non-color capture states', () {
  expect(
    rekaMiniEyePattern(RekaTerminalPhase.listening, left: true),
    isNot(rekaMiniEyePattern(RekaTerminalPhase.cancelArmed, left: true)),
  );
  expect(
    rekaMiniEyePattern(RekaTerminalPhase.receiving, left: true),
    isNot(rekaMiniEyePattern(RekaTerminalPhase.receiving, left: false)),
  );
  expect(
    rekaMiniEyePattern(RekaTerminalPhase.done, left: true),
    isNot(rekaMiniEyePattern(RekaTerminalPhase.failed, left: true)),
  );
});
~~~

- [ ] **Step 2: Write failing gesture and reduced-motion tests**

~~~dart
testWidgets('long press reports movement and never also taps', (tester) async {
  var taps = 0;
  var starts = 0;
  var ends = 0;
  final offsets = <double>[];
  await tester.pumpWidget(_host(RekaMini(
    phase: RekaTerminalPhase.listening,
    onTap: (_) => taps++,
    onLongPressStart: () => starts++,
    onLongPressMove: offsets.add,
    onLongPressEnd: () => ends++,
    onLongPressCancel: () {},
  )));

  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(RekaMini.targetKey)),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
  await gesture.moveBy(const Offset(0, -80));
  await gesture.up();
  await tester.pump();

  expect((starts, ends, taps), (1, 1, 0));
  expect(offsets.last, closeTo(-80, .01));
});

testWidgets('reduced motion leaves no repeating mini Reka ticker', (
  tester,
) async {
  await tester.pumpWidget(_host(
    RekaMini(
      phase: RekaTerminalPhase.listening,
      onTap: (_) {},
      onLongPressStart: () {},
      onLongPressMove: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () {},
    ),
    disableAnimations: true,
  ));
  await tester.pump(const Duration(seconds: 2));
  expect(tester.binding.hasScheduledFrame, isFalse);
});
~~~

- [ ] **Step 3: Run the new test and verify RED**

~~~bash
cd mobile
flutter test test/theme_v2/shell/reka_mini_test.dart
~~~

Expected: FAIL because phase, shellKey, visorKey, the 66 × 48 geometry, and rekaMiniEyePattern do not exist.

- [ ] **Step 4: Implement the minimal native renderer**

Use this public surface:

~~~dart
class RekaMini extends StatefulWidget {
  const RekaMini({
    super.key,
    required this.phase,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  static const targetKey = ValueKey<String>('reka-mini-target');
  static const visualKey = ValueKey<String>('reka-mini-visual');
  static const shellKey = ValueKey<String>('reka-mini-shell');
  static const visorKey = ValueKey<String>('reka-mini-visor');
  static const Size visualSize = Size(66, 48);
  static const double targetExtent = 72;

  final RekaTerminalPhase? phase;
}
~~~

Use SingleTickerProviderStateMixin only while animations are enabled. Stop and reset breathing when MediaQuery.disableAnimationsOf(context) is true. Paint contact shadow, warm shell gradient, lower shade, dark visor gradient, side modules, highlight, and pixel eyes inside a RepaintBoundary. Never create a WebView.

Define the exhaustive eye mapping:

~~~dart
@visibleForTesting
List<int> rekaMiniEyePattern(RekaTerminalPhase? phase, {required bool left}) =>
    switch (phase) {
      null || RekaTerminalPhase.connecting =>
        const [0, 1, 2, 3, 5, 6, 7, 8],
      RekaTerminalPhase.listening =>
        const [0, 1, 2, 3, 4, 5, 6, 7, 8],
      RekaTerminalPhase.cancelArmed => const [0, 2, 4, 6, 8],
      RekaTerminalPhase.transcribing => const [0, 1, 2, 6, 7, 8],
      RekaTerminalPhase.receiving =>
        left ? const [0, 3, 6] : const [2, 5, 8],
      RekaTerminalPhase.sending ||
      RekaTerminalPhase.understanding => const [1, 3, 4, 5, 7],
      RekaTerminalPhase.organizing => const [0, 4, 8],
      RekaTerminalPhase.done => const [1, 3, 4, 5],
      RekaTerminalPhase.empty => const [3, 4, 5],
      RekaTerminalPhase.failed =>
        left ? const [0, 4, 8] : const [2, 4, 6],
    };
~~~

- [ ] **Step 5: Verify GREEN and commit**

~~~bash
flutter test test/theme_v2/shell/reka_mini_test.dart
flutter analyze lib/theme_v2/shell/reka_mini.dart test/theme_v2/shell/reka_mini_test.dart
git add mobile/lib/theme_v2/shell/reka_mini.dart mobile/test/theme_v2/shell/reka_mini_test.dart
git commit -m "feat(mobile): render native 3d reka mini"
~~~

Expected: tests pass and analyzer reports No issues found!.

---

### Task 2: Build the raised Dock cockpit and exact clearance

**Files:**
- Modify: mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart
- Modify: mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart
- Create: mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart
- Modify: mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart

**Interfaces:**
- Consumes: Widget? rekaCockpit; the child owns live phase presentation so controller updates do not rebuild the whole Dock.
- Produces: shellSize, compositionHeight, cockpitExtent, cockpitRise, cockpitKey, cockpitTopAboveDockBottom, and companionContentClearance.

- [ ] **Step 1: Write failing exact-geometry tests**

~~~dart
testWidgets('Dock owns one 248x64 shell and one 76x72 cockpit', (
  tester,
) async {
  await tester.pumpWidget(_host(ThemeV2FloatingDock(
    selectedIndex: 1,
    onDestinationSelected: (_) {},
    rekaCockpit: const SizedBox(key: ValueKey('cockpit-child')),
  )));

  expect(
    tester.getSize(find.byKey(ThemeV2FloatingDock.dockKey)),
    const Size(248, 64),
  );
  expect(
    tester.getSize(find.byKey(ThemeV2FloatingDock.cockpitKey)),
    const Size(76, 72),
  );
  expect(find.byKey(const ValueKey('cockpit-child')), findsOneWidget);
  for (final label in const ['今日', '日历', '资产']) {
    expect(
      tester.getSize(find.bySemanticsLabel(label)).shortestSide,
      greaterThanOrEqualTo(44),
    );
  }
});
~~~

- [ ] **Step 2: Write failing neutral-recess and clearance tests**

~~~dart
testWidgets('Today keeps an empty recess without a Reka hit target', (
  tester,
) async {
  await tester.pumpWidget(_host(ThemeV2FloatingDock(
    selectedIndex: 0,
    onDestinationSelected: (_) {},
  )));
  expect(find.byKey(ThemeV2FloatingDock.cockpitKey), findsOneWidget);
  expect(find.bySemanticsLabel(startsWith('Reka，')), findsNothing);
});

testWidgets('page clearance derives from Dock composition geometry', (
  tester,
) async {
  await tester.pumpWidget(_pageScaffoldHost());
  final scaffold = tester.getRect(find.byType(Scaffold));
  final body = tester.getRect(find.byKey(const ValueKey('test-body')));
  expect(
    scaffold.bottom - body.bottom,
    ThemeV2FloatingDock.companionContentClearance,
  );
  expect(
    ThemeV2FloatingDock.companionContentClearance,
    ThemeV2FloatingDock.compositionHeight +
        ThemeV2FloatingDock.contentGap,
  );
});
~~~

- [ ] **Step 3: Run focused tests and verify RED**

~~~bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_floating_dock_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart
~~~

Expected: FAIL because the current Dock is 169 × 60, has no cockpit child/recess, and uses the old 136 clearance.

- [ ] **Step 4: Implement one glass shell with fixed regions**

Add these constants and inputs:

~~~dart
static const Size shellSize = Size(248, 64);
static const double cockpitExtent = 76;
static const double cockpitTargetExtent = 72;
static const double cockpitRise = 34;
static const double compositionHeight = 98;
static const double contentGap = 12;
static const double companionContentClearance =
    compositionHeight + contentGap;
static const double cockpitTopAboveDockBottom = compositionHeight;
static const compositionKey =
    ValueKey<String>('theme-v2-dock-composition');
static const cockpitKey = ValueKey<String>('theme-v2-reka-cockpit');

final Widget? rekaCockpit;
~~~

Build a 98-pixel composition: position the 248 × 64 glass shell at the bottom, reserve 88 pixels for two 44-pixel left targets, 76 for the cockpit, and 84 for Library. Position the 76 × 72 cockpit at horizontal center and 34 pixels above the shell top. Render the recess even with a null child; only the child supplies semantics and gestures.

The empty recess uses only a low-intensity theme-derived neutral reflection. Live state illumination belongs to the controller-listening RekaDockCockpit in Task 4, preventing the whole navigation Dock from subscribing to capture updates.

Keep ThemeV2PageScaffold formula-based:

~~~dart
final bottomClearance = showDock && !extendBodyBehindChrome
    ? ThemeV2FloatingDock.companionContentClearance +
          MediaQuery.paddingOf(context).bottom
    : 0.0;
~~~

- [ ] **Step 5: Verify compact layouts and commit**

~~~bash
flutter test test/theme_v2/shell/theme_v2_floating_dock_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter analyze lib/theme_v2/shell/theme_v2_floating_dock.dart lib/theme_v2/shell/theme_v2_page_scaffold.dart test/theme_v2/shell/theme_v2_floating_dock_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart
git add mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart mobile/test/theme_v2/shell/theme_v2_floating_dock_test.dart mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart
git commit -m "feat(mobile): embed a reka cockpit in the dock"
~~~

Expected: Dock/scaffold/navigation tests pass without overflow and analyzer is clean.

---

### Task 3: Replace the quick-action menu with direct Session resume

**Files:**
- Modify: mobile/lib/theme_v2/shell/theme_v2_app_shell.dart
- Modify: mobile/lib/theme_v2/home/today_dot_experiment_page.dart
- Delete: mobile/lib/theme_v2/home/today_reka_quick_actions.dart
- Modify: mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
- Modify: mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart

**Interfaces:**
- Produces: _resumeChat(BuildContext) and a direct onStartChat tap path.
- Removes: showTodayRekaQuickActions, TodayRekaAction, _openQuickActions, _menuExpanded, and _openRekaQuickActions.

- [ ] **Step 1: Replace the menu test with a failing direct-tap test**

~~~dart
testWidgets('Today Reka tap resumes Session without a menu', (tester) async {
  var opens = 0;
  await tester.pumpWidget(_Host(
    child: TodayDotExperimentPage(
      repository: _ImmediateRepository(TodayData.empty),
      onStartChat: () => opens++,
      rekaBuilder: _staticReka,
    ),
  ));
  await tester.pump();

  await tester.tap(find.byKey(TodayRekaScene.rekaTargetKey));
  await tester.pump();

  expect(opens, 1);
  expect(find.text('手动记录'), findsNothing);
  expect(find.text('创建报告'), findsNothing);
  expect(find.text('开始新聊天'), findsNothing);
});
~~~

- [ ] **Step 2: Add a failing Shell route test**

~~~dart
testWidgets('Reka tap pushes resumable Theme V2 ChatPage', (tester) async {
  final harness = _RekaHarness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(_shellHost(harness: harness, initialIndex: 1));

  await tester.tap(find.byKey(RekaMini.targetKey));
  await tester.pumpAndSettle();

  final page = tester.widget<ChatPage>(find.byType(ChatPage));
  expect(page.themeV2Override, isTrue);
  expect(page.startBlank, isFalse);
  expect(find.byType(PopupMenuItem), findsNothing);
});
~~~

- [ ] **Step 3: Run focused tests and verify RED**

~~~bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
~~~

Expected: old popup appears and Shell route uses startBlank: true.

- [ ] **Step 4: Implement direct resume and delete obsolete API**

In Shell:

~~~dart
void _resumeChat(BuildContext context) {
  final callback = widget.onStartChat;
  if (callback != null) {
    callback();
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ChatPage(themeV2Override: true),
    ),
  );
}
~~~

Pass _resumeChat(context) to both Today and Dock Reka. In TodayDotExperimentPage delete _menuExpanded, _openQuickActions, the quick-actions import, and the now-unused onManualRecord/onCreateReport constructor fields. Keep onStartChat:

~~~dart
onRekaTap: (_) => widget.onStartChat?.call(),
menuExpanded: false,
~~~

Delete today_reka_quick_actions.dart using apply_patch after removing imports and tests.

- [ ] **Step 5: Verify symbols are gone and commit**

~~~bash
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/session/session_state_test.dart
rg "showTodayRekaQuickActions|TodayRekaAction|today_reka_quick_actions" lib test
flutter analyze lib/theme_v2/home/today_dot_experiment_page.dart lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
git add mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git add -u mobile/lib/theme_v2/home/today_reka_quick_actions.dart
git commit -m "feat(mobile): open Session directly from reka"
~~~

Expected: focused tests pass, rg returns no matches, and analyzer is clean.

---

### Task 4: Integrate the cockpit and hand off one Reka

**Files:**
- Modify: mobile/lib/theme_v2/shell/reka_shell_companion.dart
- Modify: mobile/lib/theme_v2/shell/theme_v2_app_shell.dart
- Modify: mobile/lib/theme_v2/home/today_dot_experiment_page.dart
- Modify: mobile/lib/theme_v2/home/today_reka_scene.dart
- Modify: mobile/test/theme_v2/shell/reka_shell_companion_test.dart
- Modify: mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
- Modify: mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
- Modify: mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
- Modify: mobile/test/theme_v2/home/today_reka_scene_test.dart

**Interfaces:**
- Produces: RekaDockCockpit, rekaCockpitLightColor(), RekaShellHandoffDirection, handoffDirection, handoffEpoch, TodayDotExperimentPage.rekaVisible, and TodayRekaScene.rekaVisible.
- Consumes: Task 1 RekaMini.phase and Task 2 Dock cockpit geometry.

- [ ] **Step 1: Write failing Dock projection and Terminal-anchor tests**

~~~dart
testWidgets('Dock projection follows companion phase', (tester) async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(_host(ThemeV2FloatingDock(
    selectedIndex: 1,
    onDestinationSelected: (_) {},
    rekaCockpit: RekaDockCockpit(
      controller: harness.companion,
      onTap: (_) {},
      onLongPressStart: () {},
      onLongPressMove: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () {},
    ),
  )));

  expect(tester.widget<RekaMini>(find.byType(RekaMini)).phase, isNull);
  final initialLightDecoration = tester.widget<DecoratedBox>(
    find.byKey(RekaDockCockpit.lightKey),
  ).decoration;
  harness.activities.apply(_understandingEvent());
  await tester.pump();
  expect(
    tester.widget<RekaMini>(find.byType(RekaMini)).phase,
    RekaTerminalPhase.understanding,
  );
  expect(
    tester.widget<DecoratedBox>(
      find.byKey(RekaDockCockpit.lightKey),
    ).decoration,
    isNot(initialLightDecoration),
  );
});

testWidgets('Dock Terminal remains above the cockpit', (tester) async {
  await tester.pumpWidget(_activeDockCompanionHost());
  expect(
    tester.getBottomLeft(find.byType(RekaTerminal)).dy,
    lessThanOrEqualTo(
      tester.getTopLeft(find.byKey(ThemeV2FloatingDock.cockpitKey)).dy - 10,
    ),
  );
});
~~~

- [ ] **Step 2: Write failing one-Reka handoff tests**

~~~dart
testWidgets('Today to Calendar exposes only the proxy for 260ms', (
  tester,
) async {
  await tester.pumpWidget(_realShellHost(disableAnimations: false));
  expect(find.byKey(TodayRekaScene.rekaTargetKey), findsOneWidget);
  expect(find.byKey(RekaMini.targetKey), findsNothing);

  await tester.tap(find.bySemanticsLabel('日历'));
  await tester.pump();
  expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsOneWidget);
  expect(find.byKey(TodayRekaScene.rekaTargetKey), findsNothing);
  expect(find.byKey(RekaMini.targetKey), findsNothing);

  await tester.pump(const Duration(milliseconds: 259));
  expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsNothing);
  expect(find.byKey(RekaMini.targetKey), findsOneWidget);
});
~~~

Add reverse Calendar-to-Today and reduced-motion cases. In every frame assert Reka semantics count is at most one.

- [ ] **Step 3: Write failing explicit Today visibility test**

~~~dart
testWidgets('hidden Today Reka keeps content but removes render and target', (
  tester,
) async {
  await tester.pumpWidget(_sceneHost(rekaVisible: false));
  expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
  expect(find.byKey(TodayRekaScene.rekaRenderKey), findsNothing);
  expect(find.byKey(TodayRekaScene.rekaTargetKey), findsNothing);
});
~~~

- [ ] **Step 4: Run focused suite and verify RED**

~~~bash
cd mobile
flutter test test/theme_v2/shell/reka_shell_companion_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_reka_scene_test.dart
~~~

Expected: missing projection/handoff APIs and current mini Reka still floats independently.

- [ ] **Step 5: Implement the controller-listening Dock projection**

Add:

~~~dart
enum RekaShellHandoffDirection { toDock, toToday }

class RekaDockCockpit extends StatefulWidget {
  const RekaDockCockpit({
    super.key,
    required this.controller,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });
  final RekaCompanionController controller;
  final ValueChanged<Rect> onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<double> onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
}
~~~

Its State attaches one controller listener and builds the state light and mini Reka together. Define:

~~~dart
static const lightKey = ValueKey<String>('reka-dock-cockpit-light');

@visibleForTesting
Color rekaCockpitLightColor(
  RekaTerminalPhase? phase,
  Brightness brightness,
) => switch (phase) {
  null => brightness == Brightness.dark
      ? const Color(0x2EFFFFFF)
      : const Color(0x245E7180),
  RekaTerminalPhase.connecting || RekaTerminalPhase.listening =>
    const Color(0xAA53DDF5),
  RekaTerminalPhase.cancelArmed ||
  RekaTerminalPhase.failed ||
  RekaTerminalPhase.empty => const Color(0xAEEF6878),
  RekaTerminalPhase.transcribing ||
  RekaTerminalPhase.receiving ||
  RekaTerminalPhase.sending ||
  RekaTerminalPhase.understanding ||
  RekaTerminalPhase.organizing => const Color(0xAA826CFF),
  RekaTerminalPhase.done => const Color(0xAA78D98B),
};
~~~

Build a Stack whose DecoratedBox at lightKey uses that color and whose foreground is:

~~~dart
RekaMini(
  phase: widget.controller.terminal?.phase,
  onTap: widget.onTap,
  onLongPressStart: widget.onLongPressStart,
  onLongPressMove: widget.onLongPressMove,
  onLongPressEnd: widget.onLongPressEnd,
  onLongPressCancel: widget.onLongPressCancel,
)
~~~

Keep RekaShellCompanion responsible for Terminal layout and visual proxy. Dock Terminal bottom is:

~~~dart
bottom: bottomPadding +
    ThemeV2FloatingDock.cockpitTopAboveDockBottom +
    RekaShellCompanion.terminalGap,
~~~

- [ ] **Step 6: Implement bounded Shell handoff and Today suppression**

Add to ThemeV2AppShellState:

~~~dart
static const rekaHandoffDuration = Duration(milliseconds: 260);
Timer? _rekaHandoffTimer;
RekaShellHandoffDirection? _rekaHandoffDirection;
int _rekaHandoffEpoch = 0;

void _startRekaHandoff(RekaShellHandoffDirection direction) {
  _rekaHandoffTimer?.cancel();
  setState(() {
    _rekaHandoffDirection = direction;
    _rekaHandoffEpoch++;
  });
  _rekaHandoffTimer = Timer(rekaHandoffDuration, () {
    if (mounted) setState(() => _rekaHandoffDirection = null);
  });
}
~~~

In _selectDestination, start toDock for 0 → 1/2, toToday for 1/2 → 0, and no handoff for 1 ↔ 2. Cancel the timer in dispose.

Pass rekaVisible: _index == 0 && _rekaHandoffDirection == null into Today. Add rekaVisible default true to TodayDotExperimentPage and TodayRekaScene; conditionally omit both rekaRenderKey and rekaTargetKey while content stays mounted.

The IgnorePointer handoff proxy interpolates from todayRekaController.rekaCenter to the Dock cockpit center and from full-size scale to 1. Reduced motion interpolates opacity only. Key it by handoffEpoch. Pass RekaDockCockpit to the Dock only when _index != 0 and no handoff; retain the empty recess otherwise.

- [ ] **Step 7: Verify GREEN, repetition gates, and commit**

~~~bash
flutter test test/theme_v2/shell/reka_shell_companion_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_reka_scene_test.dart
for i in 1 2 3 4 5; do flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart --plain-name 'Today to Calendar exposes only the proxy for 260ms'; done
flutter analyze lib/theme_v2/shell/reka_shell_companion.dart lib/theme_v2/shell/theme_v2_app_shell.dart lib/theme_v2/home/today_dot_experiment_page.dart lib/theme_v2/home/today_reka_scene.dart test/theme_v2/shell/reka_shell_companion_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_reka_scene_test.dart
git add mobile/lib/theme_v2/shell/reka_shell_companion.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/lib/theme_v2/home/today_reka_scene.dart mobile/test/theme_v2/shell/reka_shell_companion_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart mobile/test/theme_v2/home/today_reka_scene_test.dart
git commit -m "feat(mobile): hand reka into the dock cockpit"
~~~

Expected: focused tests and five repetitions pass; analyzer is clean.

---

### Task 5: Lock baselines, regress, build, and install

**Files:**
- Modify: nearest Shell golden test under mobile/test/theme_v2/shell/.
- Create/Modify: only affected images under mobile/test/theme_v2/**/goldens/.

**Interfaces:**
- Consumes: completed Tasks 1–4.
- Produces: reviewed visual baselines, a clean branch, and a local-backend APK installed on RFCY71B21YK.

- [ ] **Step 1: Add focused golden scenarios**

Add idle light/dark, listening light/dark, understanding, cancel-armed, Terminal-open, and reduced-motion cases. Each test renders ThemeV2FloatingDock.compositionKey and uses a phase-specific filename:

~~~dart
await expectLater(
  find.byKey(ThemeV2FloatingDock.compositionKey),
  matchesGoldenFile('goldens/reka-cockpit-listening-light.png'),
);
~~~

- [ ] **Step 2: Verify failures are missing baselines only**

~~~bash
cd mobile
flutter test test/theme_v2/shell --plain-name 'Dock cockpit'
~~~

Expected before creation: missing-golden failures only. Overflow, exception, or unrelated pixel difference is a code defect.

- [ ] **Step 3: Generate only approved baselines and re-run**

~~~bash
flutter test test/theme_v2/shell --plain-name 'Dock cockpit' --update-goldens
flutter test test/theme_v2/shell --plain-name 'Dock cockpit'
~~~

Expected: focused golden suite passes. Inspect every PNG at original resolution before staging.

- [ ] **Step 4: Run full regression and analyzer**

~~~bash
flutter test test/voice_input test/theme_v2/capture test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_reka_scene_test.dart test/theme_v2/shell test/theme_v2/session
flutter analyze lib/capture_activity lib/voice_input lib/theme_v2/capture lib/theme_v2/home lib/theme_v2/shell lib/theme_v2/library test/voice_input test/theme_v2/capture test/theme_v2/home test/theme_v2/shell test/theme_v2/session
git diff --check
~~~

Expected: all tests pass, analyzer reports No issues found!, and diff check prints nothing.

- [ ] **Step 5: Commit reviewed baselines**

~~~bash
git status --short
git add mobile/test/theme_v2/shell
git commit -m "test(mobile): lock docked reka visuals"
~~~

Stage only the new cockpit test harness and reviewed PNGs.

- [ ] **Step 6: Build the local-chain APK**

~~~bash
curl -fsS http://127.0.0.1:8000/health
curl -fsS http://127.0.0.1:8100/ready
flutter build apk --debug --dart-define=API_BASE=http://localhost:8000
shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
~~~

Expected: both health endpoints return success JSON, build exits zero, and SHA-256 is printed.

- [ ] **Step 7: Install and launch**

~~~bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$ADB -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s RFCY71B21YK reverse tcp:8000 tcp:8000
$ADB -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$ADB -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
$ADB -s RFCY71B21YK shell pidof com.eureka.mindapp
~~~

Expected: install prints Success, launch injects one event, and pidof returns a process ID.

- [ ] **Step 8: Perform the physical checklist**

1. Today shows only full Reka and an empty Dock recess.
2. Calendar transition shows one proxy for 260 ms, then only cockpit Reka.
3. Tap cockpit Reka resumes the latest Session; no history shows the existing empty Session.
4. Long press and speak Mandarin, then release: live text appears, one Flash sends, and assets complete.
5. Long press, move upward past the existing threshold, and release: cancellation appears and no Flash is created.
6. Repeat in English.
7. Calendar/Library content remains reachable; Dock-free routes show no Reka/Terminal.
8. Reduced motion uses a crossfade without travel.

Record a device-only defect as a failing regression test before production changes.

- [ ] **Step 9: Prove final status**

~~~bash
git status --short
git log --oneline -6
~~~

Expected: working tree is clean and task commits are visible on codex/skill-dither-report-revamp.
