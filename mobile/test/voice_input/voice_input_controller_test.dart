import 'dart:async';

import 'package:eureka/voice_input/voice_input_controller.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'replaces selected range and clears provisional style on final',
    () async {
      final text = VoiceInputTextController(
        text: 'hello NAME!',
        selection: const TextSelection(baseOffset: 6, extentOffset: 10),
      );
      final session = _FakeSession();
      final controller = VoiceInputController(
        textController: text,
        service: _FakeService([session]),
        lease: VoiceInputLease(),
      );

      expect(await controller.start(), isTrue);
      session.emit(_partial(1, 'Alice'));
      await pumpEventQueue();
      expect(text.text, 'hello Alice!');
      expect(text.provisionalRange, const TextRange(start: 6, end: 11));

      session.emit(_final(2, 'Alice Smith'));
      await pumpEventQueue();
      expect(text.text, 'hello Alice Smith!');
      expect(text.provisionalRange, isNull);
      expect(controller.isBusy, isFalse);
      expect(controller.terminalCount, 1);
    },
  );

  test(
    'partial replacement, ordered stable text, and stale rejection',
    () async {
      final text = VoiceInputTextController(
        text: 'abcXYZ',
        selection: const TextSelection.collapsed(offset: 3),
      );
      final session = _FakeSession();
      final controller = VoiceInputController(
        textController: text,
        service: _FakeService([session]),
        lease: VoiceInputLease(),
      );

      await controller.start();
      session.emit(_partial(1, 'hel'));
      session.emit(_partial(2, 'hello'));
      session.emit(_partial(1, 'stale'));
      session.emit(_stable(3, 'hello'));
      session.emit(_partial(4, 'world'));
      await pumpEventQueue();

      expect(text.text, 'abchello worldXYZ');
      expect(text.provisionalRange, const TextRange(start: 9, end: 14));
    },
  );

  test('cancel and failure restore the exact original editing value', () async {
    const original = TextEditingValue(
      text: 'before selected after',
      selection: TextSelection(baseOffset: 7, extentOffset: 15),
      composing: TextRange(start: 0, end: 6),
    );
    final text = VoiceInputTextController.fromValue(original);
    final first = _FakeSession();
    final second = _FakeSession();
    final controller = VoiceInputController(
      textController: text,
      service: _FakeService([first, second]),
      lease: VoiceInputLease(),
    );

    await controller.start();
    first.emit(_partial(1, 'temporary'));
    await pumpEventQueue();
    await controller.cancel();
    expect(text.value, original);
    expect(first.cancelCount, 1);

    await controller.start();
    second.emit(_partial(1, 'temporary again'));
    second.emit(
      const VoiceInputFailure(
        code: VoiceInputErrorCode.connectionLost,
        retryable: true,
      ),
    );
    await pumpEventQueue();
    expect(text.value, original);
    expect(controller.errorCode, VoiceInputErrorCode.connectionLost);
    expect(controller.terminalCount, 2);
  });

  test('one lease rejects a second field until the first releases', () async {
    final lease = VoiceInputLease();
    final firstSession = _FakeSession();
    final secondSession = _FakeSession();
    final first = VoiceInputController(
      textController: VoiceInputTextController(),
      service: _FakeService([firstSession]),
      lease: lease,
    );
    final secondService = _FakeService([secondSession]);
    final second = VoiceInputController(
      textController: VoiceInputTextController(),
      service: secondService,
      lease: lease,
    );

    expect(await first.start(), isTrue);
    expect(await second.start(), isFalse);
    expect(second.errorCode, VoiceInputErrorCode.busy);
    expect(secondService.startCount, 0);

    await first.cancel();
    expect(await second.start(), isTrue);
  });

  test('stop-final timeout restores text and cancels the session', () async {
    final text = VoiceInputTextController(text: 'keep');
    final session = _FakeSession();
    final controller = VoiceInputController(
      textController: text,
      service: _FakeService([session]),
      lease: VoiceInputLease(),
      finalTimeout: const Duration(milliseconds: 10),
    );

    await controller.start();
    session.emit(_partial(1, 'discard'));
    await controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(session.stopCount, 1);
    expect(session.cancelCount, 1);
    expect(text.text, 'keep');
    expect(controller.errorCode, VoiceInputErrorCode.connectionLost);
    expect(controller.isBusy, isFalse);
  });

  test(
    'ordinary duration warns 30 seconds before five-minute auto-stop',
    () async {
      final session = _FakeSession();
      final controller = VoiceInputController(
        textController: VoiceInputTextController(),
        service: _FakeService([session]),
        lease: VoiceInputLease(),
        maximumDuration: const Duration(milliseconds: 40),
        warningDuration: const Duration(milliseconds: 20),
      );

      expect(controller.productionMaximumDuration, const Duration(minutes: 5));
      expect(controller.productionWarningAt, const Duration(seconds: 270));
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(controller.isDurationWarning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(session.stopCount, 1);
      expect(controller.isStopping, isTrue);

      session.emit(_final(1, 'complete'));
      session.emit(
        const VoiceInputFailure(
          code: VoiceInputErrorCode.connectionLost,
          retryable: true,
        ),
      );
      await pumpEventQueue();
      expect(controller.terminalCount, 1);
    },
  );
}

VoiceTranscriptEvent _partial(int sequence, String text) =>
    VoiceTranscriptEvent(
      kind: VoiceTranscriptKind.partial,
      sequence: sequence,
      text: text,
    );

VoiceTranscriptEvent _stable(int sequence, String text) => VoiceTranscriptEvent(
  kind: VoiceTranscriptKind.stable,
  sequence: sequence,
  text: text,
);

VoiceTranscriptEvent _final(int sequence, String text) => VoiceTranscriptEvent(
  kind: VoiceTranscriptKind.finalTranscript,
  sequence: sequence,
  text: text,
  audioDurationMs: 100,
);

class _FakeService implements VoiceInputServiceClient {
  _FakeService(this.sessions);

  final List<_FakeSession> sessions;
  int startCount = 0;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async {
    final session = sessions[startCount++];
    session.modeValue = mode;
    return session;
  }
}

class _FakeSession implements VoiceInputSessionHandle {
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>();
  int stopCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;
  VoiceInputMode modeValue = VoiceInputMode.ordinary;

  void emit(VoiceInputEvent event) => _events.add(event);

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => modeValue;

  @override
  String get voiceSessionId => 'fake-session';

  @override
  Future<void> stop() async => stopCount += 1;

  @override
  Future<void> cancel() async => cancelCount += 1;

  @override
  Future<void> dispose() async => disposeCount += 1;
}
