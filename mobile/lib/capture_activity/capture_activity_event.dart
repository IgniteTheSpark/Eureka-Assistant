import 'package:flutter/foundation.dart';

enum CaptureActivitySource { ring, card, audioUpload }

enum CaptureActivityPhase {
  listening,
  receiving,
  transcribing,
  understanding,
  organizing,
  done,
  empty,
  failed,
}

String captureActivityAlias(String kind, Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? '' : '$kind:$normalized';
}

@immutable
class CaptureActivityEvent {
  const CaptureActivityEvent({
    required this.aliases,
    required this.source,
    required this.phase,
    required this.occurredAt,
    this.isRealtime = false,
    this.sessionId,
    this.inputTurnId,
    this.resultCount,
  });

  final Set<String> aliases;
  final CaptureActivitySource source;
  final CaptureActivityPhase phase;
  final DateTime occurredAt;
  final bool isRealtime;
  final String? sessionId;
  final String? inputTurnId;
  final int? resultCount;

  static CaptureActivityEvent? fromServerPayload(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final phase = _phaseFromName(
      (json['display_phase'] ?? json['status'])?.toString(),
    );
    if (phase == null) return null;
    final aliases = <String>{
      captureActivityAlias('client', json['client_task_id']),
      captureActivityAlias('recording', json['recording_id']),
      captureActivityAlias('file', json['file_id']),
      captureActivityAlias('device-capture', json['device_capture_key']),
      captureActivityAlias('device-file', json['device_file_name']),
    }..remove('');
    if (aliases.isEmpty) return null;
    final rawSource = json['source']?.toString();
    final source = switch (rawSource) {
      'ring' => CaptureActivitySource.ring,
      'card' => CaptureActivitySource.card,
      _ => CaptureActivitySource.audioUpload,
    };
    return CaptureActivityEvent(
      aliases: aliases,
      source: source,
      phase: phase,
      isRealtime: json['is_realtime'] == true,
      sessionId: _nonEmpty(json['session_id']),
      inputTurnId: _nonEmpty(json['input_turn_id']),
      resultCount: _intOrNull(json['result_count']),
      occurredAt: (now ?? DateTime.now)().toUtc(),
    );
  }

  static CaptureActivityPhase? _phaseFromName(String? value) {
    return switch (value) {
      'listening' => CaptureActivityPhase.listening,
      'accepted' || 'receiving' => CaptureActivityPhase.receiving,
      'asr_processing' || 'transcribing' => CaptureActivityPhase.transcribing,
      'asr_done' ||
      'agent_processing' ||
      'understanding' => CaptureActivityPhase.understanding,
      'organizing' => CaptureActivityPhase.organizing,
      'done' => CaptureActivityPhase.done,
      'empty' => CaptureActivityPhase.empty,
      'failed' => CaptureActivityPhase.failed,
      _ => null,
    };
  }

  static String? _nonEmpty(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

extension CaptureActivitySourceCopy on CaptureActivitySource {
  String get label => switch (this) {
    CaptureActivitySource.ring => 'UREKA 戒指',
    CaptureActivitySource.card => 'UREKA 录音卡',
    CaptureActivitySource.audioUpload => '音频上传',
  };
}

extension CaptureActivityPhaseCopy on CaptureActivityPhase {
  bool get isTerminal => switch (this) {
    CaptureActivityPhase.done ||
    CaptureActivityPhase.empty ||
    CaptureActivityPhase.failed => true,
    _ => false,
  };

  String get label => switch (this) {
    CaptureActivityPhase.listening => '正在聆听',
    CaptureActivityPhase.receiving => '正在接收',
    CaptureActivityPhase.transcribing => '正在转写',
    CaptureActivityPhase.understanding => '正在理解',
    CaptureActivityPhase.organizing => '正在整理',
    CaptureActivityPhase.done => '已整理',
    CaptureActivityPhase.empty => '没有识别到内容',
    CaptureActivityPhase.failed => '这条闪念暂未整理完成',
  };
}
