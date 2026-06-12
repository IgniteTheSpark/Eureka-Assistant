import 'package:flutter/foundation.dart';

class FlashFileStatus {
  const FlashFileStatus({
    this.visible = false,
    this.text = '',
    this.isError = false,
  });

  final bool visible;
  final String text;
  final bool isError;
}

class FlashFileStatusController {
  FlashFileStatusController._();
  static final FlashFileStatusController instance =
      FlashFileStatusController._();

  final ValueNotifier<FlashFileStatus> status = ValueNotifier<FlashFileStatus>(
    const FlashFileStatus(),
  );

  void show(String text, {bool isError = false}) {
    status.value = FlashFileStatus(
      visible: text.isNotEmpty,
      text: text,
      isError: isError,
    );
  }

  void clear() {
    status.value = const FlashFileStatus();
  }

  void applyServerStatus(Map<String, dynamic> payload) {
    final s = payload['status']?.toString() ?? '';
    switch (s) {
      case 'accepted':
        show('闪念任务已提交');
      case 'asr_processing':
        show('正在识别内容...');
      case 'asr_done':
        show('识别完成，正在整理...');
      case 'processing_flash':
        show('正在整理到资产库...');
      case 'done':
        show('已整理到资产库');
      case 'failed':
        show(payload['message']?.toString() ?? '闪念处理失败', isError: true);
    }
  }
}
