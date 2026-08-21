# Global Reka Flash Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one Shell-owned Reka Flash companion that supports hold-to-record on every Dock root page and presents App and hardware capture status in one bottom-anchored terminal.

**Architecture:** `ThemeV2AppShell` owns the single `RekaVoiceCaptureCoordinator` and a new `RekaCompanionController`. The controller normalizes local voice and `CaptureActivityCoordinator` state into a provider-neutral model; pure widgets render the terminal beside the full Today Reka or a lightweight mini Reka above the Dock.

**Tech Stack:** Flutter/Dart, `ChangeNotifier`, existing streaming voice and capture coordinators, Theme V2 tokens, Flutter unit/widget tests, Android build and ADB.

## Global Constraints

- Today keeps its draggable full Reka; Calendar and Library roots show one centered mini Reka above the Dock.
- Long press records, release sends immediately, and upward movement of the existing 72-pixel threshold cancels.
- Live transcript is 17 px medium weight, limited to four visible lines, and follows the newest content.
- Non-immersive Dock pages reserve exactly 136 pixels plus device safe-area padding.
- Done remains two seconds, empty three seconds, and failed four seconds.
- No-Dock pages render no companion; Bottom Sheets cover it while processing continues.
- Closing during recording cancels; closing after submission hides presentation only.
- Hardware never shows transcript text not supplied by its protocol.
- Capture status never replaces the standard top navigation.
- Do not add another WebView, retry/editing, ASR changes, or ordinary-field/Session behavior changes.

---

## File Structure

**Create:**
- `mobile/lib/theme_v2/capture/reka_terminal_models.dart`
- `mobile/lib/theme_v2/capture/reka_companion_controller.dart`
- `mobile/lib/theme_v2/capture/reka_terminal.dart`
- `mobile/lib/theme_v2/shell/reka_mini.dart`
- `mobile/lib/theme_v2/shell/reka_shell_companion.dart`
- `mobile/test/theme_v2/capture/reka_companion_controller_test.dart`
- `mobile/test/theme_v2/capture/reka_terminal_test.dart`
- `mobile/test/theme_v2/shell/reka_shell_companion_test.dart`

**Modify:**
- `mobile/lib/capture_activity/capture_activity_event.dart`
- `mobile/lib/theme_v2/capture/capture_activity_coordinator.dart`
- `mobile/lib/theme_v2/capture/thinking_orb.dart`
- `mobile/lib/voice_input/reka_voice_capture.dart`
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- `mobile/test/capture_activity/capture_activity_event_test.dart`
- `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart`
- `mobile/test/theme_v2/capture/thinking_orb_test.dart`
- `mobile/test/voice_input/reka_voice_capture_test.dart`
- `mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart`
- `mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart`
- `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

---

### Task 1: Extend capture primitives

**Files:**
- Modify: `mobile/lib/capture_activity/capture_activity_event.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_activity_coordinator.dart`
- Modify: `mobile/lib/voice_input/reka_voice_capture.dart`
- Test: `mobile/test/capture_activity/capture_activity_event_test.dart`
- Test: `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart`
- Test: `mobile/test/voice_input/reka_voice_capture_test.dart`

**Interfaces:**
- Produces: `CaptureActivitySource.app`, `RekaVoiceCaptureState.empty`, `captureEpoch`, and `voiceSessionId`.

- [ ] **Step 1: Write failing tests**

```dart
expect(
  CaptureActivityEvent.fromServerPayload({
    'status': 'understanding',
    'source': 'voice',
    'client_task_id': 'voice-42',
  })!.source,
  CaptureActivitySource.app,
);
expect(durations, containsAll(<Duration>[
  const Duration(seconds: 2),
  const Duration(seconds: 3),
  const Duration(seconds: 4),
]));
final before = coordinator.captureEpoch;
expect(await coordinator.begin(), isTrue);
expect(coordinator.captureEpoch, before + 1);
session.emit(_final(1, '   '));
await pumpEventQueue();
expect(coordinator.state, RekaVoiceCaptureState.empty);
expect(coordinator.voiceSessionId, 'voice-empty');
```

- [ ] **Step 2: Verify RED**

```bash
cd mobile
flutter test test/capture_activity/capture_activity_event_test.dart test/theme_v2/capture/capture_activity_coordinator_test.dart test/voice_input/reka_voice_capture_test.dart
```

Expected: missing App/empty/identity contracts and old 1.5/2/3 dwell fail.

- [ ] **Step 3: Implement contracts**

```dart
enum CaptureActivitySource { app, ring, card, audioUpload }

final source = switch (rawSource) {
  'voice' || 'app' => CaptureActivitySource.app,
  'ring' => CaptureActivitySource.ring,
  'card' => CaptureActivitySource.card,
  _ => CaptureActivitySource.audioUpload,
};
```

```dart
enum RekaVoiceCaptureState {
  idle, connecting, listening, cancelArmed, stopping, sending, empty, error,
}
int get captureEpoch => _epoch;
String? get voiceSessionId =>
    _voiceSessionId.trim().isEmpty ? null : _voiceSessionId.trim();
bool get isActive => switch (_state) {
  RekaVoiceCaptureState.idle ||
  RekaVoiceCaptureState.empty ||
  RekaVoiceCaptureState.error => false,
  _ => true,
};
_state = text.isEmpty
    ? RekaVoiceCaptureState.empty
    : RekaVoiceCaptureState.sending;
```

```dart
Duration _terminalDwell(CaptureActivityPhase phase) => switch (phase) {
  CaptureActivityPhase.done => const Duration(seconds: 2),
  CaptureActivityPhase.empty => const Duration(seconds: 3),
  CaptureActivityPhase.failed => const Duration(seconds: 4),
  _ => Duration.zero,
};
```

Add App copy `REKA App` and update every exhaustive switch.

- [ ] **Step 4: Verify GREEN**

Run Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/capture_activity/capture_activity_event.dart mobile/lib/theme_v2/capture/capture_activity_coordinator.dart mobile/lib/voice_input/reka_voice_capture.dart mobile/test/capture_activity/capture_activity_event_test.dart mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart mobile/test/voice_input/reka_voice_capture_test.dart
git commit -m "refactor(mobile): expose reka capture presentation state"
```

---

### Task 2: Build the normalized model and controller

**Files:**
- Create: `mobile/lib/theme_v2/capture/reka_terminal_models.dart`
- Create: `mobile/lib/theme_v2/capture/reka_companion_controller.dart`
- Create: `mobile/test/theme_v2/capture/reka_companion_controller_test.dart`

**Interfaces:**
- Consumes: local voice coordinator and capture activity coordinator.
- Produces: `RekaTerminalModel`, `RekaTerminalPhase`, `terminal`, `dismissTerminal()`, and `openableActivity`.

- [ ] **Step 1: Write failing merge/lifecycle tests**

```dart
final callbacks = <Duration, VoidCallback>{};
final companion = RekaCompanionController(
  voice: voice,
  activities: activities,
  schedule: (duration, callback) => callbacks[duration] = callback,
);
await voice.begin();
session.emit(_partial(1, '这是最新内容'));
await pumpEventQueue();
expect(companion.terminal!.phase, RekaTerminalPhase.listening);
expect(companion.terminal!.transcript, '这是最新内容');

activities.apply(appEvent(
  aliases: {'client:' + session.voiceSessionId},
  phase: CaptureActivityPhase.understanding,
));
session.emit(_final(2, '这是最新内容'));
await voice.release();
await pumpEventQueue();
expect(companion.terminal!.phase, RekaTerminalPhase.understanding);

await companion.dismissTerminal();
activities.apply(appEvent(
  aliases: {'client:' + session.voiceSessionId},
  phase: CaptureActivityPhase.done,
));
expect(companion.terminal, isNull);
```

Also cover held-App priority, realtime priority, oldest fallback, queue count, hardware transcript empty, local empty/failure dwell, and new-task reappearance.

- [ ] **Step 2: Verify RED**

```bash
cd mobile
flutter test test/theme_v2/capture/reka_companion_controller_test.dart
```

Expected: missing model/controller.

- [ ] **Step 3: Define the model**

```dart
enum RekaTerminalPhase {
  connecting, listening, cancelArmed, transcribing, sending,
  receiving, understanding, organizing, done, empty, failed,
}

@immutable
class RekaTerminalModel {
  const RekaTerminalModel({
    required this.identity,
    required this.aliases,
    required this.source,
    required this.phase,
    required this.statusLabel,
    this.transcript = '',
    this.resultCount,
    this.queuedCount = 0,
    this.canOpenDetail = false,
  });
  final String identity;
  final Set<String> aliases;
  final CaptureActivitySource source;
  final RekaTerminalPhase phase;
  final String statusLabel;
  final String transcript;
  final int? resultCount;
  final int queuedCount;
  final bool canOpenDetail;
}
```

Add exhaustive source commands (`REKA://APP`, `REKA://RING`, `REKA://CARD`, `REKA://UPLOAD`), status copy, Orb state, and header tint.

- [ ] **Step 4: Implement controller rules**

```dart
typedef RekaCompanionSchedule =
    void Function(Duration duration, VoidCallback callback);

class RekaCompanionController extends ChangeNotifier {
  RekaCompanionController({
    required RekaVoiceCaptureCoordinator voice,
    required CaptureActivityCoordinator activities,
    RekaCompanionSchedule? schedule,
  });
  RekaTerminalModel? get terminal => _terminal;
  CaptureActivityItem? get openableActivity => _openableActivity;
  Future<void> dismissTerminal();
}
```

Local aliases are `app-local:<epoch>` and, when known, `client:<voiceSessionId>`. Local non-idle state has first priority, then the coordinator realtime activity, then oldest pending. Dismiss stores every alias; connecting/listening/cancel-armed/stopping awaits `cancelGesture()`, while sending only hides. Empty schedules three seconds and failure four seconds using epoch and timer-generation guards. Clear dismissed aliases only after no current local/server activity intersects them.

- [ ] **Step 5: Verify GREEN and commit**

```bash
flutter test test/theme_v2/capture/reka_companion_controller_test.dart
git add mobile/lib/theme_v2/capture/reka_terminal_models.dart mobile/lib/theme_v2/capture/reka_companion_controller.dart mobile/test/theme_v2/capture/reka_companion_controller_test.dart
git commit -m "feat(mobile): model global reka capture status"
```

---

### Task 3: Build the terminal and reduced-motion Orb

**Files:**
- Create: `mobile/lib/theme_v2/capture/reka_terminal.dart`
- Modify: `mobile/lib/theme_v2/capture/thinking_orb.dart`
- Create: `mobile/test/theme_v2/capture/reka_terminal_test.dart`
- Modify: `mobile/test/theme_v2/capture/thinking_orb_test.dart`

**Interfaces:**
- Consumes: immutable terminal model.
- Produces: fixed-height tail-follow terminal with accessible close/result actions.

- [ ] **Step 1: Write failing widget tests**

```dart
await tester.pumpWidget(host(RekaTerminal(
  model: listeningModel(
    transcript: List.filled(8, '最新语音').join('\\n'),
  ),
  onClose: () {},
)));
await tester.pump();
final scrollable = tester.state<ScrollableState>(
  find.descendant(
    of: find.byKey(RekaTerminal.transcriptViewportKey),
    matching: find.byType(Scrollable),
  ),
);
expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
expect(
  tester.getSize(find.byKey(RekaTerminal.closeKey)).shortestSide,
  greaterThanOrEqualTo(48),
);
expect(find.text('虚构硬件转录'), findsNothing);
```

Also test queue count, result tap, phase-only live region, large text, and no recurring Orb ticker with reduced motion.

- [ ] **Step 2: Verify RED**

```bash
cd mobile
flutter test test/theme_v2/capture/reka_terminal_test.dart test/theme_v2/capture/thinking_orb_test.dart
```

- [ ] **Step 3: Stop Orb animation under reduced motion**

```dart
void _syncMotionPreference() {
  final disabled = MediaQuery.disableAnimationsOf(context);
  if (_reduceMotion == disabled) return;
  _reduceMotion = disabled;
  if (disabled) {
    _motion.stop();
    _morph.value = 1;
  } else {
    _motion.repeat();
  }
}
```

Call from `didChangeDependencies`; jump profiles immediately in `didUpdateWidget` when disabled.

- [ ] **Step 4: Implement terminal and tail-follow**

Build a dark rounded body and state-tinted header with 32-pixel Orb, phase, source command, queue count, and 48-pixel close. Only the phase is a live region; exclude partial transcript semantics.

```dart
void _followTranscriptTail() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  });
}
@override
void didUpdateWidget(covariant RekaTerminal oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.model.transcript != widget.model.transcript) {
    _followTranscriptTail();
  }
}
```

Transcript style is 17 px, weight 500, height 1.35, maximum height `17 * 1.35 * 4`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
flutter test test/theme_v2/capture/reka_terminal_test.dart test/theme_v2/capture/thinking_orb_test.dart
git add mobile/lib/theme_v2/capture/reka_terminal.dart mobile/lib/theme_v2/capture/thinking_orb.dart mobile/test/theme_v2/capture/reka_terminal_test.dart mobile/test/theme_v2/capture/thinking_orb_test.dart
git commit -m "feat(mobile): render reka flash terminal"
```

---

### Task 4: Build mini Reka and route-aware overlay

**Files:**
- Create: `mobile/lib/theme_v2/shell/reka_mini.dart`
- Create: `mobile/lib/theme_v2/shell/reka_shell_companion.dart`
- Create: `mobile/test/theme_v2/shell/reka_shell_companion_test.dart`

**Interfaces:**
- Consumes: companion controller, Today motion controller, gesture/detail/quick-action callbacks.
- Produces: Today/mini modes and safe terminal placement.

- [ ] **Step 1: Write failing placement/gesture tests**

```dart
expect(
  tester.getCenter(find.byKey(RekaMini.targetKey)).dx,
  closeTo(tester.getCenter(find.byKey(ThemeV2FloatingDock.dockKey)).dx, .01),
);
final gesture = await tester.startGesture(
  tester.getCenter(find.byKey(RekaMini.targetKey)),
);
await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
await gesture.moveBy(const Offset(0, -80));
await gesture.up();
expect(offsets.last, closeTo(-80, .01));
expect(releases, 1);
```

Also test tap anchor, Today following, safe clamping, null terminal, and reduced motion.

- [ ] **Step 2: Verify RED**

```bash
cd mobile
flutter test test/theme_v2/shell/reka_shell_companion_test.dart
```

- [ ] **Step 3: Implement Flutter-painted mini Reka**

```dart
class RekaMini extends StatelessWidget {
  static const targetKey = ValueKey<String>('reka-mini-target');
  static const visualSize = Size(64, 44);
  static const double targetExtent = 72;
  const RekaMini({
    super.key,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });
}
```

Use one `CustomPainter` for shell, visor, two cyan eyes, and restrained dither. Instantiate no WebView-related widget. Report vertical offset as current global Y minus the long-press origin Y.

Wrap the target in `Semantics(button: true, label: 'Reka 快捷操作，长按说话，上滑取消，松开发送')` and keep the full 72-by-72 target exposed to accessibility.

- [ ] **Step 4: Implement route-aware companion**

```dart
enum RekaShellCompanionMode { today, mini }

class RekaShellCompanion extends StatelessWidget {
  const RekaShellCompanion({
    super.key,
    required this.mode,
    required this.controller,
    required this.todayRekaController,
    required this.onTapReka,
    required this.onOpenDetail,
  });
}
```

Mini mode centers above the Dock. Today mode renders no mini and anchors above `rekaCenter`. Clamp terminal with 16-pixel side bounds. Use scale/opacity, or zero duration under reduced motion.

- [ ] **Step 5: Verify GREEN and commit**

```bash
flutter test test/theme_v2/shell/reka_shell_companion_test.dart
git add mobile/lib/theme_v2/shell/reka_mini.dart mobile/lib/theme_v2/shell/reka_shell_companion.dart mobile/test/theme_v2/shell/reka_shell_companion_test.dart
git commit -m "feat(mobile): add docked reka companion"
```

---

### Task 5: Integrate Shell ownership and route chrome

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4, `VoiceInputScope`, `sendVoiceFlash`, quick actions, detail navigation.
- Produces: one voice owner, stable nav, exact clearance, and tab-continuous capture.

- [ ] **Step 1: Write failing integration tests**

```dart
expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
expect(find.byType(CaptureActivityTopBar), findsNothing);
expect(find.byType(RekaTerminal), findsOneWidget);
await tester.tap(find.text('calendar'));
await tester.pumpAndSettle();
expect(find.byKey(RekaMini.targetKey), findsOneWidget);
expect(identical(todayVoice, shellVoice), isTrue);
```

Also test 136-pixel clearance, no-Dock absence, recording across root tab changes, and Bottom Sheet occlusion.

- [ ] **Step 2: Verify RED**

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_app_shell_capture_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart
```

- [ ] **Step 3: Add shared geometry and companion slot**

```dart
static const double contentClearance = 80;
static const double companionContentClearance = 136;
static const double miniRekaGap = 6;
```

Add `Widget? companion` to PageScaffold and `withShellChrome`:

```dart
final bottomClearance = showDock && !extendBodyBehindChrome
    ? ThemeV2FloatingDock.companionContentClearance +
        MediaQuery.paddingOf(context).bottom
    : 0.0;
if (showDock && dock != null)
  Positioned(left: 0, right: 0, bottom: 0, child: dock!),
if (showDock && companion != null)
  Positioned.fill(child: companion!),
```

- [ ] **Step 4: Move voice/controller ownership to Shell**

Create the production voice owner once in `didChangeDependencies`, then companion controller with the same activity coordinator. Own one Today motion controller. Publish an App activity immediately after a real Flash result:

```dart
final result = await sendVoiceFlash(
  api,
  text,
  voiceSessionId: voiceSessionId,
);
_captureActivityCoordinator.apply(CaptureActivityEvent(
  aliases: <String>{
    'client:' + voiceSessionId,
    if (result.recordingId.isNotEmpty) 'recording:' + result.recordingId,
  },
  source: CaptureActivitySource.app,
  phase: result.hasPending
      ? CaptureActivityPhase.understanding
      : CaptureActivityPhase.done,
  isRealtime: true,
  sessionId: result.sessionId,
  inputTurnId: result.inputTurnId,
  resultCount: result.hasPending ? null : result.cards.length,
  occurredAt: DateTime.now().toUtc(),
));
```

App pause/inactive/hidden/detached cancels only unsubmitted recording.

- [ ] **Step 5: Keep nav stable and inject companion**

Remove the capture header switch. Always pass standard nav. Use Today mode only for production Today index 0; other Dock roots use mini.

Route a normal mini-Reka tap through the existing quick-action sheet:

```dart
Future<void> _openRekaQuickActions(BuildContext context, Rect anchor) =>
    showTodayRekaQuickActions(
  context,
  anchor: anchor,
  onManualRecord: widget.onManualRecord,
  onCreateReport: widget.onCreateReport,
  onStartChat: widget.onStartChat,
);
```

```dart
activePage.withShellChrome(
  topNav: standardTopNav,
  dock: dock,
  companion: companion,
  body: indexedPages,
);
```

- [ ] **Step 6: Make Today consume Shell owners**

Inject Shell voice and motion controllers. Remove `_RekaVoiceOverlay` and tab-deactivation cancellation. Keep fallback ownership only for standalone tests/previews.

- [ ] **Step 7: Verify GREEN and commit**

```bash
flutter test test/theme_v2/shell/theme_v2_app_shell_capture_test.dart test/theme_v2/shell/theme_v2_page_scaffold_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/shell/reka_shell_companion_test.dart test/theme_v2/capture/reka_companion_controller_test.dart test/voice_input/reka_voice_capture_test.dart
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart mobile/lib/theme_v2/home/today_dot_experiment_page.dart mobile/test/theme_v2/shell/theme_v2_app_shell_capture_test.dart mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "feat(mobile): integrate global reka flash companion"
```

---

### Task 6: Full verification and physical device

**Files:** No planned source changes. A failing gate reopens the responsible Task 1–5 test cycle before Task 6 restarts.

- [ ] **Step 1: Run focused regression**

```bash
cd mobile
flutter test test/voice_input test/theme_v2/capture test/theme_v2/home/today_dot_experiment_page_test.dart test/theme_v2/home/today_reka_scene_test.dart test/theme_v2/shell test/theme_v2/session
```

Expected: PASS without Flutter errors, pending timers, semantics failures, or overflow.

- [ ] **Step 2: Analyze**

```bash
cd mobile
flutter analyze lib/capture_activity lib/voice_input lib/theme_v2/capture lib/theme_v2/home lib/theme_v2/shell test/voice_input test/theme_v2/capture test/theme_v2/home test/theme_v2/shell
```

Expected: `No issues found!`

- [ ] **Step 3: Build, install, and launch**

```bash
cd mobile
flutter build apk --debug
flutter devices
adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: newest APK installs and launches with backend port reversed.

- [ ] **Step 4: Verify physical interactions**

```text
Today full Reka: drag, hold, live transcript, release sends.
Today: slide upward beyond 72 px and release creates nothing.
Calendar/Library: mini Reka centered above Dock and no content overlap.
Navigate while recording: same transcript and microphone session continue.
More than four lines: newest transcript remains visible.
Close recording: cancel and immediate microphone reuse.
Close processing: hide only; same task does not reopen.
Hardware: source/phase only, no invented transcript.
No-Dock and Bottom Sheet: companion hidden/covered; processing survives.
Top navigation: device and notification controls always remain.
```

- [ ] **Step 5: Confirm final scoped state**

```bash
git diff --check
git status --short
cd mobile
flutter test test/voice_input test/theme_v2/capture test/theme_v2/shell test/theme_v2/session
flutter analyze lib/capture_activity lib/voice_input lib/theme_v2/capture lib/theme_v2/home lib/theme_v2/shell
```

Expected: diff check is clean, only the design/plan and Task 1–5 feature paths differ from the branch baseline, tests pass, analysis is clean, and no verification-only commit is created.

---

## Final Definition of Done

- One Shell-owned voice coordinator serves all Dock root pages.
- App live transcript hands off to backend status under one correlated identity.
- App and hardware share the terminal; hardware never fabricates transcript.
- Standard top navigation remains mounted.
- Mini Reka is Flutter-painted and shared clearance prevents overlap.
- Close, cancel, route, lifecycle, reduced motion, semantics, queue, dwell, and tail-follow have deterministic tests.
- Focused tests and analysis pass.
- A fresh APK builds, installs, launches, and is verified on the connected Android device.
