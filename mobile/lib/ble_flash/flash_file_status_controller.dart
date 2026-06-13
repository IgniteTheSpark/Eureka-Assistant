import 'package:flutter/foundation.dart';

class FlashFileStatus {
  const FlashFileStatus({
    this.visible = false,
    this.text = '',
    this.isError = false,
    this.fileName = '',
  });

  final bool visible;
  final String text;
  final bool isError;
  final String fileName;
}

class FlashFileStatusController {
  FlashFileStatusController._();
  static final FlashFileStatusController instance =
      FlashFileStatusController._();

  final ValueNotifier<FlashFileStatus> status = ValueNotifier<FlashFileStatus>(
    const FlashFileStatus(),
  );

  void show(String text, {bool isError = false, String? fileName}) {
    status.value = FlashFileStatus(
      visible: text.isNotEmpty,
      text: text,
      isError: isError,
      fileName: fileName ?? '',
    );
  }

  void clear() {
    status.value = const FlashFileStatus();
  }

  void heard(String fileName) {
    show('Reka已听到-${_fileLabel(fileName)}已进入队列', fileName: fileName);
  }

  void syncing(String fileName) {
    show('Reka已听到-${_fileLabel(fileName)}正在同步', fileName: fileName);
  }

  void transcoding(String fileName) {
    show('Reka正在转码-${_fileLabel(fileName)}', fileName: fileName);
  }

  void uploading(String fileName) {
    show('Reka正在上传-${_fileLabel(fileName)}', fileName: fileName);
  }

  void submitting(String fileName) {
    show('Reka正在提交-${_fileLabel(fileName)}', fileName: fileName);
  }

  void cleaning(String fileName) {
    show('Reka正在收尾-${_fileLabel(fileName)}', fileName: fileName);
  }

  void failed(String fileName, {String? message}) {
    final label = _fileLabel(fileName);
    final suffix = message == null || message.trim().isEmpty
        ? ''
        : '：${message.trim()}';
    show('Reka处理-$label遇到问题$suffix', isError: true, fileName: fileName);
  }

  void applyServerStatus(Map<String, dynamic> payload) {
    final s = payload['status']?.toString() ?? '';
    final fileName = payload['device_file_name']?.toString() ?? '';
    switch (s) {
      case 'accepted':
        show('Reka已接手-${_fileLabel(fileName)}', fileName: fileName);
      case 'asr_processing':
        show('Reka正在听写-${_fileLabel(fileName)}', fileName: fileName);
      case 'asr_done':
        show('Reka听写好了-${_fileLabel(fileName)}', fileName: fileName);
      case 'processing_flash':
        show('Reka正在整理-${_fileLabel(fileName)}', fileName: fileName);
      case 'done':
        clear();
      case 'failed':
        failed(fileName, message: payload['message']?.toString());
    }
  }

  String _fileLabel(String fileName) {
    final trimmed = fileName.trim();
    return trimmed.isEmpty ? '这条闪念' : '$trimmed文件';
  }
}
