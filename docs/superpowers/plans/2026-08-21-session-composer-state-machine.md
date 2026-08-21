# Session Composer State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Session composer as a state-driven integrated card that hides send while idle or recording, follows the newest transcript beyond five lines, and blocks both send and recording while the Agent replies.

**Architecture:** Add a pure `SessionComposerPresentation` derivation so focus, draft, voice, and Agent-reply rules are testable without widget layout. Extend `VoiceInputField` with an optional body-composition seam that preserves every existing call site by default, then make `SessionComposer` stateful so it owns the internal text scroll controller and explicit voice-tail following.

**Tech Stack:** Flutter, Dart, `TextField`, `FocusNode`, `ScrollController`, existing `VoiceInputController`, Flutter widget tests, golden tests

## Global Constraints

- Do not add a dependency or change the ASR provider, protocol, ownership, or five-minute limit.
- Do not change Reka or any non-Session voice-input surface.
- The Session input grows from one through exactly five visible lines; later content scrolls internally.
- Empty and unfocused shows only the input region and one 48-by-48 microphone action; send is absent.
- Voice connecting, listening, and finalizing close the keyboard and omit send from both widget and semantics trees.
- A finalized voice transcript or manually dismissed typed draft remains sendable without reopening the keyboard.
- Agent reply blocks both send and voice at UI and method boundaries.
- The leading sparkle is decorative, excluded from pointer handling and semantics, and has no context-asset callback.
- Preserve cancellation snapshot restoration, Session draft clearing, warnings, errors, accessibility, and reduced-motion behavior.
- Use TDD: observe each focused test fail for the intended reason before production changes.

---

## File Structure

- Create `mobile/lib/theme_v2/session/session_composer_state.dart`: pure Session presentation-state derivation only.
- Create `mobile/test/theme_v2/session/session_composer_state_test.dart`: exhaustive state table for focus, draft, voice, and Agent lock.
- Modify `mobile/lib/voice_input/voice_input_field.dart`: optional Session composition seam while retaining the current default row.
- Modify `mobile/lib/voice_input/voice_input_status_icon.dart`: expose provider-neutral visible status copy from `VoiceInputPresentation`.
- Modify `mobile/test/voice_input/voice_input_field_test.dart`: prove the custom seam receives the canonical voice action and default layout is unchanged.
- Modify `mobile/lib/theme_v2/session/session_composer.dart`: integrated card, focus lifecycle, voice lifecycle, and tail-follow scroll ownership.
- Modify `mobile/test/theme_v2/session/session_keyboard_test.dart`: focus, keyboard, long-content, layout, Agent lock, and tail-follow widget regressions.
- Modify `mobile/test/theme_v2/session/theme_v2_session_golden_test.dart`: add deterministic `reviewReady` and `longReviewReady` fixtures for the expanded card and five-line bound.
- Modify `mobile/test/theme_v2/session/goldens/session-*.png`: accept only inspected Session composer changes.

---

### Task 1: Make the shared voice field layout composable

**Files:**
- Modify: `mobile/lib/voice_input/voice_input_field.dart`
- Modify: `mobile/lib/voice_input/voice_input_status_icon.dart`
- Test: `mobile/test/voice_input/voice_input_field_test.dart`

**Interfaces:**
- Consumes: existing `VoiceInputFieldBuilder`, `VoiceInputPresentation`, and canonical `VoiceInputField.micKey` action.
- Produces: `VoiceInputFieldLayoutBuilder` and optional `VoiceInputField.layoutBuilder`; `VoiceInputPresentation.statusLabel`.

- [ ] **Step 1: Write the failing custom-layout and status-copy tests**

Add tests that mount `VoiceInputField(layoutBuilder: ...)`, assert the supplied `field` and canonical microphone action render inside a keyed custom container, tap that action to start/stop the fake voice session, and verify `voice.statusLabel` returns `null`, `正在连接语音`, `正在聆听`, and `正在完成转录` for the four controller states.

```dart
testWidgets('custom layout receives the field and canonical voice action', (
  tester,
) async {
  final text = VoiceInputTextController();
  final session = _WidgetFakeSession();
  final controller = VoiceInputController(
    textController: text,
    coordinator: VoiceInputCoordinator(service: _WidgetFakeService(session)),
  );

  await tester.pumpWidget(MaterialApp(
    home: VoiceInputField(
      controller: controller,
      layoutBuilder: (context, voice, field, voiceAction) => Row(
        key: const Key('custom-voice-layout'),
        children: [Expanded(child: field), voiceAction],
      ),
      builder: (_, __) => const TextField(key: Key('custom-field')),
    ),
  ));

  expect(find.byKey(const Key('custom-voice-layout')), findsOneWidget);
  expect(find.byKey(const Key('custom-field')), findsOneWidget);
  expect(find.byKey(VoiceInputField.micKey), findsOneWidget);
  await tester.tap(find.byKey(VoiceInputField.micKey));
  await tester.pump();
  expect(controller.state, VoiceInputControllerState.listening);
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub test/voice_input/voice_input_field_test.dart --reporter compact
```

Expected: compile failure because `layoutBuilder` and `statusLabel` do not exist.

- [ ] **Step 3: Add the minimal default-preserving composition seam**

Add the public typedef and optional property:

```dart
typedef VoiceInputFieldLayoutBuilder = Widget Function(
  BuildContext context,
  VoiceInputPresentation voice,
  Widget field,
  Widget voiceAction,
);

final VoiceInputFieldLayoutBuilder? layoutBuilder;
```

Extract the existing `IconButton` unchanged into `voiceAction`. Build either the custom body or the existing row:

```dart
final field = builder(context, voice);
final body = layoutBuilder?.call(context, voice, field, voiceAction) ??
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
        const SizedBox(width: 6),
        voiceAction,
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
```

Warnings and errors remain below `body` in the existing outer column. Add the status getter without provider-specific types:

```dart
String? get statusLabel => switch (state) {
  VoiceInputControllerState.idle => null,
  VoiceInputControllerState.connecting => '正在连接语音',
  VoiceInputControllerState.listening => '正在聆听',
  VoiceInputControllerState.stopping => '正在完成转录',
};
```

Use `statusLabel` inside `VoiceInputStatusIcon` so visible and semantic copy cannot diverge.

- [ ] **Step 4: Run shared voice tests and confirm GREEN**

Run:

```bash
cd mobile
flutter test --no-pub test/voice_input/voice_input_field_test.dart test/voice_input/voice_input_adoption_test.dart --reporter compact
```

Expected: all tests pass; default call sites still render one canonical microphone/stop action and no cancel action.

- [ ] **Step 5: Commit the shared seam**

```bash
git add mobile/lib/voice_input/voice_input_field.dart mobile/lib/voice_input/voice_input_status_icon.dart mobile/test/voice_input/voice_input_field_test.dart
git commit -m "refactor(mobile): make voice field layout composable"
```

---

### Task 2: Add the pure Session composer state derivation

**Files:**
- Create: `mobile/lib/theme_v2/session/session_composer_state.dart`
- Create: `mobile/test/theme_v2/session/session_composer_state_test.dart`

**Interfaces:**
- Consumes: `VoiceInputControllerState`.
- Produces: `SessionComposerMode` and `SessionComposerPresentation.derive(...)` with `showFooter`, `showSend`, `showVoiceStatus`, `canSend`, and `canStartVoice`.

- [ ] **Step 1: Write the complete failing state table**

Cover empty/unfocused, focused empty, focused draft, active voice with provisional text, finalized/unfocused draft, whitespace-only text, and every state with `agentReplying: true`.

```dart
test('voice always wins and removes send', () {
  final state = SessionComposerPresentation.derive(
    hasFocus: true,
    text: '临时转录',
    voiceState: VoiceInputControllerState.listening,
    agentReplying: false,
  );
  expect(state.mode, SessionComposerMode.voiceActive);
  expect(state.showFooter, isTrue);
  expect(state.showVoiceStatus, isTrue);
  expect(state.showSend, isFalse);
  expect(state.canSend, isFalse);
});

test('agent reply locks both actions without changing draft layout', () {
  final state = SessionComposerPresentation.derive(
    hasFocus: false,
    text: '保留草稿',
    voiceState: VoiceInputControllerState.idle,
    agentReplying: true,
  );
  expect(state.mode, SessionComposerMode.reviewReady);
  expect(state.showSend, isTrue);
  expect(state.canSend, isFalse);
  expect(state.canStartVoice, isFalse);
});
```

- [ ] **Step 2: Run the model test and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub test/theme_v2/session/session_composer_state_test.dart --reporter compact
```

Expected: compile failure because `session_composer_state.dart` is absent.

- [ ] **Step 3: Implement the pure immutable derivation**

```dart
enum SessionComposerMode { collapsedIdle, editing, voiceActive, reviewReady }

@immutable
final class SessionComposerPresentation {
  const SessionComposerPresentation._({
    required this.mode,
    required this.hasDraft,
    required this.voiceState,
    required this.agentReplying,
  });

  factory SessionComposerPresentation.derive({
    required bool hasFocus,
    required String text,
    required VoiceInputControllerState voiceState,
    required bool agentReplying,
  }) {
    final hasDraft = text.trim().isNotEmpty;
    final mode = voiceState != VoiceInputControllerState.idle
        ? SessionComposerMode.voiceActive
        : hasFocus
        ? SessionComposerMode.editing
        : hasDraft
        ? SessionComposerMode.reviewReady
        : SessionComposerMode.collapsedIdle;
    return SessionComposerPresentation._(
      mode: mode,
      hasDraft: hasDraft,
      voiceState: voiceState,
      agentReplying: agentReplying,
    );
  }

  final SessionComposerMode mode;
  final bool hasDraft;
  final VoiceInputControllerState voiceState;
  final bool agentReplying;

  bool get showFooter => mode != SessionComposerMode.collapsedIdle;
  bool get showSend =>
      mode == SessionComposerMode.editing ||
      mode == SessionComposerMode.reviewReady;
  bool get showVoiceStatus => mode == SessionComposerMode.voiceActive;
  bool get canSend => showSend && hasDraft && !agentReplying;
  bool get canStartVoice =>
      voiceState == VoiceInputControllerState.idle && !agentReplying;
}
```

- [ ] **Step 4: Run the state table and confirm GREEN**

Run the command from Step 2.

Expected: all state-table tests pass.

- [ ] **Step 5: Commit the state model**

```bash
git add mobile/lib/theme_v2/session/session_composer_state.dart mobile/test/theme_v2/session/session_composer_state_test.dart
git commit -m "feat(mobile): define session composer states"
```

---

### Task 3: Rebuild Session as one integrated state-driven composer card

**Files:**
- Modify: `mobile/lib/theme_v2/session/session_composer.dart`
- Modify: `mobile/test/theme_v2/session/session_keyboard_test.dart`

**Interfaces:**
- Consumes: `SessionComposerPresentation.derive(...)`, `VoiceInputField.layoutBuilder`, `VoiceInputPresentation.statusLabel`, and the existing Session callbacks.
- Produces: keyed regions `session-composer-footer`, `session-composer-sparkle`, `session-voice-status-label`, and the existing `session-composer-field`, `session-send`, and canonical microphone keys.

- [ ] **Step 1: Write failing state/layout widget tests**

Add tests that verify:

```dart
expect(find.byKey(const ValueKey('session-composer-footer')), findsNothing);
expect(find.byKey(const ValueKey('session-send')), findsNothing);
expect(find.byKey(VoiceInputField.micKey), findsOneWidget);
```

Then focus the field and assert the footer/send appear; enter text, unfocus, and assert they remain. Verify the sparkle has no tap action. Set `FakeSessionController.streaming = true` and prove both the microphone `IconButton.onPressed` and send `IconButton.onPressed` are null while `_submit` remains guarded.

- [ ] **Step 2: Run Session keyboard tests and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub test/theme_v2/session/session_keyboard_test.dart --reporter compact
```

Expected: idle still contains send and the new footer/sparkle keys are absent.

- [ ] **Step 3: Convert `SessionComposer` to a stateful integrated layout**

Convert `SessionComposer` to `StatefulWidget`. Keep `maxVisibleLines = 5` and `actionSize = 48.0`. Derive presentation on every relevant listenable update:

```dart
final presentation = SessionComposerPresentation.derive(
  hasFocus: widget.focusNode.hasFocus,
  text: widget.controller.text,
  voiceState: widget.voiceController.state,
  agentReplying: widget.streaming,
);
```

Use `VoiceInputField.layoutBuilder` to choose:

```dart
if (presentation.mode == SessionComposerMode.collapsedIdle) {
  return Row(children: [Expanded(child: field), voiceAction]);
}
final sendAction = IconButton(
  key: const ValueKey('session-send'),
  onPressed: presentation.canSend
      ? () => unawaited(_submit(widget.controller.text))
      : null,
  icon: const Icon(Icons.arrow_upward_rounded),
);
final statusIcon = voice.statusIcon(color: tokens.accent);
final footer = presentation.showVoiceStatus
    ? Row(
        children: [
          if (statusIcon != null) statusIcon,
          if (voice.statusLabel != null)
            Text(
              voice.statusLabel!,
              key: const ValueKey('session-voice-status-label'),
            ),
          const Spacer(),
          voiceAction,
        ],
      )
    : Row(
        children: [
          const Spacer(),
          voiceAction,
          if (presentation.showSend) ...[
            const SizedBox(width: 8),
            sendAction,
          ],
        ],
      );
return DecoratedBox(
  decoration: BoxDecoration(
    color: tokens.surface,
    border: Border.all(color: tokens.border),
    borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      field,
      Container(
        key: const ValueKey('session-composer-footer'),
        height: SessionComposer.actionSize + 16,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: footer,
      ),
    ],
  ),
);
```

The idle text decoration has the card border. Expanded text decoration removes its independent outline so the field and footer read as one card. Replace the interactive prefix `IconButton` with:

```dart
const ExcludeSemantics(
  child: IgnorePointer(
    child: Icon(
      Icons.auto_awesome_outlined,
      key: ValueKey('session-composer-sparkle'),
    ),
  ),
)
```

Editing/review footers contain the canonical `voiceAction` and send. Voice footers contain `voice.statusIcon()`, visible `voice.statusLabel`, and the canonical stop action; they never build send. Agent reply passes `enabled: !widget.streaming` to `VoiceInputField` and keeps `_submit` guarded by `widget.streaming` and `voiceController.isBusy`.

- [ ] **Step 4: Make focus and keyboard transitions explicit**

Register/deregister focus, text, and voice listeners in `initState`, `didUpdateWidget`, and `dispose`. On the first non-idle voice state:

```dart
if (widget.voiceController.isBusy && widget.focusNode.hasFocus) {
  widget.focusNode.unfocus();
}
```

Keep send behavior immediate:

```dart
final trimmed = text.trim();
if (trimmed.isEmpty || widget.streaming || widget.voiceController.isBusy) {
  return;
}
widget.controller.clear();
widget.focusNode.unfocus();
await widget.onSend(trimmed);
```

- [ ] **Step 5: Run focused layout tests and confirm GREEN**

Run the command from Step 2.

Expected: all Session keyboard tests pass, including idle, editing, review-ready, Agent lock, keyboard inset, action size, and long-content bounds.

- [ ] **Step 6: Commit the integrated state layout**

```bash
git add mobile/lib/theme_v2/session/session_composer.dart mobile/test/theme_v2/session/session_keyboard_test.dart
git commit -m "feat(mobile): redesign session composer states"
```

---

### Task 4: Guarantee newest speech remains visible beyond five lines

**Files:**
- Modify: `mobile/lib/theme_v2/session/session_composer.dart`
- Modify: `mobile/test/theme_v2/session/session_keyboard_test.dart`

**Interfaces:**
- Consumes: Session-owned `ScrollController`, existing `VoiceInputTextController` selection/provisional updates, and `VoiceInputController.terminalCount`.
- Produces: deterministic `_scheduleVoiceTailFollow()` used for provisional, stable, and final voice text.

- [ ] **Step 1: Write a deterministic failing tail-follow regression**

Pump a `SessionComposer` with a fake voice session, start voice, emit enough newline-separated partial/stable text to exceed five lines, manually jump its internal scroll controller to zero, then emit the next partial. Assert after a frame:

```dart
expect(
  scrollable.position.pixels,
  closeTo(scrollable.position.maxScrollExtent, 1),
);
```

Emit a final transcript longer than five lines, allow the controller to return to idle, and make the same assertion. Also assert `session-send` is absent before finalization and present after finalization while the keyboard remains closed.

- [ ] **Step 2: Run the tail-follow test and confirm RED**

Run:

```bash
cd mobile
flutter test --no-pub test/theme_v2/session/session_keyboard_test.dart --plain-name "voice transcript always follows the newest line" --reporter expanded
```

Expected: scroll position remains above `maxScrollExtent`, or the old stateless composer has no owned scroll controller.

- [ ] **Step 3: Add explicit voice-tail scroll ownership**

Create and dispose one `_textScrollController`. Pass it to the Session `TextField`. On text changes while voice is busy and on a new terminal count, schedule exactly one post-frame tail update:

```dart
void _scheduleVoiceTailFollow() {
  if (_tailFollowScheduled) return;
  _tailFollowScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _tailFollowScheduled = false;
    if (!mounted || !_textScrollController.hasClients) return;
    final position = _textScrollController.position;
    _textScrollController.jumpTo(position.maxScrollExtent);
  });
}
```

Do not force-scroll ordinary keyboard editing; Flutter continues to keep the active caret visible. A new voice update intentionally overrides manual upward scrolling.

- [ ] **Step 4: Run scroll, layout, and shared voice regressions**

Run:

```bash
cd mobile
flutter test --no-pub test/theme_v2/session/session_keyboard_test.dart test/theme_v2/session/session_state_test.dart test/voice_input/voice_input_field_test.dart --reporter compact
```

Expected: all tests pass, with no render overflow or semantics exception.

- [ ] **Step 5: Commit the tail-follow fix**

```bash
git add mobile/lib/theme_v2/session/session_composer.dart mobile/test/theme_v2/session/session_keyboard_test.dart
git commit -m "fix(mobile): follow live session transcript tail"
```

---

### Task 5: Update visual baselines and verify the complete branch

**Files:**
- Modify: `mobile/test/theme_v2/session/theme_v2_session_golden_test.dart`
- Modify: `mobile/test/theme_v2/session/goldens/session-*.png` only after visual inspection.

**Interfaces:**
- Consumes: completed Session composer behavior from Tasks 1–4.
- Produces: reviewed golden baselines, clean analysis/tests, a fresh Android APK, and a device-installed build.

- [ ] **Step 1: Run Session goldens without updating**

```bash
cd mobile
flutter test --no-pub test/theme_v2/session/theme_v2_session_golden_test.dart --reporter compact
```

Expected: only intentional Session composer visual differences fail.

- [ ] **Step 2: Add review-ready golden fixtures**

Extend `_GoldenState` with `reviewReady` and `longReviewReady`. After the first pump, enter deterministic text through `session-composer-field`, unfocus it, and pump before capture:

```dart
if (state == _GoldenState.reviewReady ||
    state == _GoldenState.longReviewReady) {
  final text = state == _GoldenState.reviewReady
      ? '请整理访谈反馈，并输出三个行动建议。'
      : List<String>.generate(10, (index) => '第 ${index + 1} 行访谈重点').join('\n');
  await tester.enterText(
    find.byKey(const ValueKey('session-composer-field')),
    text,
  );
  tester.widget<TextField>(
    find.byKey(const ValueKey('session-composer-field')),
  ).focusNode!.unfocus();
  await tester.pump();
}
```

- [ ] **Step 3: Generate and inspect changed Session baselines**

```bash
cd mobile
flutter test --no-pub test/theme_v2/session/theme_v2_session_golden_test.dart --update-goldens --reporter compact
```

Inspect every changed PNG. Reject any change outside the bottom composer, keyboard offset attributable to its new height, or explicitly added state fixture.

- [ ] **Step 4: Run targeted tests and analysis**

```bash
cd mobile
flutter test --no-pub test/theme_v2/session test/voice_input --reporter compact
flutter analyze --no-pub lib/theme_v2/session/session_composer.dart lib/theme_v2/session/session_composer_state.dart lib/voice_input/voice_input_field.dart lib/voice_input/voice_input_status_icon.dart test/theme_v2/session test/voice_input
```

Expected: all tests pass and analyzer reports `No issues found!`.

- [ ] **Step 5: Run the full Flutter suite**

```bash
cd mobile
flutter test --no-pub --reporter compact
```

Expected: the complete suite passes. If whole-project analysis still reports the pre-existing `packages/chiplet_ring/example/test/widget_test.dart` missing example import, record it separately and do not modify that unrelated package.

- [ ] **Step 6: Build the latest-home Android APK**

```bash
cd mobile
flutter build apk --debug --no-pub \
  --dart-define=THEME_V2=true \
  --dart-define=TODAY_DOT_EXPERIMENT=true \
  --dart-define=API_BASE=http://127.0.0.1:8200
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced successfully.

- [ ] **Step 7: Install and launch on the connected Android device**

```bash
adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
adb -s RFCY71B21YK reverse tcp:8200 tcp:8200
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: install reports `Success`, `com.eureka.mindapp/.MainActivity` becomes foreground, and Session manually demonstrates idle, keyboard editing, long text, voice-active/no-send, final review-ready, send/reset, and Agent-reply lock states.

- [ ] **Step 8: Commit reviewed tests and baselines**

```bash
git add mobile/test/theme_v2/session/theme_v2_session_golden_test.dart mobile/test/theme_v2/session/goldens
git commit -m "test(mobile): cover session composer states"
```
