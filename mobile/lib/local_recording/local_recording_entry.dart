import 'dart:async';

import 'local_recording_service.dart';

/// Global entry point for 本地录音 → 后端 ASR 转写 → 闪念提交.
///
/// UI 通过 [localRecording] 调用 startRecording / stopRecording /
/// transcribeAndSubmit,监听 [LocalRecordingService.status] 获取进度。
/// 与 RingCaptureService 的全局入口模式保持一致。
LocalRecordingService? _instance;

LocalRecordingService get localRecording =>
    _instance ??= LocalRecordingService();

void disposeLocalRecording() {
  final current = _instance;
  _instance = null;
  if (current != null) {
    unawaited(current.dispose());
  }
}

