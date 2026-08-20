import 'dart:async';

import 'package:eureka/voice_input/voice_input_controller.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_field.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_scope.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
            builder: (context, voiceBusy) => TextField(
              key: const Key('dictation-field'),
              controller: text,
              readOnly: voiceBusy,
              onSubmitted: (_) => submits += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump();
    expect(find.byKey(VoiceInputField.cancelKey), findsOneWidget);
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
            builder: (_, voiceBusy) =>
                TextField(controller: text, readOnly: voiceBusy),
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
    await tester.tap(find.byKey(VoiceInputField.cancelKey));
    await tester.pumpAndSettle();
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
              builder: (_, controller, voiceBusy) =>
                  TextField(controller: controller, readOnly: voiceBusy),
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

    await tester.tap(find.byKey(VoiceInputField.cancelKey));
    await tester.pumpAndSettle();
    expect(plain.text, 'before ');
  });
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
