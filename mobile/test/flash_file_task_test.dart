import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/ble_flash/flash_file_workflow.dart';
import 'package:eureka/ble_flash/flash_file_status_controller.dart';
import 'package:eureka/ble_flash/flash_file_task.dart';
import 'package:eureka/capture_activity/capture_activity_event.dart';

void main() {
  test('isFlashFileName only accepts uppercase F opus files', () {
    expect(isFlashFileName('F20260612-101500.opus'), isTrue);
    expect(isFlashFileName('F20260612-101500.OPUS'), isTrue);
    expect(isFlashFileName('f20260612-101500.opus'), isFalse);
    expect(isFlashFileName('R20260612-101500.opus'), isFalse);
    expect(isFlashFileName('F20260612-101500.mp3'), isFalse);
    expect(isFlashFileName('notes.opus'), isFalse);
  });

  test('flash filename preserves original local capture second', () {
    final value = captureDateTimeFromFlashFileName('F20260805-231407.opus');

    expect(value, DateTime(2026, 8, 5, 23, 14, 7));
    expect(
      captureEpochSecondsFromFlashFileName('F20260805-231407.opus'),
      value!.millisecondsSinceEpoch ~/ 1000,
    );
    expect(captureDateTimeFromFlashFileName('F20260230-231407.opus'), isNull);
    expect(captureEpochSecondsFromFlashFileName('invalid.opus'), isNull);
  });

  test('FlashFileTask persists ASR workflow metadata', () {
    final retryAt = DateTime.utc(2026, 6, 12, 10, 15);
    final task = FlashFileTask(
      id: 'task-id',
      key: 'SN1:F1.opus',
      deviceSn: 'SN1',
      fileName: 'F1.opus',
      source: FlashFileSource.realtime,
      stage: FlashFileStage.waitingServerAsr,
      updatedAt: DateTime.utc(2026, 6, 12, 10),
      createTime: 1781230500,
      endTime: 1781230520,
      crc: 1234,
      deviceSizeBytes: 34567,
      localOpusPath: '/tmp/F1.opus',
      localAudioPath: '/tmp/F1.mp3',
      localMp3Path: '/tmp/F1.mp3',
      asrMode: FlashFileAsrMode.async,
      audioFormat: 'mp3',
      localAudioSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      localAudioSizeBytes: 12345,
      clientAsrText: '你好世界',
      clientAsrSegments: const [
        {'text': '你好世界', 'start_ms': 0, 'end_ms': 1000},
      ],
      clientAsrRawResponse: const {
        'code': 0,
        'data': {'text': '你好世界'},
      },
      clientAsrStatus: 'completed',
      clientAsrError: '',
      clientAsrMessage: '',
      mp3Sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      mp3SizeBytes: 12345,
      s3Key: '2026/06/12/F1.mp3',
      s3UploadHeaders: const {'Content-Type': 'audio/mpeg'},
      s3ExpiresIn: 3600,
      tencentAsrTaskId: '123',
      eurekaRecordingId: 'recording-id',
      attemptsByStage: const {'converted': 2},
      retryAfter: retryAt,
      deviceDeletePending: true,
      lastError: 'network',
    );

    final restored = FlashFileTask.fromJson(task.toJson());

    expect(restored.key, task.key);
    expect(restored.source, FlashFileSource.realtime);
    expect(restored.stage, FlashFileStage.waitingServerAsr);
    expect(restored.asrMode, FlashFileAsrMode.async);
    expect(restored.audioFormat, 'mp3');
    expect(restored.localAudioPath, '/tmp/F1.mp3');
    expect(
      restored.localAudioSha256,
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(restored.localAudioSizeBytes, 12345);
    expect(restored.clientAsrText, '你好世界');
    expect(restored.clientAsrSegments, [
      {'text': '你好世界', 'start_ms': 0, 'end_ms': 1000},
    ]);
    expect(restored.clientAsrRawResponse, {
      'code': 0,
      'data': {'text': '你好世界'},
    });
    expect(restored.clientAsrStatus, 'completed');
    expect(restored.clientAsrError, '');
    expect(restored.clientAsrMessage, '');
    expect(restored.s3UploadHeaders, {'Content-Type': 'audio/mpeg'});
    expect(restored.attemptsByStage, {'converted': 2});
    expect(restored.retryAfter, retryAt);
    expect(restored.deviceDeletePending, isTrue);
  });

  test('FlashFileStatusController describes flash files by capture time', () {
    final controller = FlashFileStatusController.instance;
    controller.syncing('F20260613-120523.opus');

    expect(controller.status.value.text, 'Reka听到：2026年6月13日 12:05:23的闪念正在同步');
    expect(controller.status.value.text, isNot(contains('F20260613')));
    expect(controller.status.value.text, isNot(contains('.opus')));

    controller.clear();
  });

  test('FlashFileWorkflow task storage is scoped by user id', () {
    expect(
      FlashFileWorkflow.debugPrefsKeyForUser('user-a'),
      'flash_file_tasks_v1:user-a',
    );
    expect(
      FlashFileWorkflow.debugPrefsKeyForUser('user-b'),
      'flash_file_tasks_v1:user-b',
    );
    expect(
      FlashFileWorkflow.debugPrefsKeyForUser(' user-a '),
      'flash_file_tasks_v1:user-a',
    );
  });

  test('card workflow task exposes stable aliases and normalized phase', () {
    final task = FlashFileTask(
      id: 'client-task-1',
      key: 'SN1:F20260807-090000.opus',
      deviceSn: 'SN1',
      fileName: 'F20260807-090000.opus',
      source: FlashFileSource.realtime,
      stage: FlashFileStage.waitingServerAsr,
      updatedAt: DateTime.utc(2026, 8, 7, 9),
      createTime: DateTime.utc(2026, 8, 7, 9).millisecondsSinceEpoch ~/ 1000,
      eurekaRecordingId: 'recording-1',
    );

    final activity = captureActivityForFlashFileTask(task);

    expect(activity.source, CaptureActivitySource.card);
    expect(activity.phase, CaptureActivityPhase.transcribing);
    expect(activity.isRealtime, isTrue);
    expect(
      activity.aliases,
      containsAll(<String>{
        'local:SN1:F20260807-090000.opus',
        'client:client-task-1',
        'recording:recording-1',
        'device-file:F20260807-090000.opus',
      }),
    );
  });
}
