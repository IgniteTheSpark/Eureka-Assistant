import 'dart:async';

import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/reka_companion_controller.dart';
import 'package:eureka/theme_v2/capture/reka_terminal_models.dart';
import 'package:eureka/voice_input/reka_voice_capture.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local transcript preempts hardware and hands off by client alias',
    () async {
      final activity = CaptureActivityCoordinator();
      final session = _FakeSession('voice-handoff');
      late final RekaVoiceCaptureCoordinator voice;
      voice = _voice(
        session,
        sendFlash: (_, sessionId) async {
          activity.apply(
            _event(
              aliases: {'client:$sessionId', 'recording:app-recording'},
              source: CaptureActivitySource.app,
              phase: CaptureActivityPhase.understanding,
              isRealtime: true,
              sessionId: 'flash-session',
              inputTurnId: 'flash-turn',
            ),
          );
        },
      );
      final companion = RekaCompanionController(
        voice: voice,
        activities: activity,
      );
      addTearDown(() async {
        companion.dispose();
        await voice.close();
        voice.dispose();
        activity.dispose();
      });

      activity.apply(
        _event(
          aliases: {'client:hardware'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.listening,
          isRealtime: true,
        ),
      );
      await voice.begin();
      session.emit(_partial(1, '这是最新内容'));
      await pumpEventQueue();

      expect(companion.terminal!.phase, RekaTerminalPhase.listening);
      expect(companion.terminal!.transcript, '这是最新内容');
      expect(companion.terminal!.source, CaptureActivitySource.app);
      expect(companion.terminal!.queuedCount, 1);

      await voice.release();
      session.emit(_final(2, '这是最新内容'));
      await pumpEventQueue();

      expect(companion.terminal!.phase, RekaTerminalPhase.understanding);
      expect(companion.terminal!.aliases, contains('client:voice-handoff'));
      expect(companion.openableActivity!.inputTurnId, 'flash-turn');
    },
  );

  test(
    'dismissed task stays hidden through terminal phase and new task appears',
    () async {
      final activity = CaptureActivityCoordinator();
      final voice = _voice(_FakeSession('unused'));
      final companion = RekaCompanionController(
        voice: voice,
        activities: activity,
      );
      addTearDown(() async {
        companion.dispose();
        await voice.close();
        voice.dispose();
        activity.dispose();
      });

      activity.apply(
        _event(
          aliases: {'client:first'},
          source: CaptureActivitySource.card,
          phase: CaptureActivityPhase.understanding,
          isRealtime: true,
        ),
      );
      expect(companion.terminal, isNotNull);

      await companion.dismissTerminal();
      activity.apply(
        _event(
          aliases: {'client:first'},
          source: CaptureActivitySource.card,
          phase: CaptureActivityPhase.done,
          isRealtime: true,
          resultCount: 2,
        ),
      );
      expect(companion.terminal, isNull);

      activity.apply(
        _event(
          aliases: {'client:second'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.receiving,
        ),
      );
      expect(companion.terminal!.aliases, contains('client:second'));
    },
  );

  test('hardware model contains real phase data but no transcript', () async {
    final activity = CaptureActivityCoordinator();
    final voice = _voice(_FakeSession('unused'));
    final companion = RekaCompanionController(
      voice: voice,
      activities: activity,
    );
    addTearDown(() async {
      companion.dispose();
      await voice.close();
      voice.dispose();
      activity.dispose();
    });

    activity.apply(
      _event(
        aliases: {'recording:ring-1'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.transcribing,
      ),
    );

    expect(companion.terminal!.phase, RekaTerminalPhase.transcribing);
    expect(companion.terminal!.transcript, isEmpty);
    expect(companion.terminal!.sourceCommand, 'REKA://RING');
    expect(companion.terminal!.statusLabel, '正在转写');
  });

  test('keeps the coordinator active realtime activity stable', () async {
    final activity = CaptureActivityCoordinator();
    final voice = _voice(_FakeSession('unused'));
    final companion = RekaCompanionController(
      voice: voice,
      activities: activity,
    );
    addTearDown(() async {
      companion.dispose();
      await voice.close();
      voice.dispose();
      activity.dispose();
    });

    activity.apply(
      _event(
        aliases: {'client:selected'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.listening,
        isRealtime: true,
        occurredAt: DateTime.utc(2026, 8, 21, 10),
      ),
    );
    activity.apply(
      _event(
        aliases: {'client:later-arrival'},
        source: CaptureActivitySource.card,
        phase: CaptureActivityPhase.listening,
        isRealtime: true,
        occurredAt: DateTime.utc(2026, 8, 21, 9),
      ),
    );

    expect(companion.terminal!.aliases, contains('client:selected'));
    expect(companion.terminal!.queuedCount, 1);
  });

  test('local empty and failure use three and four second dwell', () async {
    final scheduled = <Duration, VoidCallback>{};
    final first = _FakeSession('voice-empty');
    final second = _FakeSession('voice-failed');
    final activity = CaptureActivityCoordinator();
    final voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(
        service: _QueueService([first, second]),
      ),
      sendFlash: (_, _) async {},
      haptic: () {},
    );
    final companion = RekaCompanionController(
      voice: voice,
      activities: activity,
      schedule: (duration, callback) => scheduled[duration] = callback,
    );
    addTearDown(() async {
      companion.dispose();
      await voice.close();
      voice.dispose();
      activity.dispose();
    });

    await voice.begin();
    await voice.release();
    first.emit(_final(1, '   '));
    await pumpEventQueue();
    expect(companion.terminal!.phase, RekaTerminalPhase.empty);
    expect(scheduled, contains(const Duration(seconds: 3)));
    scheduled[const Duration(seconds: 3)]!();
    expect(companion.terminal, isNull);

    await voice.begin();
    second.emit(
      const VoiceInputFailure(
        code: VoiceInputErrorCode.connectionLost,
        retryable: true,
      ),
    );
    await pumpEventQueue();
    expect(companion.terminal!.phase, RekaTerminalPhase.failed);
    expect(scheduled, contains(const Duration(seconds: 4)));
    scheduled[const Duration(seconds: 4)]!();
    expect(companion.terminal, isNull);
  });

  test(
    'closing the terminal while listening cancels microphone ownership',
    () async {
      final session = _FakeSession('voice-close');
      final activity = CaptureActivityCoordinator();
      final voice = _voice(session);
      final companion = RekaCompanionController(
        voice: voice,
        activities: activity,
      );
      addTearDown(() async {
        companion.dispose();
        await voice.close();
        voice.dispose();
        activity.dispose();
      });

      await voice.begin();
      expect(companion.terminal!.phase, RekaTerminalPhase.listening);
      await companion.dismissTerminal();

      expect(session.cancelCount, 1);
      expect(voice.state, RekaVoiceCaptureState.idle);
      expect(companion.terminal, isNull);
    },
  );
}

CaptureActivityEvent _event({
  required Set<String> aliases,
  required CaptureActivitySource source,
  required CaptureActivityPhase phase,
  bool isRealtime = false,
  String? sessionId,
  String? inputTurnId,
  int? resultCount,
  DateTime? occurredAt,
}) => CaptureActivityEvent(
  aliases: aliases,
  source: source,
  phase: phase,
  occurredAt: occurredAt ?? DateTime.utc(2026, 8, 21),
  isRealtime: isRealtime,
  sessionId: sessionId,
  inputTurnId: inputTurnId,
  resultCount: resultCount,
);

RekaVoiceCaptureCoordinator _voice(
  _FakeSession session, {
  Future<void> Function(String, String)? sendFlash,
}) => RekaVoiceCaptureCoordinator(
  coordinator: VoiceInputCoordinator(service: _QueueService([session])),
  sendFlash: sendFlash ?? (_, _) async {},
  haptic: () {},
);

VoiceTranscriptEvent _partial(int sequence, String text) =>
    VoiceTranscriptEvent(
      kind: VoiceTranscriptKind.partial,
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

class _FakeSession implements VoiceInputSessionHandle {
  _FakeSession(this.voiceSessionId);

  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>.broadcast();
  @override
  final String voiceSessionId;
  VoiceInputMode modeValue = VoiceInputMode.ordinary;
  int cancelCount = 0;

  void emit(VoiceInputEvent event) => _events.add(event);

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => modeValue;

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async => cancelCount += 1;

  @override
  Future<void> dispose() async {}
}
