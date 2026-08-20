import 'dart:async';

import 'package:eureka/voice_input/reka_voice_capture.dart';
import 'package:eureka/voice_input/voice_input_controller.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary and Reka supersede each other without busy', () async {
    final firstOrdinary = _FakeSession('ordinary-first');
    final rekaSession = _FakeSession('reka-middle');
    final secondOrdinary = _FakeSession('ordinary-second');
    final shared = VoiceInputCoordinator(
      service: _QueueService([firstOrdinary, rekaSession, secondOrdinary]),
    );
    final ordinary = VoiceInputController(
      textController: VoiceInputTextController(text: 'original'),
      coordinator: shared,
    );
    final reka = RekaVoiceCaptureCoordinator(
      coordinator: shared,
      sendFlash: (_, _) async {},
      haptic: () {},
    );

    expect(await ordinary.start(), isTrue);
    firstOrdinary.emit(_partial(1, 'temporary'));
    await pumpEventQueue();
    expect(await reka.begin(), isTrue);
    expect(firstOrdinary.cancelCount, 1);
    expect(ordinary.textController.text, 'original');
    expect(ordinary.errorCode, isNull);
    expect(rekaSession.modeValue, VoiceInputMode.reka);

    expect(await ordinary.start(), isTrue);
    expect(rekaSession.cancelCount, 1);
    expect(reka.state, RekaVoiceCaptureState.idle);
    expect(reka.errorCode, isNull);
    expect(secondOrdinary.modeValue, VoiceInputMode.ordinary);

    await ordinary.close();
    ordinary.dispose();
    await reka.close();
    reka.dispose();
    await shared.dispose();
  });

  test(
    'release before connection readiness stops then sends one final',
    () async {
      final service = _DelayedService();
      final sent = <(String, String)>[];
      var haptics = 0;
      final coordinator = RekaVoiceCaptureCoordinator(
        coordinator: VoiceInputCoordinator(service: service),
        sendFlash: (text, sessionId) async => sent.add((text, sessionId)),
        haptic: () => haptics += 1,
      );

      final start = coordinator.begin();
      await coordinator.release();
      final session = _FakeSession('voice-early');
      service.complete(session);
      await start;
      await pumpEventQueue();

      expect(session.modeValue, VoiceInputMode.reka);
      expect(session.stopCount, 1);
      expect(haptics, 1);
      expect(sent, isEmpty);

      session.emit(_final(1, '  记得周五交报告  '));
      await pumpEventQueue();
      expect(sent, [('记得周五交报告', 'voice-early')]);
      expect(coordinator.state, RekaVoiceCaptureState.idle);

      session.emit(_final(2, '不能重复发送'));
      await pumpEventQueue();
      expect(sent, hasLength(1));
    },
  );

  test(
    'cancel before connection readiness cancels the eventual session',
    () async {
      final service = _DelayedService();
      final sent = <String>[];
      final coordinator = RekaVoiceCaptureCoordinator(
        coordinator: VoiceInputCoordinator(service: service),
        sendFlash: (text, _) async => sent.add(text),
        haptic: () {},
      );

      final start = coordinator.begin();
      await service.started.future;
      coordinator.updateVerticalOffset(-100);
      await coordinator.release();
      final session = _FakeSession('voice-early-cancel');
      service.complete(session);
      await start;

      expect(session.cancelCount, 1);
      expect(coordinator.state, RekaVoiceCaptureState.idle);
      expect(sent, isEmpty);
    },
  );

  test('shows ordered provisional text and arms cancel at 72 pixels', () async {
    final session = _FakeSession('voice-move');
    var haptics = 0;
    final coordinator = _coordinator(session, haptic: () => haptics += 1);

    await coordinator.begin();
    session.emit(_partial(1, '你好'));
    session.emit(_stable(2, '你好'));
    session.emit(_partial(3, 'world'));
    session.emit(_partial(2, 'stale'));
    await pumpEventQueue();

    expect(coordinator.transcript, '你好world');
    expect(coordinator.state, RekaVoiceCaptureState.listening);
    coordinator.updateVerticalOffset(-72);
    expect(coordinator.state, RekaVoiceCaptureState.cancelArmed);
    expect(haptics, 2);
    coordinator.updateVerticalOffset(-30);
    expect(coordinator.state, RekaVoiceCaptureState.listening);
    coordinator.updateVerticalOffset(-80);
    expect(haptics, 3);
  });

  test(
    'release while cancel armed creates nothing and ignores late final',
    () async {
      final session = _FakeSession('voice-cancel');
      final sent = <String>[];
      final coordinator = _coordinator(
        session,
        sendFlash: (text, _) async => sent.add(text),
      );

      await coordinator.begin();
      session.emit(_partial(1, '不要发送'));
      coordinator.updateVerticalOffset(-100);
      await coordinator.release();
      session.emit(_final(2, '不要发送'));
      await pumpEventQueue();

      expect(session.cancelCount, 1);
      expect(sent, isEmpty);
      expect(coordinator.state, RekaVoiceCaptureState.idle);
    },
  );

  test('empty final and provider failure never create a Flash', () async {
    final first = _FakeSession('voice-empty');
    final second = _FakeSession('voice-error');
    final sent = <String>[];
    final coordinator = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(
        service: _QueueService([first, second]),
      ),
      sendFlash: (text, _) async => sent.add(text),
      haptic: () {},
    );

    await coordinator.begin();
    await coordinator.release();
    first.emit(_final(1, '   '));
    await pumpEventQueue();
    expect(sent, isEmpty);

    await coordinator.begin();
    second.emit(
      const VoiceInputFailure(
        code: VoiceInputErrorCode.connectionLost,
        retryable: true,
      ),
    );
    await pumpEventQueue();
    expect(sent, isEmpty);
    expect(coordinator.state, RekaVoiceCaptureState.error);
    expect(coordinator.errorCode, VoiceInputErrorCode.connectionLost);
  });

  test('a provider final received while held waits for release', () async {
    final session = _FakeSession('voice-held-final');
    final sent = <String>[];
    final coordinator = _coordinator(
      session,
      sendFlash: (text, _) async => sent.add(text),
    );

    await coordinator.begin();
    session.emit(_final(1, '先别发送'));
    await session.closeEvents();
    await pumpEventQueue();
    expect(sent, isEmpty);
    expect(coordinator.transcript, '先别发送');

    await coordinator.release();
    await pumpEventQueue();
    expect(sent, ['先别发送']);
  });

  test(
    'Flash submission failure is surfaced without an automatic retry',
    () async {
      final session = _FakeSession('voice-send-failure');
      var attempts = 0;
      final coordinator = _coordinator(
        session,
        sendFlash: (_, _) async {
          attempts += 1;
          throw StateError('backend rejected');
        },
      );

      await coordinator.begin();
      await coordinator.release();
      session.emit(_final(1, '只试一次'));
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(attempts, 1);
      expect(coordinator.state, RekaVoiceCaptureState.error);
      expect(coordinator.errorCode, VoiceInputErrorCode.serviceUnavailable);
    },
  );

  test('warns after 30 seconds and auto-finalizes at 60 seconds', () async {
    final session = _FakeSession('voice-limit');
    final sent = <String>[];
    final coordinator = _coordinator(
      session,
      maximumDuration: const Duration(milliseconds: 45),
      warningDuration: const Duration(milliseconds: 20),
      sendFlash: (text, _) async => sent.add(text),
    );

    expect(coordinator.productionMaximumDuration, const Duration(minutes: 1));
    expect(coordinator.productionWarningAt, const Duration(seconds: 30));
    await coordinator.begin();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(coordinator.isDurationWarning, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(session.stopCount, 1);
    expect(coordinator.state, RekaVoiceCaptureState.stopping);

    session.emit(_final(1, '自动发送'));
    await pumpEventQueue();
    expect(sent, ['自动发送']);
  });

  test('final timeout and close clean up without creating Flash', () async {
    final first = _FakeSession('voice-timeout');
    final second = _FakeSession('voice-close');
    final sent = <String>[];
    final coordinator = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(
        service: _QueueService([first, second]),
        finalTimeout: const Duration(milliseconds: 10),
      ),
      sendFlash: (text, _) async => sent.add(text),
      haptic: () {},
    );

    await coordinator.begin();
    await coordinator.release();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(first.cancelCount, 1);
    expect(sent, isEmpty);
    expect(coordinator.state, RekaVoiceCaptureState.error);

    await coordinator.begin();
    await coordinator.close();
    second.emit(_final(1, 'late'));
    await pumpEventQueue();
    expect(second.cancelCount, 1);
    expect(sent, isEmpty);
  });
}

RekaVoiceCaptureCoordinator _coordinator(
  _FakeSession session, {
  Future<void> Function(String, String)? sendFlash,
  void Function()? haptic,
  Duration maximumDuration = const Duration(minutes: 1),
  Duration warningDuration = const Duration(seconds: 30),
}) {
  return RekaVoiceCaptureCoordinator(
    coordinator: VoiceInputCoordinator(service: _QueueService([session])),
    sendFlash: sendFlash ?? (_, _) async {},
    haptic: haptic ?? () {},
    maximumDuration: maximumDuration,
    warningDuration: warningDuration,
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

class _QueueService implements VoiceInputServiceClient {
  _QueueService(this.sessions);

  final List<_FakeSession> sessions;
  int starts = 0;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async {
    final session = sessions[starts++];
    session.modeValue = mode;
    return session;
  }
}

class _DelayedService implements VoiceInputServiceClient {
  final Completer<_FakeSession> _completer = Completer<_FakeSession>();
  final Completer<void> started = Completer<void>();

  void complete(_FakeSession session) => _completer.complete(session);

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async {
    if (!started.isCompleted) started.complete();
    final session = await _completer.future;
    session.modeValue = mode;
    return session;
  }
}

class _FakeSession implements VoiceInputSessionHandle {
  _FakeSession(this.voiceSessionId);

  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>.broadcast();
  @override
  final String voiceSessionId;
  VoiceInputMode modeValue = VoiceInputMode.ordinary;
  int stopCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;

  void emit(VoiceInputEvent event) => _events.add(event);

  Future<void> closeEvents() => _events.close();

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => modeValue;

  @override
  Future<void> stop() async => stopCount += 1;

  @override
  Future<void> cancel() async => cancelCount += 1;

  @override
  Future<void> dispose() async => disposeCount += 1;
}
