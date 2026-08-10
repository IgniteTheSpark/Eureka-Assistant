import 'package:eureka/ring/ring_capture_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ring device key is stable across reconnect attempts', () {
    final first = ringDeviceCaptureKey(
      deviceId: 'AA:BB',
      fileName: 'R0001.bin',
      fileId: const [1, 2, 3],
      sizeBytes: 240000,
    );
    final second = ringDeviceCaptureKey(
      deviceId: ' aa:bb ',
      fileName: ' R0001.bin ',
      fileId: const [1, 2, 3],
      sizeBytes: 240000,
    );

    expect(second, first);
    expect(first, startsWith('ring:'));
  });

  test('task JSON round trip retains recovery metadata in UTC', () {
    final task = _ringTask(
      stage: RingCaptureStage.downloaded,
      endedAt: DateTime.parse('2026-08-11T08:30:12+08:00'),
      fileName: 'R0001.bin',
      fileId: const [1, 2, 3],
      deviceSizeBytes: 240000,
      deviceCaptureKey: 'ring:stable',
      localWavPath: '/tmp/ring.wav',
      localAudioSha256: List.filled(64, 'a').join(),
      localAudioSizeBytes: 480000,
      transcript: '明天下午去跑步',
      recordingId: 'recording-1',
      sessionId: 'session-1',
      inputTurnId: 'turn-1',
      deletePending: true,
      lastErrorCode: 'network_timeout',
    );

    final restored = RingCaptureTask.fromJson(task.toJson());

    expect(restored.id, task.id);
    expect(restored.stage, RingCaptureStage.downloaded);
    expect(restored.startedAt.isUtc, isTrue);
    expect(restored.endedAt, DateTime.utc(2026, 8, 11, 0, 30, 12));
    expect(restored.fileId, [1, 2, 3]);
    expect(restored.localWavPath, '/tmp/ring.wav');
    expect(restored.transcript, '明天下午去跑步');
    expect(restored.deletePending, isTrue);
    expect(restored.lastErrorCode, 'network_timeout');
  });

  test('copyWith can explicitly clear nullable recovery fields', () {
    final failed = _ringTask(
      stage: RingCaptureStage.failed,
      transcript: '已有转写',
      lastErrorCode: 'network_timeout',
    );

    final retried = failed.copyWith(
      stage: RingCaptureStage.submitting,
      transcript: null,
      lastErrorCode: null,
    );

    expect(retried.stage, RingCaptureStage.submitting);
    expect(retried.transcript, isNull);
    expect(retried.lastErrorCode, isNull);
  });

  test('fromJson rejects malformed durable identity and stage', () {
    final valid = _ringTask().toJson();

    expect(
      () => RingCaptureTask.fromJson({...valid, 'id': '  '}),
      throwsFormatException,
    );
    expect(
      () => RingCaptureTask.fromJson({...valid, 'stage': 'unknown'}),
      throwsFormatException,
    );
    expect(
      () => RingCaptureTask.fromJson({...valid, 'startedAt': 'not-a-date'}),
      throwsFormatException,
    );
  });
}

RingCaptureTask _ringTask({
  RingCaptureStage stage = RingCaptureStage.recording,
  DateTime? endedAt,
  String? fileName,
  List<int> fileId = const [],
  int? deviceSizeBytes,
  String? deviceCaptureKey,
  String? localWavPath,
  String? localAudioSha256,
  int? localAudioSizeBytes,
  String? transcript,
  String? recordingId,
  String? sessionId,
  String? inputTurnId,
  bool deletePending = false,
  String? lastErrorCode,
}) {
  return RingCaptureTask(
    id: 'task-1',
    userId: 'user-a',
    deviceId: 'AA:BB',
    stage: stage,
    startedAt: DateTime.parse('2026-08-11T08:30:00+08:00'),
    updatedAt: DateTime.parse('2026-08-11T08:31:00+08:00'),
    endedAt: endedAt,
    fileName: fileName,
    fileId: fileId,
    deviceSizeBytes: deviceSizeBytes,
    deviceCaptureKey: deviceCaptureKey,
    localWavPath: localWavPath,
    localAudioSha256: localAudioSha256,
    localAudioSizeBytes: localAudioSizeBytes,
    transcript: transcript,
    recordingId: recordingId,
    sessionId: sessionId,
    inputTurnId: inputTurnId,
    deletePending: deletePending,
    lastErrorCode: lastErrorCode,
  );
}
