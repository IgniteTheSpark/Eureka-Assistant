# Theme V2 Session and Today Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Session keyboard and turn-count behavior, add the existing global top navigation to Today, and replace Today’s static Asset bubble layout with the existing Forge2D gravity/collision behavior.

**Architecture:** Session derives one shared user-turn count and passes it to both count consumers. The app shell exposes its existing `ThemeV2GlobalTopNav` on Today. A new focused Theme V2 bubble-field widget adapts the shared `BubbleField` physics core while owning Theme V2 rendering, sensor/ticker lifecycle, Core Record navigation, and Reduce Motion fallback.

**Tech Stack:** Flutter/Dart, Flutter widget tests, Forge2D 0.14.2+1, sensors_plus 7.0.0, Android ADB.

## Global Constraints

- Follow strict red-green-refactor: every production change starts with a test that fails for the intended reason.
- Do not add or upgrade dependencies; `forge2d` and `sensors_plus` are already present.
- Do not change backend APIs, Session persistence, or database schema.
- A Session turn is exactly one `ChatMessage.isUser == true`; Agent replies and streaming updates do not increment it.
- Today must show the existing `ThemeV2GlobalTopNav` and retain the existing `ThemeV2FloatingDock`.
- Theme V2 bubble taps must use `AssetEntityKind.asset` with `coreRecordsOnly: true`.
- Do not import or mount the legacy `BubblePool`; reuse only the shared `BubbleField` physics core.
- Reduce Motion must use a stable static layout without a Ticker or accelerometer subscription.
- Do not restore legacy Home horizontal switching, long-press type filtering, Dashboard, or legacy Asset APIs.
- Commit and push only `codex/theme-v2-ui-refactor`; do not merge `main`.

## File Structure

- `mobile/lib/theme_v2/session/session_composer.dart`: dismisses keyboard before asynchronous send.
- `mobile/lib/theme_v2/session/theme_v2_session_page.dart`: owns the shared user-turn calculation and distributes it.
- `mobile/lib/theme_v2/session/session_header.dart`: renders the supplied turn count.
- `mobile/lib/theme_v2/session/session_transcript.dart`: renders the supplied turn count as the watermark while preserving message-based scrolling.
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`: enables Today’s top navigation and supplies Home active state.
- `mobile/lib/today/bubble_physics.dart`: keeps the common Forge2D world and makes its Dock collider optional.
- `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`: new Theme V2 physics adapter, rendering, gestures, sensor lifecycle, and Core Record open action.
- `mobile/lib/theme_v2/home/theme_v2_home_page.dart`: accepts whether Today is the visible tab and passes that state downward.
- `mobile/lib/theme_v2/home/home_today_panel.dart`: hosts the extracted physics bubble field and removes the old static bubble implementation.
- `mobile/test/theme_v2/session/session_state_test.dart`: keyboard and user-turn regression coverage.
- `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`: Today top-nav integration coverage.
- `mobile/test/today/bubble_physics_test.dart`: deterministic gravity, bounds, and circle-collision coverage for the shared physics core.
- `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`: Theme V2 animation, Reduce Motion, active-state, semantics, and tap coverage.
- `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`: keeps Today composition and bubble-field integration coverage.

---

### Task 1: Session keyboard dismissal and user-turn count

**Files:**
- Modify: `mobile/test/theme_v2/session/session_state_test.dart`
- Modify: `mobile/lib/theme_v2/session/session_composer.dart`
- Modify: `mobile/lib/theme_v2/session/theme_v2_session_page.dart`
- Modify: `mobile/lib/theme_v2/session/session_header.dart`
- Modify: `mobile/lib/theme_v2/session/session_transcript.dart`

**Interfaces:**
- Produces: `int sessionTurnCount(Iterable<ChatMessage> messages)`.
- Produces: `SessionHeader(turnCount: int, ...)`.
- Produces: `SessionTranscript(turnCount: int, ...)`.
- Preserves: message-count-based transcript scrolling, focus targeting, and content signatures.

- [ ] **Step 1: Add the keyboard and turn-count regression tests**

Add a pending-send seam to `FakeSessionController`:

```dart
final Completer<void>? sendCompleter;

FakeSessionController({
  List<ChatMessage>? messages,
  this.streaming = false,
  this.error,
  List<SessionInfo>? sessions,
  List<({String id, String label})>? contextAssets,
  this.loadCompleter,
  this.loadCompleters,
  this.sendCompleter,
  this.listFailuresRemaining = 0,
}) : messages = messages ?? [],
     sessions = sessions ?? [],
     contextAssets = contextAssets ?? [];

@override
Future<void> send(String text) async {
  await sendCompleter?.future;
}
```

Add these tests before changing production code:

```dart
testWidgets('sending dismisses the keyboard before the request completes', (
  tester,
) async {
  final pending = Completer<void>();
  final controller = FakeSessionController(sendCompleter: pending);
  await _pumpSession(tester, controller: controller);

  final field = find.byKey(const ValueKey('session-composer-field'));
  await tester.tap(field);
  await tester.enterText(field, '今天有什么待办？');
  expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

  await tester.tap(find.byKey(const ValueKey('session-send')));
  await tester.pump();

  expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
  pending.complete();
  await tester.pump();
});

testWidgets('header and watermark count user turns instead of messages', (
  tester,
) async {
  final messages = <ChatMessage>[];
  for (var index = 0; index < 6; index++) {
    messages
      ..add(ChatMessage.user('u-$index', '第 ${index + 1} 次输入'))
      ..add(_assistant('第 ${index + 1} 次回复', streaming: index == 5));
  }
  await _pumpSession(
    tester,
    controller: FakeSessionController(messages: messages, streaming: true),
  );

  expect(find.text('06'), findsNWidgets(2));
  expect(find.text('12'), findsNothing);
});
```

- [ ] **Step 2: Run the two tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/session/session_state_test.dart --plain-name "sending dismisses the keyboard before the request completes"
flutter test test/theme_v2/session/session_state_test.dart --plain-name "header and watermark count user turns instead of messages"
```

Expected failures:

- keyboard test reports `Expected: false, Actual: true`;
- count test reports no `06` widgets because the current UI renders `12`.

- [ ] **Step 3: Implement the minimal shared turn count and keyboard dismissal**

In `session_composer.dart`, change `_submit` to:

```dart
Future<void> _submit(String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty || streaming) return;
  controller.clear();
  focusNode.unfocus();
  await onSend(trimmed);
}
```

In `theme_v2_session_page.dart`, add the pure helper next to `SessionViewState`:

```dart
int sessionTurnCount(Iterable<ChatMessage> messages) {
  return messages.where((message) => message.isUser).length;
}
```

In `_buildPage`, compute the value once and pass it to both consumers:

```dart
final turnCount = sessionTurnCount(state.messages);

SessionHeader(
  title: title,
  turnCount: turnCount,
  onBack: _back,
  onNewSession: widget.readOnly ? null : _newConversation,
  onOpenHistory: widget.readOnly
      ? null
      : () => _scaffoldKey.currentState?.openDrawer(),
),

SessionTranscript(
  messages: state.messages,
  turnCount: turnCount,
  analyzing: state.surface == SessionSurfaceState.analyzing,
  error: state.error,
  onRetry: () => unawaited(_controller.retryLastFailedTurn()),
  onKeepDraft: _inputFocusNode.requestFocus,
  onPrecipitate: _precipitate,
  onStarter: (text) => unawaited(_controller.send(text)),
  emptyOpener: widget.emptyOpener,
  emptyStarters: widget.emptyStarters,
  focusedInputTurnId: widget.focusedInputTurnId,
),
```

Rename the `SessionHeader` constructor/property from `messageCount` to `turnCount` and render:

```dart
Text(
  turnCount.toString().padLeft(2, '0'),
  style: ThemeV2Typography.mono(
    color: tokens.muted,
    fontSize: 8,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  ),
),
```

Add `required this.turnCount` and `final int turnCount;` to `SessionTranscript`; change only its watermark to:

```dart
Text(
  widget.turnCount.toString().padLeft(2, '0'),
  style: TextStyle(
    color: tokens.watermark,
    fontSize: 96,
    fontWeight: FontWeight.w600,
    height: 1,
  ),
),
```

Do not replace `_lastMessageCount`, `widget.messages.length` in scroll estimation, or structural-change detection.

- [ ] **Step 4: Run Session tests and verify GREEN**

Run:

```bash
cd mobile
flutter test test/theme_v2/session/session_state_test.dart
flutter test test/theme_v2/capture/flash_notification_target_test.dart
```

Expected: both files finish with `All tests passed!`.

- [ ] **Step 5: Commit Task 1**

```bash
git add mobile/lib/theme_v2/session/session_composer.dart mobile/lib/theme_v2/session/theme_v2_session_page.dart mobile/lib/theme_v2/session/session_header.dart mobile/lib/theme_v2/session/session_transcript.dart mobile/test/theme_v2/session/session_state_test.dart
git commit -m "fix: align theme v2 session turn behavior"
```

---

### Task 2: Today global top navigation

**Files:**
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`

**Interfaces:**
- Consumes: the existing `ThemeV2GlobalTopNav` built once by `ThemeV2AppShell`.
- Produces: Today `ThemeV2PageScaffold` with `showTopNav == true` and the existing floating Dock unchanged.

- [ ] **Step 1: Change the Today shell test to require the top navigation**

Replace the production Today test with:

```dart
testWidgets('production Today exposes top navigation and floating dock', (
  tester,
) async {
  var deviceTaps = 0;
  var notificationTaps = 0;
  await tester.pumpWidget(
    _ThemeHost(
      child: ThemeV2AppShell(
        initialIndex: 0,
        showStartupOverlays: false,
        deviceStatus: const DeviceStatusSummary.disconnected(),
        onDevicePressed: () => deviceTaps++,
        onNotificationsPressed: () => notificationTaps++,
      ),
    ),
  );
  await tester.pump();

  expect(find.byType(ThemeV2HomePage), findsOneWidget);
  expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
  expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
  expect(find.text('目标'), findsNothing);

  await tester.tap(find.bySemanticsLabel('设备：未连接'));
  await tester.tap(find.bySemanticsLabel('通知'));
  expect(deviceTaps, 1);
  expect(notificationTaps, 1);
  expect(tester.takeException(), isNull);

  await tester.tap(find.bySemanticsLabel('日历'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('今日'));
  await tester.pump();
  expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
});
```

- [ ] **Step 2: Run the Today shell test and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart --plain-name "production Today exposes top navigation and floating dock"
```

Expected: FAIL because `ThemeV2GlobalTopNav` is absent on index 0.

- [ ] **Step 3: Enable the existing top navigation on Today**

Change the first production page declaration in `_pages()` to:

```dart
const ThemeV2PageScaffold(body: ThemeV2HomePage()),
```

Do not construct a second nav inside `ThemeV2HomePage`; `withShellChrome` must continue injecting the shell-owned instance.

- [ ] **Step 4: Run shell and Today geometry tests and verify GREEN**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter test test/theme_v2/shell/theme_v2_shell_test.dart
flutter test test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: all files finish with `All tests passed!`; Today retains the Dock and has no overflow exception.

- [ ] **Step 5: Commit Task 2**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "fix: expose global navigation on today"
```

---

### Task 3: Generalize the shared Forge2D field for a panel without a Dock obstacle

**Files:**
- Create: `mobile/test/today/bubble_physics_test.dart`
- Modify: `mobile/lib/today/bubble_physics.dart`

**Interfaces:**
- Produces: `BubbleField({required Size box, Rect? dock, Offset gravity = const Offset(0, 20)})`.
- Preserves: legacy callers that pass `dock:` and all existing `Bubble`, `hit`, `grab`, `dragTo`, `release`, `wakeAll`, and `step` behavior.
- Consumed by Task 4: a Theme V2 field that omits `dock`.

- [ ] **Step 1: Write deterministic gravity, bounds, and collision tests**

Create `mobile/test/today/bubble_physics_test.dart`:

```dart
import 'dart:ui';

import 'package:eureka/today/bubble_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('field without a dock applies gravity and keeps bubbles in bounds', () {
    BubbleField? field;
    Object? constructorError;
    try {
      field = Function.apply(BubbleField.new, const [], {
        #box: const Size(200, 300),
        #gravity: const Offset(0, 20),
      }) as BubbleField;
    } catch (error) {
      constructorError = error;
    }
    expect(
      constructorError,
      isNull,
      reason: 'BubbleField must support a panel with no Dock collider',
    );
    final fieldWithoutDock = field!;
    fieldWithoutDock.addBubble('asset-1', const Offset(100, 30), 20);
    final bubble = fieldWithoutDock.bubbles.single;
    final initialY = bubble.y;

    for (var step = 0; step < 60; step++) {
      fieldWithoutDock.step();
    }
    expect(bubble.y, greaterThan(initialY));

    for (var step = 0; step < 600; step++) {
      fieldWithoutDock.step();
    }
    expect(bubble.x, inInclusiveRange(20, 180));
    expect(bubble.y, inInclusiveRange(20, 280.5));
  });

  test('overlapping dynamic circles separate without tunneling', () {
    final field = BubbleField(
      box: const Size(240, 180),
      dock: const Rect.fromLTWH(0, 180, 0, 0),
      gravity: Offset.zero,
    );
    field
      ..addBubble('left', const Offset(100, 90), 20)
      ..addBubble('right', const Offset(130, 90), 20);

    for (var step = 0; step < 120; step++) {
      field.step();
    }

    final left = field.bubbles[0];
    final right = field.bubbles[1];
    final distance = Offset(left.x - right.x, left.y - right.y).distance;
    expect(distance, greaterThanOrEqualTo(39.5));
  });
}
```

- [ ] **Step 2: Run the physics tests and verify RED**

Run:

```bash
cd mobile
flutter test test/today/bubble_physics_test.dart
```

Expected: the first test compiles and fails its explicit `constructorError isNull`
assertion because the existing constructor rejects a call without `dock`. Do not
accept a compile error or an uncaught invocation error as RED.

- [ ] **Step 3: Make only the Dock obstacle optional**

Change the constructor and bounds method in `bubble_physics.dart`:

```dart
BubbleField({
  required this.box,
  Rect? dock,
  Offset gravity = const Offset(0, _gMag),
}) : _world = World(Vector2(gravity.dx, gravity.dy)) {
  _buildBounds(dock);
}

void _buildBounds(Rect? dock) {
  final w = box.width / _scale;
  final h = box.height / _scale;
  final walls = _world.createBody(BodyDef()..type = BodyType.static);
  void edge(Vector2 a, Vector2 b) => walls.createFixture(
    FixtureDef(EdgeShape()..set(a, b), friction: 0.4, restitution: 0.1),
  );
  edge(Vector2(0, h), Vector2(w, h));
  edge(Vector2(0, 0), Vector2(0, h));
  edge(Vector2(w, 0), Vector2(w, h));
  edge(Vector2(0, 0), Vector2(w, 0));
  if (dock == null) return;

  final halfW = dock.width / 2 / _scale;
  final halfH = (box.height - dock.top) / 2 / _scale;
  final center = Vector2(dock.center.dx / _scale, dock.top / _scale + halfH);
  final dockBody = _world.createBody(
    BodyDef()
      ..type = BodyType.static
      ..position = center,
  );
  dockBody.createFixture(
    FixtureDef(
      PolygonShape()..setAsBox(halfW, halfH, Vector2.zero(), 0),
      friction: 0.4,
      restitution: 0.2,
    ),
  );
}
```

Do not change scale, damping, restitution, fixture density, hit slop, or drag velocity.

- [ ] **Step 4: Run shared physics and legacy Today tests and verify GREEN**

Run:

```bash
cd mobile
flutter test test/today/bubble_physics_test.dart
flutter test test/theme_v2/asset_detail/asset_detail_entry_points_test.dart
```

Expected: both files finish with `All tests passed!`; the legacy `BubblePool` still compiles with its existing `dock:` argument.

- [ ] **Step 5: Commit Task 3**

```bash
git add mobile/lib/today/bubble_physics.dart mobile/test/today/bubble_physics_test.dart
git commit -m "refactor: share bubble physics with theme v2"
```

---

### Task 4: Replace the static Theme V2 bubble chamber with the physics adapter

**Files:**
- Create: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Create: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/lib/theme_v2/home/home_today_panel.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**
- Consumes: Task 3’s `BubbleField` without a `dock` argument.
- Produces: `ThemeV2AssetBubbleField({required List<PoolAsset> assets, required int trueCount, bool active = true, Stream<Offset>? gravityStream, ValueChanged<PoolAsset>? onOpenAsset})`.
- Produces: `Offset themeV2GravityForAcceleration(double x, double y)` for deterministic sensor mapping tests.
- Produces: `ThemeV2HomePage(active: bool = true)` and `HomeTodayPanel(active: bool = true)`.

- [ ] **Step 1: Write the first Theme V2 movement regression test**

Do not import or create the not-yet-existing adapter yet. In the existing
`theme_v2_home_page_test.dart`, make `_HomeHost` accept a
`disableAnimations` argument (defaulting to `true`) and pass it into its
`MediaQueryData`. Add an assertion against the existing bubble semantics so
the current static implementation reaches RED without a compilation failure:

```dart
testWidgets('Today asset bubbles fall under gravity when motion is enabled', (
  tester,
) async {
  await tester.pumpWidget(const _HomeHost(disableAnimations: false));
  await tester.pump();
  final bubble = find.bySemanticsLabel('打开资产 访谈摘录');
  final before = tester.getCenter(bubble);

  await tester.pump(const Duration(milliseconds: 500));

  expect(tester.getCenter(bubble).dy, greaterThan(before.dy));
});
```

After Step 2 has produced that assertion failure, create
`mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart` at the start
of Step 3. Add each focused test below before its corresponding adapter
behavior, run it to RED for an assertion-level behavior failure, and then make
it GREEN. The fixture and host control Reduce Motion:

```dart
import 'dart:async';

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/theme_v2_asset_bubble_field.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final asset = PoolAsset(
    id: 'asset-1',
    type: 'contact',
    domain: 'work',
    title: 'Kevin',
    payload: const {'name': 'Kevin'},
    createdAt: DateTime(2026, 8, 3, 10),
  );

  test('acceleration maps to fixed-magnitude screen gravity', () {
    expect(themeV2GravityForAcceleration(0, 0), const Offset(0, 20));
    expect(themeV2GravityForAcceleration(-9.8, 0).dx, closeTo(20, 0.01));
  });

  testWidgets('active physics moves a bubble under gravity', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getCenter(bubble).dy, greaterThan(before.dy));
  });

  testWidgets('Reduce Motion keeps a stable settled bubble', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: true,
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(seconds: 1));

    expect(tester.getCenter(bubble), before);
  });

  testWidgets('inactive Home pauses bubble motion', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      active: false,
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(seconds: 1));

    expect(tester.getCenter(bubble), before);
  });

  testWidgets('sensor failure falls back to default downward gravity', (
    tester,
  ) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: Stream<Offset>.error(StateError('sensor unavailable')),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(tester.getCenter(bubble).dy, greaterThan(before.dy));
  });

  testWidgets('bubble keeps semantics and opens the exact asset', (tester) async {
    PoolAsset? opened;
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: true,
      onOpenAsset: (value) => opened = value,
    );

    final target = find.bySemanticsLabel('打开资产 Kevin');
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    await tester.tap(target);

    expect(opened?.id, 'asset-1');
  });
}

Future<void> _pumpField(
  WidgetTester tester, {
  required List<PoolAsset> assets,
  required bool disableAnimations,
  bool active = true,
  Stream<Offset>? gravityStream,
  ValueChanged<PoolAsset>? onOpenAsset,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(395, 790);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: SizedBox(
          width: 395,
          height: 790,
          child: ThemeV2AssetBubbleField(
            assets: assets,
            trueCount: assets.length,
            active: active,
            gravityStream: gravityStream,
            onOpenAsset: onOpenAsset,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
```

In `theme_v2_home_page_test.dart`, add this integration assertion to the existing Pen composition test:

```dart
expect(find.byType(ThemeV2AssetBubbleField), findsOneWidget);
expect(
  find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1')),
  findsOneWidget,
);
```

- [ ] **Step 2: Run the existing Home test and verify assertion-level RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_page_test.dart --plain-name 'Today asset bubbles fall under gravity when motion is enabled'
```

Expected: FAIL with the final `dy` not greater than the initial `dy`, proving
the current bubble chamber is static. Fix any finder, fixture, or compilation
error until this precise behavioral assertion fails.

- [ ] **Step 3: Create the focused Theme V2 physics adapter**

Create `theme_v2_asset_bubble_field.dart` with these public declarations and state responsibilities:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../today/bubble_physics.dart';
import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';

Offset themeV2GravityForAcceleration(double x, double y) {
  const magnitude = 20.0;
  final length = math.sqrt(x * x + y * y);
  if (length < 1.2) return const Offset(0, magnitude);
  return Offset(-x / length, y / length) * magnitude;
}

class ThemeV2AssetBubbleField extends StatefulWidget {
  const ThemeV2AssetBubbleField({
    super.key,
    required this.assets,
    required this.trueCount,
    this.active = true,
    this.gravityStream,
    this.onOpenAsset,
  });

  final List<PoolAsset> assets;
  final int trueCount;
  final bool active;
  final Stream<Offset>? gravityStream;
  final ValueChanged<PoolAsset>? onOpenAsset;

  @override
  State<ThemeV2AssetBubbleField> createState() =>
      _ThemeV2AssetBubbleFieldState();
}
```

Implement `_ThemeV2AssetBubbleFieldState` with:

```dart
class _ThemeV2AssetBubbleFieldState extends State<ThemeV2AssetBubbleField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final Map<String, PoolAsset> _assetsById = {};
  final Map<String, double> _diametersById = {};
  BubbleField? _field;
  StreamSubscription<Offset>? _gravitySubscription;
  Size _box = Size.zero;
  bool _reduceMotion = false;
  Offset _gravity = const Offset(0, 20);

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _physicsActive =>
      widget.active && !_reduceMotion && _foreground && widget.assets.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion = MediaQuery.disableAnimationsOf(context);
    if (nextReduceMotion != _reduceMotion) {
      _reduceMotion = nextReduceMotion;
      _rebuildField(_box);
    }
    _syncLifecycle();
  }

  @override
  void didUpdateWidget(covariant ThemeV2AssetBubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_assetKey(oldWidget.assets) != _assetKey(widget.assets)) {
      _syncAssets();
    }
    if (oldWidget.gravityStream != widget.gravityStream) {
      unawaited(_gravitySubscription?.cancel());
      _gravitySubscription = null;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.gravityStream != widget.gravityStream) {
      _syncLifecycle();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncLifecycle();
  }

  String _assetKey(List<PoolAsset> assets) =>
      assets.map((asset) => asset.id).join('|');

  double _diameter(PoolAsset asset, int index) {
    const diameters = [
      70.0,
      48.0,
      72.0,
      58.0,
      80.0,
      52.0,
      64.0,
      52.0,
      44.0,
      50.0,
      38.0,
      46.0,
      38.0,
      38.0,
      54.0,
      42.0,
      56.0,
      46.0,
      34.0,
      30.0,
      34.0,
      32.0,
    ];
    return _diametersById.putIfAbsent(
      asset.id,
      () => diameters[index % diameters.length],
    );
  }

  Offset _spawnCenter(int index, double radius) {
    final usableWidth = math.max(1.0, _box.width - radius * 2);
    final fraction = ((index % 7) + 1) / 8;
    return Offset(radius + usableWidth * fraction, radius + 2 + index ~/ 7 * 4);
  }

  Offset _settledCenter(int index, double radius) {
    const slots = [
      Offset(39, 700),
      Offset(87, 711),
      Offset(141, 686),
      Offset(194, 709),
      Offset(255, 684),
      Offset(314, 710),
      Offset(362, 685),
      Offset(41, 641),
      Offset(79, 650),
      Offset(160, 627),
      Offset(199, 639),
      Offset(323, 631),
      Offset(369, 639),
      Offset(49, 589),
      Offset(105, 605),
      Offset(171, 579),
      Offset(272, 604),
      Offset(341, 581),
      Offset(215, 565),
      Offset(27, 550),
      Offset(373, 553),
      Offset(130, 548),
    ];
    final source = slots[index % slots.length];
    return Offset(
      source.dx.clamp(radius, math.max(radius, _box.width - radius)),
      (source.dy - (790 - _box.height)).clamp(
        radius,
        math.max(radius, _box.height - radius),
      ),
    );
  }

  void _rebuildField(Size box) {
    _box = box;
    _assetsById
      ..clear()
      ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
    if (box == Size.zero || widget.assets.isEmpty) {
      _field = null;
      _syncLifecycle();
      return;
    }
    final field = BubbleField(box: box, gravity: _gravity);
    for (var index = 0; index < widget.assets.length; index++) {
      final asset = widget.assets[index];
      final radius = _diameter(asset, index) / 2;
      field.addBubble(
        asset.id,
        _reduceMotion
            ? _settledCenter(index, radius)
            : _spawnCenter(index, radius),
        radius,
      );
    }
    _field = field;
    _repaint.value++;
    _syncLifecycle();
  }

  void _syncAssets() {
    final field = _field;
    if (field == null || _box == Size.zero) {
      _rebuildField(_box);
      return;
    }
    _assetsById
      ..clear()
      ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
    final ids = widget.assets.map((asset) => asset.id).toSet();
    for (final bubble in List<Bubble>.of(field.bubbles)) {
      if (!ids.contains(bubble.id)) {
        field.removeBubble(bubble);
        _diametersById.remove(bubble.id);
      }
    }
    for (var index = 0; index < widget.assets.length; index++) {
      final asset = widget.assets[index];
      if (field.has(asset.id)) continue;
      final radius = _diameter(asset, index) / 2;
      field.addBubble(
        asset.id,
        _reduceMotion
            ? _settledCenter(index, radius)
            : _spawnCenter(index, radius),
        radius,
      );
    }
    _repaint.value++;
    _syncLifecycle();
  }

  void _onTick(Duration elapsed) {
    final field = _field;
    if (!_physicsActive || field == null) return;
    if (!field.anyAwake) {
      _ticker.stop();
      return;
    }
    field.step();
    _repaint.value++;
  }

  Stream<Offset> _productionGravityStream() {
    return accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 66),
    ).map((event) => themeV2GravityForAcceleration(event.x, event.y));
  }

  void _syncLifecycle() {
    if (!_physicsActive) {
      if (_ticker.isActive) _ticker.stop();
      unawaited(_gravitySubscription?.cancel());
      _gravitySubscription = null;
      return;
    }
    _gravitySubscription ??=
        (widget.gravityStream ?? _productionGravityStream()).listen(
          (gravity) {
            if ((gravity - _gravity).distance < 0.04) return;
            _gravity = gravity;
            final field = _field;
            if (field != null) {
              field.gravity = gravity;
              field.wakeAll();
              if (!_ticker.isActive) _ticker.start();
            }
          },
          onError: (_) {
            unawaited(_gravitySubscription?.cancel());
            _gravitySubscription = null;
          },
        );
    if ((_field?.anyAwake ?? false) && !_ticker.isActive) _ticker.start();
  }

  void _openAsset(PoolAsset asset) {
    final callback = widget.onOpenAsset;
    if (callback != null) {
      callback(asset);
      return;
    }
    unawaited(
      openAssetDetail(
        context,
        AssetEntityRef(kind: AssetEntityKind.asset, id: asset.id),
        coreRecordsOnly: true,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_gravitySubscription?.cancel());
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }
}
```

Complete `_ThemeV2AssetBubbleFieldState.build` with the exact layout, gestures, count labels, and per-bubble semantic hit targets:

```dart
@override
Widget build(BuildContext context) {
  final tokens = context.themeV2;
  return LayoutBuilder(
    builder: (context, constraints) {
      final box = constraints.biggest;
      if (box != _box) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && box != _box) setState(() => _rebuildField(box));
        });
      }
      final field = _field;
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 238,
            top: 450,
            child: IgnorePointer(
              child: Text(
                '${widget.trueCount}',
                style: TextStyle(
                  color: tokens.accent.withValues(alpha: 0.07),
                  fontFamily: 'Geist',
                  fontSize: 112,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -6,
                ),
              ),
            ),
          ),
          Positioned(
            left: 286,
            top: 548,
            child: IgnorePointer(
              child: Text(
                '今日生成',
                style: TextStyle(
                  color: tokens.accent.withValues(alpha: 0.28),
                  fontFamily: 'Geist Mono',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          if (field != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (details) {
                  final bubble = field.hit(details.localPosition);
                  if (bubble == null) {
                    field.release();
                    return;
                  }
                  field.grab(bubble);
                  _syncLifecycle();
                },
                onPanUpdate: (details) {
                  field.dragTo(details.localPosition);
                  _syncLifecycle();
                },
                onPanEnd: (_) => field.release(),
                onPanCancel: field.release,
                child: AnimatedBuilder(
                  animation: _repaint,
                  builder: (context, _) {
                    final indexById = <String, int>{
                      for (var index = 0;
                          index < widget.assets.length;
                          index++)
                        widget.assets[index].id: index,
                    };
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final bubble in field.bubbles)
                          if (_assetsById[bubble.id] case final asset?)
                            Builder(
                              builder: (context) {
                                final index = indexById[bubble.id] ?? 0;
                                final hitSize = math.max(44, bubble.r * 2);
                                return Positioned(
                                  key: ValueKey(
                                    'theme-v2-asset-bubble-${asset.id}',
                                  ),
                                  left: bubble.x - hitSize / 2,
                                  top: bubble.y - hitSize / 2,
                                  width: hitSize,
                                  height: hitSize,
                                  child: Semantics(
                                    label: '打开资产 ${asset.title}',
                                    button: true,
                                    onTap: () => _openAsset(asset),
                                    child: ExcludeSemantics(
                                      child: Center(
                                        child: SizedBox.square(
                                          dimension: bubble.r * 2,
                                          child: _ThemeV2BubbleVisual(
                                            asset: asset,
                                            index: index,
                                            onTap: () => _openAsset(asset),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      );
    },
  );
}
```

Add the complete Theme V2 visual implementation to the same file:

```dart
class _ThemeV2BubbleVisual extends StatelessWidget {
  const _ThemeV2BubbleVisual({
    required this.asset,
    required this.index,
    required this.onTap,
  });

  final PoolAsset asset;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final highlighted = index < 5;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? null : tokens.background.withValues(alpha: 0.78),
        gradient: highlighted ? _bubbleGradient(context, index) : null,
        shape: BoxShape.circle,
        border: Border.all(
          color: highlighted
              ? Colors.white.withValues(alpha: 0.4)
              : tokens.border,
        ),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x55697BFF),
                  offset: Offset(0, 5),
                  blurRadius: 14,
                  spreadRadius: -5,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: Icon(
                _assetIcon(asset.type),
                size: math.min(22, constraints.maxWidth * 0.31),
                color: highlighted ? Colors.white : tokens.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

LinearGradient _bubbleGradient(BuildContext context, int index) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (index) {
    0 => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          dark ? const Color(0xFF8A82FF) : const Color(0xFF25B6D6),
          const Color(0xFF58D6FF),
        ],
      ),
    1 => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8A82FF), Color(0xFFD06BFF)],
      ),
    2 => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF32D7A1), Color(0xFF58D6FF)],
      ),
    3 => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF9B68), Color(0xFFE36BFF)],
      ),
    _ => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6F7CFF), Color(0xFF58D6FF)],
      ),
  };
}

IconData _assetIcon(String type) {
  return switch (type.toLowerCase()) {
    'idea' => Icons.lightbulb_outline,
    'todo' => Icons.check_box_outlined,
    'event' || 'calendar' => Icons.calendar_today_outlined,
    'book' => Icons.menu_book_outlined,
    'expense' => Icons.restaurant_outlined,
    'contact' => Icons.person_outline,
    'audio' || 'voice' => Icons.mic_none_outlined,
    'image' || 'photo' => Icons.image_outlined,
    'location' => Icons.location_on_outlined,
    'note' => Icons.description_outlined,
    _ => Icons.auto_awesome_outlined,
  };
}
```

- [ ] **Step 4: Wire Home visibility and replace the static field**

Add `active` with a default to `ThemeV2HomePage`:

```dart
const ThemeV2HomePage({
  super.key,
  this.controller,
  this.repository,
  this.now,
  this.active = true,
});

final bool active;
```

Pass it through the Today branch:

```dart
HomePresentation.today => HomeTodayPanel(
  key: const ValueKey(HomePresentation.today),
  data: data,
  date: widget.now,
  active: widget.active,
  onOpenAgenda: _controller.openAgenda,
),
```

Add the matching `active` parameter to `HomeTodayPanel`:

```dart
const HomeTodayPanel({
  super.key,
  required this.data,
  required this.onOpenAgenda,
  this.date,
  this.active = true,
});

final bool active;
```

Replace `_AssetBubbleField` with:

```dart
ThemeV2AssetBubbleField(
  key: assetBubbleFieldKey,
  assets: data.pool,
  trueCount: data.poolTrueCount,
  active: active,
),
```

Delete the old `_AssetBubbleField`, `_AssetBubble`, `_bubbleGradient`, and `_assetIcon` declarations from `home_today_panel.dart`; import `theme_v2_asset_bubble_field.dart` instead.

In the shell production page list, preserve Task 2’s top nav and pass visibility:

```dart
ThemeV2PageScaffold(body: ThemeV2HomePage(active: _index == 0)),
```

- [ ] **Step 5: Run the field and Home tests and verify GREEN**

Run:

```bash
cd mobile
flutter test test/today/bubble_physics_test.dart
flutter test test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
flutter test test/theme_v2/home/theme_v2_home_page_test.dart
flutter test test/theme_v2/home/theme_v2_home_golden_test.dart
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: every file finishes with `All tests passed!`; golden files do not change under Reduce Motion.

- [ ] **Step 6: Commit Task 4**

```bash
git add mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/theme_v2_home_page.dart mobile/lib/theme_v2/home/home_today_panel.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart
git commit -m "feat: restore physics to theme v2 today bubbles"
```

---

### Task 5: Full regression, APK, and real-device acceptance

**Files:**
- Verify only; modify production files only if a new failing regression test demonstrates a defect.
- Update test counts in `spec/design/theme-v2-api-integration-audit-2026-08-03.md` only after observing the final counts.

**Interfaces:**
- Consumes: Tasks 1–4 complete and committed.
- Produces: formatted/analyzed code, a passing full test suite, an installed Theme V2 APK, and a pushed current branch.

- [ ] **Step 1: Format all changed Dart files**

Run:

```bash
dart format mobile/lib/theme_v2/session/session_composer.dart mobile/lib/theme_v2/session/theme_v2_session_page.dart mobile/lib/theme_v2/session/session_header.dart mobile/lib/theme_v2/session/session_transcript.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/today/bubble_physics.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/theme_v2_home_page.dart mobile/lib/theme_v2/home/home_today_panel.dart mobile/test/theme_v2/session/session_state_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/test/today/bubble_physics_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: command exits 0.

- [ ] **Step 2: Run targeted static analysis**

Run from `mobile/`:

```bash
flutter analyze lib/theme_v2/session/session_composer.dart lib/theme_v2/session/theme_v2_session_page.dart lib/theme_v2/session/session_header.dart lib/theme_v2/session/session_transcript.dart lib/theme_v2/shell/theme_v2_app_shell.dart lib/today/bubble_physics.dart lib/theme_v2/home/theme_v2_asset_bubble_field.dart lib/theme_v2/home/theme_v2_home_page.dart lib/theme_v2/home/home_today_panel.dart test/theme_v2/session/session_state_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/today/bubble_physics_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/theme_v2_home_page_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Run the complete Flutter suite**

Run from `mobile/`:

```bash
flutter test
```

Expected: final line is `All tests passed!`. Record the observed count and update the audit document if it differs from 543.

- [ ] **Step 4: Build and install the final Theme V2 APK**

Run from `mobile/`:

```bash
flutter build apk --debug --dart-define=THEME_V2=true --dart-define=API_BASE=http://127.0.0.1:8000
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK reverse tcp:8000 tcp:8100
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: APK build and streamed install succeed; one launcher event is injected.

- [ ] **Step 5: Perform the six manual acceptance checks**

On device RFCY71B21YK:

1. Open the 8月3日闪念 Session, type a question, send it, and confirm the keyboard closes before the response arrives.
2. Confirm the header and watermark show the user-turn count rather than twice that number.
3. Return to Today and confirm Logo, device status, theme toggle, notifications, and the bottom Dock are visible and tappable.
4. Observe bubbles falling and colliding; tilt the phone and confirm gravity direction changes.
5. Drag and throw a bubble; confirm it collides, settles, and does not cross the field boundary.
6. Tap a bubble and confirm the exact Core Record Asset opens without a legacy API 404.

Capture one screenshot of Today and one of the Session turn count. Inspect the running app’s error log with:

```bash
theme_v2_app_pid=$(/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell pidof com.eureka.mindapp)
test -n "$theme_v2_app_pid"
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK logcat -d --pid="$theme_v2_app_pid" '*:E'
```

Accept Android vendor graphics warnings but reject Dart, Flutter, HTTP 404, or uncaught API errors.

- [ ] **Step 6: Update the audit count, commit verification metadata, and push only the current branch**

After substituting the observed Flutter count in the audit document:

```bash
git add spec/design/theme-v2-api-integration-audit-2026-08-03.md
git commit -m "docs: record theme v2 interaction verification"
git status --short --branch
git push origin codex/theme-v2-ui-refactor
```

Expected: the branch is synchronized with `origin/codex/theme-v2-ui-refactor`; no merge or push to `main` occurs.
