# Voice Input Field Status and Session Composer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a shared listening/finalizing icon inside every ordinary voice-input field, remove the ambiguous visible cancel action, and keep Session composer actions aligned while long text scrolls inside a five-line bound.

**Architecture:** Add a provider-neutral `VoiceInputPresentation` and reusable animated `VoiceInputStatusIcon` under `mobile/lib/voice_input/`. `VoiceInputField` continues to own start/stop, warning, and error behavior, but exposes presentation state to each concrete field decoration and accepts an optional trailing business action so chat composers can use one action rail. Every adopted input explicitly places the shared indicator within its own border; Session adds an explicit text-height bound and internal scrolling.

**Tech Stack:** Flutter/Dart, Material `TextField`/`InputDecoration`, `AnimationController`, existing `VoiceInputController` and app-owned `VoiceInputCoordinator`, Flutter widget tests and static adoption tests.

## Global Constraints

- Ordinary voice input supports `idle`, `connecting`, `listening`, and `stopping`/finalizing presentation without exposing provider-specific events.
- Ordinary inputs remain tap-to-start and tap-to-stop; stopping retains editable transcript text and never auto-submits.
- Ordinary inputs expose no visible cancel/delete control and no control that clears pre-existing text.
- Lifecycle, target-switch, interruption, and failure cancellation must still restore the exact pre-recording text and selection.
- Reka remains long-press to speak, release to send, and slide upward to cancel.
- Session grows from one to at most five visible lines; additional text scrolls inside the field.
- Session voice/stop and send actions retain fixed touch targets and bottom alignment as text grows.
- The status indicator is non-interactive, has localized semantics, and respects `MediaQuery.disableAnimations`.
- Do not add dependencies or change the backend, ASR provider, wire protocol, duration limits, retry policy, or microphone ownership.

---

## File Structure

- Create `mobile/lib/voice_input/voice_input_status_icon.dart`: owns `VoiceInputPresentation`, the state-to-label/icon mapping, listening pulse animation, and reduced-motion behavior.
- Modify `mobile/lib/voice_input/voice_input_field.dart`: changes builder contracts from a boolean to `VoiceInputPresentation`, removes the visible cancel action, fixes bottom alignment, and adds an optional `trailing` action slot.
- Modify `mobile/test/voice_input/voice_input_field_test.dart`: verifies all presentation states, reduced motion, stop semantics, lack of visible cancel, and controller-only cancellation restoration.
- Modify all adopted ordinary input files listed in Task 2: places `voice.statusIcon()` inside the real input decoration and derives read-only state from `voice.isBusy`.
- Modify `mobile/test/voice_input/voice_input_adoption_test.dart`: fail-closed inventory proving every production `VoiceInputField`/`VoiceInputTextAdapter` call site adopts `VoiceInputPresentation` and an in-field status placement.
- Modify `mobile/lib/theme_v2/session/session_composer.dart`: bounds the field, moves send into the shared action rail, and inserts the shared status into the input.
- Modify `mobile/test/theme_v2/session/session_keyboard_test.dart`: verifies internal scrolling, composer height, stable action geometry, large text, and keyboard insets.

---

### Task 1: Shared Voice Presentation and Ordinary Stop Control

**Files:**
- Create: `mobile/lib/voice_input/voice_input_status_icon.dart`
- Modify: `mobile/lib/voice_input/voice_input_field.dart`
- Test: `mobile/test/voice_input/voice_input_field_test.dart`

**Interfaces:**
- Consumes: `VoiceInputControllerState` and `VoiceInputController.canStop` from `mobile/lib/voice_input/voice_input_controller.dart`.
- Produces: `VoiceInputPresentation(VoiceInputControllerState state)`, `bool VoiceInputPresentation.isBusy`, and `Widget? VoiceInputPresentation.statusIcon({Color? color, double size = 18})`.
- Produces: `VoiceInputStatusIcon.statusKey`, `VoiceInputStatusIcon.pulseKey`, and semantic labels `正在连接语音`, `正在聆听`, `正在完成转录`.
- Produces: `VoiceInputField.trailing`, which places an optional business action after the voice action in the same bottom-aligned row.

- [ ] **Step 1: Write failing state-presentation and control tests**

Replace boolean builders in `mobile/test/voice_input/voice_input_field_test.dart` and add deterministic connecting/listening/finalizing coverage:

Add this import:

```dart
import 'package:eureka/voice_input/voice_input_status_icon.dart';
```

```dart
testWidgets('shows in-field state and only a start-or-stop action', (
  tester,
) async {
  final text = VoiceInputTextController(text: 'before ');
  final session = _WidgetFakeSession();
  final startGate = Completer<VoiceInputSessionHandle>();
  final controller = VoiceInputController(
    textController: text,
    coordinator: VoiceInputCoordinator(
      service: _GatedWidgetFakeService(startGate.future),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VoiceInputField(
          controller: controller,
          builder: (context, voice) => TextField(
            key: const Key('dictation-field'),
            controller: text,
            readOnly: voice.isBusy,
            decoration: InputDecoration(suffixIcon: voice.statusIcon()),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(VoiceInputField.micKey));
  await tester.pump();
  expect(find.byKey(VoiceInputStatusIcon.statusKey), findsOneWidget);
  expect(find.bySemanticsLabel('正在连接语音'), findsOneWidget);
  expect(find.byKey(const Key('voice-input-cancel')), findsNothing);

  startGate.complete(session);
  await tester.pump();
  expect(find.bySemanticsLabel('正在聆听'), findsOneWidget);
  expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

  await tester.tap(find.byKey(VoiceInputField.micKey));
  await tester.pump();
  expect(session.stopCount, 1);
  expect(find.bySemanticsLabel('正在完成转录'), findsOneWidget);

  session.emit(
    const VoiceTranscriptEvent(
      kind: VoiceTranscriptKind.finalTranscript,
      sequence: 1,
      text: 'before voice',
      audioDurationMs: 100,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(VoiceInputStatusIcon.statusKey), findsNothing);
});

testWidgets('reduced motion uses a static listening icon', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: VoiceInputStatusIcon(
          state: VoiceInputControllerState.listening,
        ),
      ),
    ),
  );

  expect(find.bySemanticsLabel('正在聆听'), findsOneWidget);
  expect(find.byKey(VoiceInputStatusIcon.pulseKey), findsNothing);
  expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
});
```

Add the gated service used by the first test:

```dart
class _GatedWidgetFakeService implements VoiceInputServiceClient {
  const _GatedWidgetFakeService(this.result);

  final Future<VoiceInputSessionHandle> result;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) => result;
}
```

Change the existing cancellation test to prove cancellation remains available through lifecycle/controller code without a visible button:

```dart
session.emit(
  const VoiceTranscriptEvent(
    kind: VoiceTranscriptKind.partial,
    sequence: 1,
    text: 'discard',
  ),
);
await tester.pump();
await controller.cancel();
await tester.pumpAndSettle();
expect(find.byKey(const Key('voice-input-cancel')), findsNothing);
expect(session.cancelCount, 1);
expect(text.text, 'original');
```

Update the existing adapter test so it completes normally rather than depending on the removed cancel button:

```dart
await tester.tap(find.byKey(VoiceInputField.micKey));
await tester.pump();
session.emit(
  const VoiceTranscriptEvent(
    kind: VoiceTranscriptKind.partial,
    sequence: 1,
    text: 'voice',
  ),
);
await tester.pump();
expect(plain.text, 'before voice');

await tester.tap(find.byKey(VoiceInputField.micKey));
await tester.pump();
session.emit(
  const VoiceTranscriptEvent(
    kind: VoiceTranscriptKind.finalTranscript,
    sequence: 2,
    text: 'voice',
    audioDurationMs: 100,
  ),
);
await tester.pumpAndSettle();
expect(plain.text, 'before voice');
expect(find.byKey(const Key('voice-input-cancel')), findsNothing);
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
cd mobile
flutter test test/voice_input/voice_input_field_test.dart
```

Expected: compilation fails because `VoiceInputPresentation`, `VoiceInputStatusIcon`, the presentation builder signature, and `VoiceInputField.trailing` do not exist; the old cancel control is also still rendered.

- [ ] **Step 3: Create the shared presentation widget**

Create `mobile/lib/voice_input/voice_input_status_icon.dart`:

```dart
import 'package:flutter/material.dart';

import 'voice_input_controller.dart';

@immutable
final class VoiceInputPresentation {
  const VoiceInputPresentation(this.state);

  final VoiceInputControllerState state;

  bool get isBusy => state != VoiceInputControllerState.idle;

  Widget? statusIcon({Color? color, double size = 18}) {
    if (!isBusy) return null;
    return VoiceInputStatusIcon(state: state, color: color, size: size);
  }
}

final class VoiceInputStatusIcon extends StatefulWidget {
  const VoiceInputStatusIcon({
    super.key,
    required this.state,
    this.color,
    this.size = 18,
  });

  static const statusKey = Key('voice-input-status');
  static const pulseKey = Key('voice-input-listening-pulse');

  final VoiceInputControllerState state;
  final Color? color;
  final double size;

  @override
  State<VoiceInputStatusIcon> createState() => _VoiceInputStatusIconState();
}

class _VoiceInputStatusIconState extends State<VoiceInputStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(VoiceInputStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    final animate =
        widget.state == VoiceInputControllerState.listening &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == VoiceInputControllerState.idle) {
      return const SizedBox.shrink();
    }
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final label = switch (widget.state) {
      VoiceInputControllerState.idle => '',
      VoiceInputControllerState.connecting => '正在连接语音',
      VoiceInputControllerState.listening => '正在聆听',
      VoiceInputControllerState.stopping => '正在完成转录',
    };
    final indicator = switch (widget.state) {
      VoiceInputControllerState.connecting ||
      VoiceInputControllerState.stopping => SizedBox.square(
        dimension: widget.size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      VoiceInputControllerState.listening => _listeningIcon(color),
      VoiceInputControllerState.idle => const SizedBox.shrink(),
    };
    return Semantics(
      key: VoiceInputStatusIcon.statusKey,
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox.square(dimension: 32, child: Center(child: indicator)),
      ),
    );
  }

  Widget _listeningIcon(Color color) {
    final icon = Icon(
      Icons.graphic_eq_rounded,
      size: widget.size,
      color: color,
    );
    if (MediaQuery.disableAnimationsOf(context)) return icon;
    return FadeTransition(
      key: VoiceInputStatusIcon.pulseKey,
      opacity: Tween<double>(begin: 0.58, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: icon,
      ),
    );
  }
}
```

- [ ] **Step 4: Change `VoiceInputField` to the presentation API and remove visible cancel**

In `mobile/lib/voice_input/voice_input_field.dart`, import the new file and replace the public typedef/constructor fields with:

```dart
import 'voice_input_status_icon.dart';

typedef VoiceInputFieldBuilder =
    Widget Function(BuildContext context, VoiceInputPresentation voice);

final class VoiceInputField extends StatelessWidget {
  const VoiceInputField({
    super.key,
    required this.controller,
    required this.builder,
    this.enabled = true,
    this.trailing,
  });

  static const micKey = Key('voice-input-mic');

  final VoiceInputController controller;
  final VoiceInputFieldBuilder builder;
  final bool enabled;
  final Widget? trailing;
```

Replace the active row in `build` with a bottom-aligned row and no cancel action:

```dart
final voice = VoiceInputPresentation(controller.state);
return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: builder(context, voice)),
        const SizedBox(width: 6),
        IconButton(
          key: micKey,
          tooltip: switch (controller.state) {
            VoiceInputControllerState.idle => '开始语音输入',
            VoiceInputControllerState.connecting => '正在连接语音',
            VoiceInputControllerState.listening => '停止语音输入',
            VoiceInputControllerState.stopping => '正在完成转录',
          },
          onPressed: !enabled
              ? null
              : controller.state == VoiceInputControllerState.idle
              ? () => unawaited(controller.start())
              : controller.canStop
              ? () => unawaited(controller.stop())
              : null,
          icon: Icon(
            controller.state == VoiceInputControllerState.idle
                ? Icons.mic_none_rounded
                : Icons.stop_rounded,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    ),
    if (controller.isDurationWarning)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '还可说 30 秒',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    if (!voice.isBusy && controller.errorCode != null)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _errorCopy(controller.errorCode!),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
  ],
);
```

Update the adapter typedef and forwarding builder:

```dart
typedef VoiceInputTextAdapterBuilder =
    Widget Function(
      BuildContext context,
      VoiceInputTextController controller,
      VoiceInputPresentation voice,
    );

builder: (context, voice) =>
    widget.builder(context, _textController, voice),
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
cd mobile
dart format lib/voice_input/voice_input_status_icon.dart lib/voice_input/voice_input_field.dart test/voice_input/voice_input_field_test.dart
flutter test test/voice_input/voice_input_field_test.dart
flutter analyze lib/voice_input/voice_input_status_icon.dart lib/voice_input/voice_input_field.dart test/voice_input/voice_input_field_test.dart
```

Expected: all focused tests pass and analyzer reports `No issues found!`.

- [ ] **Step 6: Commit the shared presentation**

```bash
git add mobile/lib/voice_input/voice_input_status_icon.dart mobile/lib/voice_input/voice_input_field.dart mobile/test/voice_input/voice_input_field_test.dart
git commit -m "feat(mobile): show voice state inside text fields"
```

---

### Task 2: Adopt the In-field Indicator Across Every Ordinary Input

**Files:**
- Modify: `mobile/lib/flash/flash_sheet.dart`
- Modify: `mobile/lib/pages/chat_page.dart`
- Modify: `mobile/lib/pages/session_detail_page.dart`
- Modify: `mobile/lib/theme_v2/asset_detail/markdown_field_editor.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editor.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Modify: `mobile/lib/theme_v2/report/report_create_sheet.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Test: `mobile/test/voice_input/voice_input_adoption_test.dart`

**Interfaces:**
- Consumes: `VoiceInputPresentation.isBusy` and `VoiceInputPresentation.statusIcon({Color? color, double size = 18})` from Task 1.
- Produces: every non-Session production builder places the returned status widget within its concrete `InputDecoration.suffixIcon`.
- Preserves: existing field keys, validation, counters, labels, hint text, send/save behavior, and Reka behavior.

- [ ] **Step 1: Extend the fail-closed adoption inventory and verify RED**

Add this test to `mobile/test/voice_input/voice_input_adoption_test.dart`:

```dart
test('every ordinary voice builder places shared status inside its field', () {
  const expectedStatusCalls = <String, int>{
    'lib/flash/flash_sheet.dart': 1,
    'lib/pages/chat_page.dart': 1,
    'lib/pages/session_detail_page.dart': 1,
    'lib/theme_v2/asset_detail/markdown_field_editor.dart': 1,
    'lib/theme_v2/library/asset/asset_editor.dart': 1,
    'lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart': 2,
    'lib/theme_v2/report/report_create_sheet.dart': 1,
    'lib/theme_v2/report/report_run_page.dart': 2,
  };

  for (final entry in expectedStatusCalls.entries) {
    final source = File(entry.key).readAsStringSync();
    expect(
      '.statusIcon('.allMatches(source),
      hasLength(entry.value),
      reason: entry.key,
    );
    expect(source, isNot(contains('voiceBusy')), reason: entry.key);
  }
});
```

Run:

```bash
cd mobile
flutter test test/voice_input/voice_input_adoption_test.dart
```

Expected: FAIL because production builders still accept `voiceBusy` and do not call `.statusIcon(`.

- [ ] **Step 2: Migrate Flash and legacy chat fields**

In `mobile/lib/flash/flash_sheet.dart`, `mobile/lib/pages/chat_page.dart`, and `mobile/lib/pages/session_detail_page.dart`, change each builder to `builder: (context, voice)`, set `readOnly: voice.isBusy`, and add the status inside its existing decoration:

```dart
suffixIcon: voice.statusIcon(color: eu.brand),
suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
```

Keep the existing hint, fill, padding, and border values unchanged. In `flash_sheet.dart`, preserve `enabled: !_sending`; in both legacy chat fields, preserve `streaming` send disablement and existing page-owned send button behavior.

- [ ] **Step 3: Migrate report fields**

In `mobile/lib/theme_v2/report/report_create_sheet.dart`, change the builder and make the decoration non-const:

```dart
builder: (context, voice) => TextField(
  key: const ValueKey('report-create-intent'),
  controller: _intent,
  readOnly: voice.isBusy,
  autofocus: true,
  minLines: 3,
  maxLines: 5,
  maxLength: 4000,
  textInputAction: TextInputAction.done,
  onChanged: (_) => setState(() {}),
  onSubmitted: (_) {
    if (!voice.isBusy) unawaited(_submit());
  },
  decoration: InputDecoration(
    labelText: '你想生成什么报告？',
    hintText: '例如：总结最近一个月的跑步训练，并分析恢复情况',
    alignLabelWithHint: true,
    suffixIcon: voice.statusIcon(color: context.themeV2.accent),
  ),
),
```

In both builders in `mobile/lib/theme_v2/report/report_run_page.dart`, use `voice.isBusy` and add:

```dart
suffixIcon: voice.statusIcon(color: context.themeV2.accent),
```

Retain the existing label, hint, max length, max lines, and clarification `onBusyChanged` behavior.

- [ ] **Step 4: Migrate Skill and asset fields**

For both builders in `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`, use `voice.isBusy` and decorate as follows:

```dart
decoration: _inputDecoration(
  '例如：记录每次跑步的距离、配速、地点和感受',
).copyWith(suffixIcon: voice.statusIcon(color: tokens.accent)),
```

```dart
decoration: InputDecoration(
  hintText: question.placeholder,
  suffixIcon: voice.statusIcon(color: context.themeV2.accent),
),
```

In `mobile/lib/theme_v2/library/asset/asset_editor.dart`, pass the built widget into the helper rather than making the helper depend on voice types:

```dart
builder: (context, controller, voice) => _shortTextField(
  controller,
  label: label,
  readOnly: voice.isBusy,
  statusIcon: voice.statusIcon(color: context.themeV2.accent),
),
```

Extend `_shortTextField` with `Widget? statusIcon` and assign it to `InputDecoration.suffixIcon`; pass `statusIcon: null` from the non-voice branch.

In `mobile/lib/theme_v2/asset_detail/markdown_field_editor.dart`, replace `InputDecoration.collapsed` with an equivalent borderless collapsed decoration that accepts the shared suffix:

```dart
builder: (context, controller, voice) => TextField(
  key: const ValueKey('markdown-editor-input'),
  controller: controller,
  readOnly: voice.isBusy,
  minLines: 9,
  maxLines: null,
  keyboardType: TextInputType.multiline,
  decoration: InputDecoration(
    hintText: '支持 Markdown：# 标题、**加粗**、*斜体*、- 列表、> 引用…',
    border: InputBorder.none,
    isCollapsed: true,
    suffixIcon: voice.statusIcon(color: tokens.accent),
    suffixIconConstraints: const BoxConstraints(
      minWidth: 32,
      minHeight: 32,
    ),
  ),
),
```

- [ ] **Step 5: Run the adoption and affected feature suites**

Run:

```bash
cd mobile
dart format lib/flash/flash_sheet.dart lib/pages/chat_page.dart lib/pages/session_detail_page.dart lib/theme_v2/asset_detail/markdown_field_editor.dart lib/theme_v2/library/asset/asset_editor.dart lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart lib/theme_v2/report/report_create_sheet.dart lib/theme_v2/report/report_run_page.dart test/voice_input/voice_input_adoption_test.dart
flutter test test/voice_input/voice_input_adoption_test.dart test/voice_input/voice_input_field_test.dart test/theme_v2/report test/theme_v2/library test/theme_v2/asset_detail
flutter analyze lib/flash/flash_sheet.dart lib/pages/chat_page.dart lib/pages/session_detail_page.dart lib/theme_v2/asset_detail/markdown_field_editor.dart lib/theme_v2/library/asset/asset_editor.dart lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart lib/theme_v2/report/report_create_sheet.dart lib/theme_v2/report/report_run_page.dart test/voice_input/voice_input_adoption_test.dart
```

Expected: all selected tests pass and analyzer reports `No issues found!`.

- [ ] **Step 6: Commit the app-wide adoption**

```bash
git add mobile/lib/flash/flash_sheet.dart mobile/lib/pages/chat_page.dart mobile/lib/pages/session_detail_page.dart mobile/lib/theme_v2/asset_detail/markdown_field_editor.dart mobile/lib/theme_v2/library/asset/asset_editor.dart mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart mobile/lib/theme_v2/report/report_create_sheet.dart mobile/lib/theme_v2/report/report_run_page.dart mobile/test/voice_input/voice_input_adoption_test.dart
git commit -m "refactor(mobile): place voice status inside authoring fields"
```

---

### Task 3: Bound the Session Composer and Fix the Action Rail

**Files:**
- Modify: `mobile/lib/theme_v2/session/session_composer.dart`
- Modify: `mobile/test/theme_v2/session/session_keyboard_test.dart`
- Modify: `mobile/test/voice_input/voice_input_adoption_test.dart`

**Interfaces:**
- Consumes: `VoiceInputField.trailing` and `VoiceInputPresentation` from Task 1.
- Produces: `SessionComposer.maxVisibleLines = 5` and `ValueKey('session-composer-field-bound')` for deterministic geometry tests.
- Preserves: `ValueKey('session-composer-field')`, `ValueKey('session-send')`, add-context behavior, keyboard inset behavior, and explicit send semantics.

- [ ] **Step 1: Write failing long-text geometry tests**

Extend `mobile/test/theme_v2/session/session_keyboard_test.dart`:

```dart
testWidgets('long text scrolls inside a bounded composer', (tester) async {
  final controller = FakeSessionController();
  await _pumpKeyboard(tester, controller: controller);

  final fieldFinder = find.byKey(const ValueKey('session-composer-field'));
  await tester.enterText(
    fieldFinder,
    List<String>.generate(40, (index) => '第$index段很长的输入内容').join('\n'),
  );
  await tester.pump();

  final bound = tester.getSize(
    find.byKey(const ValueKey('session-composer-field-bound')),
  );
  final editable = tester.widget<EditableText>(
    find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
  );
  expect(bound.height, lessThanOrEqualTo(116));
  expect(editable.scrollController.hasClients, isTrue);
  expect(editable.scrollController.position.maxScrollExtent, greaterThan(0));
  expect(tester.takeException(), isNull);
});

testWidgets('voice and send actions keep a fixed bottom alignment', (
  tester,
) async {
  final controller = FakeSessionController();
  await _pumpKeyboard(tester, controller: controller);

  await tester.enterText(
    find.byKey(const ValueKey('session-composer-field')),
    List<String>.filled(30, '很长的消息内容').join('\n'),
  );
  await tester.pump();

  final mic = tester.getRect(find.byKey(VoiceInputField.micKey));
  final send = tester.getRect(find.byKey(const ValueKey('session-send')));
  expect(mic.size, const Size.square(48));
  expect(send.size, const Size.square(48));
  expect((mic.bottom - send.bottom).abs(), lessThan(0.5));
  expect(tester.takeException(), isNull);
});
```

Import `package:eureka/voice_input/voice_input_field.dart`. Add this entry to `expectedStatusCalls` in the adoption inventory:

```dart
'lib/theme_v2/session/session_composer.dart': 1,
```

- [ ] **Step 2: Run the Session tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/session/session_keyboard_test.dart
```

Expected: FAIL because `session-composer-field-bound` does not exist and the mic/send buttons still belong to nested action rows with different geometry.

- [ ] **Step 3: Implement the explicit five-line bound**

In `mobile/lib/theme_v2/session/session_composer.dart`, add:

```dart
import 'dart:math' as math;

static const maxVisibleLines = 5;
```

Inside `build`, compute an accessibility-aware maximum field height:

```dart
final scaledLineHeight =
    MediaQuery.textScalerOf(context).scale(13) * 1.35;
final maxFieldHeight = math.max(
  ThemeV2Sizes.minTouchTarget,
  scaledLineHeight * maxVisibleLines + 24,
);
```

Wrap the `TextField` returned by the voice builder:

```dart
builder: (context, voice) => ConstrainedBox(
  key: const ValueKey('session-composer-field-bound'),
  constraints: BoxConstraints(maxHeight: maxFieldHeight),
  child: TextField(
    key: const ValueKey('session-composer-field'),
    controller: controller,
    focusNode: focusNode,
    readOnly: voice.isBusy,
    minLines: 1,
    maxLines: maxVisibleLines,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    style: TextStyle(
      color: tokens.foreground,
      fontSize: 13,
      height: 1.35,
    ),
    decoration: InputDecoration(
      hintText: '问 Agent 任何事…',
      hintStyle: TextStyle(color: tokens.muted),
      prefixIcon: IconButton(
        tooltip: '添加上下文资产',
        onPressed: voice.isBusy ? null : onAddContext,
        constraints: const BoxConstraints(
          minWidth: ThemeV2Sizes.minTouchTarget,
          minHeight: ThemeV2Sizes.minTouchTarget,
        ),
        icon: Icon(
          Icons.auto_awesome_outlined,
          color: tokens.accent,
          size: 18,
        ),
      ),
      suffixIcon: voice.statusIcon(color: tokens.accent),
      suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      filled: true,
      fillColor: tokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
        borderSide: BorderSide(color: tokens.accent),
      ),
    ),
  ),
),
```

- [ ] **Step 4: Move send into the single action rail**

Remove the outer `Row` around `VoiceInputField`. Pass the existing send control through `trailing`:

```dart
return VoiceInputField(
  key: const ValueKey('session-composer-voice'),
  controller: voiceController,
  enabled: !streaming,
  trailing: Semantics(
    label: streaming ? '正在发送' : '发送消息',
    button: true,
    enabled: enabled,
    child: SizedBox.square(
      dimension: ThemeV2Sizes.minTouchTarget,
      child: IconButton(
        key: const ValueKey('session-send'),
        onPressed: enabled ? () => _submit(value.text) : null,
        style: IconButton.styleFrom(
          backgroundColor: enabled ? tokens.accent : tokens.border,
          foregroundColor: tokens.background,
          disabledForegroundColor: tokens.muted,
        ),
        icon: streaming
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.muted,
                ),
              )
            : const Icon(Icons.arrow_upward_rounded, size: 20),
      ),
    ),
  ),
  builder: (context, voice) => ConstrainedBox(
    key: const ValueKey('session-composer-field-bound'),
    constraints: BoxConstraints(maxHeight: maxFieldHeight),
    child: TextField(
      key: const ValueKey('session-composer-field'),
      controller: controller,
      focusNode: focusNode,
      readOnly: voice.isBusy,
      minLines: 1,
      maxLines: maxVisibleLines,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: TextStyle(
        color: tokens.foreground,
        fontSize: 13,
        height: 1.35,
      ),
      decoration: InputDecoration(
        hintText: '问 Agent 任何事…',
        hintStyle: TextStyle(color: tokens.muted),
        prefixIcon: IconButton(
          tooltip: '添加上下文资产',
          onPressed: voice.isBusy ? null : onAddContext,
          constraints: const BoxConstraints(
            minWidth: ThemeV2Sizes.minTouchTarget,
            minHeight: ThemeV2Sizes.minTouchTarget,
          ),
          icon: Icon(
            Icons.auto_awesome_outlined,
            color: tokens.accent,
            size: 18,
          ),
        ),
        suffixIcon: voice.statusIcon(color: tokens.accent),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
          borderSide: BorderSide(color: tokens.accent),
        ),
      ),
    ),
  ),
);
```

- [ ] **Step 5: Run Session, shared voice, and full mobile gates**

Run:

```bash
cd mobile
dart format lib/theme_v2/session/session_composer.dart test/theme_v2/session/session_keyboard_test.dart test/voice_input/voice_input_adoption_test.dart
flutter test test/theme_v2/session/session_keyboard_test.dart test/theme_v2/session/session_state_test.dart test/voice_input
flutter test
flutter analyze
flutter build apk --debug --dart-define=THEME_V2=true --dart-define=TODAY_DOT_EXPERIMENT=true --dart-define=API_BASE=http://127.0.0.1:8200
```

Expected: all tests pass, analyzer reports `No issues found!`, and Flutter produces `build/app/outputs/flutter-apk/app-debug.apk` without overflow or compilation errors.

- [ ] **Step 6: Inspect final scope and commit**

Run:

```bash
git diff --check
git status --short
git diff --stat 06de429..HEAD
```

Expected: only the planned voice-input, adopted field, Session composer, and test files are changed; there are no whitespace errors.

Commit:

```bash
git add mobile/lib/theme_v2/session/session_composer.dart mobile/test/theme_v2/session/session_keyboard_test.dart mobile/test/voice_input/voice_input_adoption_test.dart
git commit -m "fix(mobile): keep session composer actions aligned"
```

---

## Final Acceptance Walkthrough

- [ ] Start voice input in Session and verify the waveform appears inside the input border while the stop square remains in the fixed action rail.
- [ ] Stop voice input and verify finalizing shows progress inside the field, then disappears when final text arrives.
- [ ] Enter more than five lines and verify the field scrolls internally while microphone/stop and send remain bottom-aligned.
- [ ] Repeat voice start/stop in report creation, report clarification, Skill description, Skill “其他”, Flash, asset short text, and Markdown editing; verify the same in-field state vocabulary.
- [ ] Switch voice targets or leave a recording page and verify provisional text is rolled back without any visible “另一个输入正在使用麦克风” or clear-all action.
- [ ] Long-press Reka, slide upward, and release; verify Reka still cancels without creating a Flash.
