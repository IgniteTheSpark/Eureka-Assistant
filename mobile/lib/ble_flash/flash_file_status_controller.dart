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
        clear();
      case 'asr_processing':
        clear();
      case 'asr_done':
        clear();
      case 'processing_flash':
        clear();
      case 'done':
        clear();
      case 'failed':
        show(payload['message']?.toString() ?? '闪念处理失败', isError: true);
    }
  }
}
