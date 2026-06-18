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
    show(_processingText(fileName, '准备同步'), fileName: fileName);
  }

  void syncing(String fileName) {
    show(_processingText(fileName, '同步'), fileName: fileName);
  }

  void transcoding(String fileName) {
    show(_processingText(fileName, '转码'), fileName: fileName);
  }

  void uploading(String fileName) {
    show(_processingText(fileName, '上传'), fileName: fileName);
  }

  void submitting(String fileName) {
    show(_processingText(fileName, '提交'), fileName: fileName);
  }

  void cleaning(String fileName) {
    show(_processingText(fileName, '收尾'), fileName: fileName);
  }

  /// Ring capture does on-device ASR (no file-sync workflow), so it drives the
  /// 「正在…」bubble directly to mirror the card's progressive status instead of
  /// a single static line. [action] e.g. '听写' / '整理'.
  void processing(String action, {String fileName = ''}) {
    show(_processingText(fileName, action), fileName: fileName);
  }

  void failed(String fileName, {String? message}) {
    final label = _flashLabel(fileName);
    final suffix = message == null || message.trim().isEmpty
        ? ''
        : '：${message.trim()}';
    show('Reka听到：$label处理遇到问题$suffix', isError: true, fileName: fileName);
  }

  void applyServerStatus(Map<String, dynamic> payload) {
    final s = payload['status']?.toString() ?? '';
    final fileName = payload['device_file_name']?.toString() ?? '';
    switch (s) {
      case 'accepted':
        show(_processingText(fileName, '接手'), fileName: fileName);
      case 'asr_processing':
        show(_processingText(fileName, '听写'), fileName: fileName);
      case 'asr_done':
        show(_processingText(fileName, '整理'), fileName: fileName);
      case 'processing_flash':
        show(_processingText(fileName, '整理'), fileName: fileName);
      case 'done':
        clear();
      case 'failed':
        failed(fileName, message: payload['message']?.toString());
    }
  }

  String _processingText(String fileName, String action) {
    return 'Reka听到：${_flashLabel(fileName)}正在$action';
  }

  String _flashLabel(String fileName) {
    final capturedAt = _capturedAtFromFileName(fileName);
    if (capturedAt != null) {
      return '${capturedAt.year}年${capturedAt.month}月${capturedAt.day}日 '
          '${_two(capturedAt.hour)}:${_two(capturedAt.minute)}:${_two(capturedAt.second)}的闪念';
    }
    return '这条闪念';
  }

  DateTime? _capturedAtFromFileName(String fileName) {
    final trimmed = fileName.trim();
    final match = RegExp(
      r'^F(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return null;
    final values = [
      for (var i = 1; i <= 6; i++) int.tryParse(match.group(i) ?? ''),
    ];
    if (values.any((v) => v == null)) return null;
    return DateTime(
      values[0]!,
      values[1]!,
      values[2]!,
      values[3]!,
      values[4]!,
      values[5]!,
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
