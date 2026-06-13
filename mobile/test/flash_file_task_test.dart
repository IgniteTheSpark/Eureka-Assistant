import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/ble_flash/flash_file_status_controller.dart';
import 'package:eureka/ble_flash/flash_file_task.dart';

void main() {
  test('isFlashFileName only accepts uppercase F opus files', () {
    expect(isFlashFileName('F20260612-101500.opus'), isTrue);
    expect(isFlashFileName('F20260612-101500.OPUS'), isTrue);
    expect(isFlashFileName('f20260612-101500.opus'), isFalse);
    expect(isFlashFileName('R20260612-101500.opus'), isFalse);
    expect(isFlashFileName('F20260612-101500.mp3'), isFalse);
    expect(isFlashFileName('notes.opus'), isFalse);
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
      localMp3Path: '/tmp/F1.mp3',
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
}
