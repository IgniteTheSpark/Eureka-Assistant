import 'dart:async';

import 'package:eureka/voice_input/voice_input_controller.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_field.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_scope.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:eureka/voice_input/voice_input_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation exposes provider-neutral status labels', () {
    expect(
      const VoiceInputPresentation(VoiceInputControllerState.idle).statusLabel,
      isNull,
    );
    expect(
      const VoiceInputPresentation(
        VoiceInputControllerState.connecting,
      ).statusLabel,
      '正在连接语音',
    );
    expect(
      const VoiceInputPresentation(
        VoiceInputControllerState.listening,
      ).statusLabel,
      '正在聆听',
    );
    expect(
      const VoiceInputPresentation(
        VoiceInputControllerState.stopping,
      ).statusLabel,
      '正在完成转录',
    );
  });

  testWidgets('custom layout receives the field and canonical voice action', (
    tester,
  ) async {
    final text = VoiceInputTextController();
    final session = _WidgetFakeSession();
    final controller = VoiceInputController(
      textController: text,
      coordinator: VoiceInputCoordinator(service: _WidgetFakeService(session)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceInputField(
            controller: controller,
            layoutBuilder: (context, voice, field, voiceAction) => Row(
              key: const Key('custom-voice-layout'),
              children: [
                Expanded(child: field),
                voiceAction,
              ],
            ),
            builder: (_, _) => const TextField(key: Key('custom-field')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('custom-voice-layout')), findsOneWidget);
    expect(find.byKey(const Key('custom-field')), findsOneWidget);
    expect(find.byKey(VoiceInputField.micKey), findsOneWidget);
    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump();
    expect(controller.state, VoiceInputControllerState.listening);

    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump();
    session.emit(
      const VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.finalTranscript,
        sequence: 1,
        text: '完成',
        audioDurationMs: 100,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('mic starts/stops, shows provisional text, and never submits', (
    tester,
  ) async {
    final text = VoiceInputTextController();
    final session = _WidgetFakeSession();
    final controller = VoiceInputController(
      textController: text,
      coordinator: VoiceInputCoordinator(service: _WidgetFakeService(session)),
    );
    var submits = 0;

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
              onSubmitted: (_) => submits += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump();
    expect(find.byKey(const Key('voice-input-cancel')), findsNothing);
    expect(find.bySemanticsLabel('正在聆听'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('dictation-field')))
          .readOnly,
      isTrue,
    );

    session.emit(
      const VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.partial,
        sequence: 1,
        text: '临时文字',
      ),
    );
    await tester.pump();
    expect(text.text, '临时文字');

    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump();
    expect(session.stopCount, 1);
    expect(submits, 0);
    session.emit(
      const VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.finalTranscript,
        sequence: 2,
        text: '临时文字',
        audioDurationMs: 10,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('shows connecting, listening, and finalizing inside the field', (
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

  testWidgets('cancel restores text and warning copy is visible', (
    tester,
  ) async {
    final text = VoiceInputTextController(text: 'original');
    final session = _WidgetFakeSession();
    final controller = VoiceInputController(
      textController: text,
      coordinator: VoiceInputCoordinator(service: _WidgetFakeService(session)),
      maximumDuration: const Duration(milliseconds: 20),
      warningDuration: const Duration(milliseconds: 15),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceInputField(
            controller: controller,
            builder: (_, voice) => TextField(
              controller: text,
              readOnly: voice.isBusy,
              decoration: InputDecoration(suffixIcon: voice.statusIcon()),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump(const Duration(milliseconds: 6));
    expect(find.text('还可说 30 秒'), findsOneWidget);

    session.emit(
      const VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.partial,
        sequence: 1,
        text: 'discard',
      ),
    );
    await tester.pump();
    unawaited(controller.cancel());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-input-cancel')), findsNothing);
    expect(session.cancelCount, 1);
    expect(controller.isBusy, isFalse);
    expect(text.text, 'original');
  });

  testWidgets('adapter adds voice input to an existing plain controller', (
    tester,
  ) async {
    final plain = TextEditingController(text: 'before ');
    final session = _WidgetFakeSession();

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceInputHost(
          service: _WidgetFakeService(session),
          child: Scaffold(
            body: VoiceInputTextAdapter(
              controller: plain,
              builder: (_, controller, voice) => TextField(
                controller: controller,
                readOnly: voice.isBusy,
                decoration: InputDecoration(suffixIcon: voice.statusIcon()),
              ),
            ),
          ),
        ),
      ),
    );

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
  });
}

class _GatedWidgetFakeService implements VoiceInputServiceClient {
  const _GatedWidgetFakeService(this.result);

  final Future<VoiceInputSessionHandle> result;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) => result;
}

class _WidgetFakeService implements VoiceInputServiceClient {
  _WidgetFakeService(this.session);
  final _WidgetFakeSession session;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async => session;
}

class _WidgetFakeSession implements VoiceInputSessionHandle {
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>();
  int stopCount = 0;
  int cancelCount = 0;

  void emit(VoiceInputEvent event) => _events.add(event);

  @override
  Stream<VoiceInputEvent> get events => _events.stream;
  @override
  VoiceInputMode get mode => VoiceInputMode.ordinary;
  @override
  String get voiceSessionId => 'widget-session';
  @override
  Future<void> stop() async => stopCount += 1;
  @override
  Future<void> cancel() async => cancelCount += 1;
  @override
  Future<void> dispose() async {}
}
