import 'package:flutter/foundation.dart';

import '../../capture_activity/capture_activity_event.dart';

@immutable
class CaptureActivityItem {
  const CaptureActivityItem({
    required this.aliases,
    required this.source,
    required this.phase,
    required this.isRealtime,
    required this.occurredAt,
    DateTime? phaseStartedAt,
    this.sessionId,
    this.inputTurnId,
    this.resultCount,
  }) : phaseStartedAt = phaseStartedAt ?? occurredAt;

  final Set<String> aliases;
  final CaptureActivitySource source;
  final CaptureActivityPhase phase;
  final bool isRealtime;
  final DateTime occurredAt;
  final DateTime phaseStartedAt;
  final String? sessionId;
  final String? inputTurnId;
  final int? resultCount;

  bool get canOpenSession =>
      (sessionId?.isNotEmpty ?? false) && (inputTurnId?.isNotEmpty ?? false);

  String? aliasValue(String kind) {
    final prefix = '$kind:';
    for (final alias in aliases) {
      if (alias.startsWith(prefix) && alias.length > prefix.length) {
        return alias.substring(prefix.length);
      }
    }
    return null;
  }

  String? get recordingId => aliasValue('recording');

  String get statusLabel {
    if (phase == CaptureActivityPhase.done && resultCount != null) {
      return '已整理 · $resultCount 项';
    }
    if (phase == CaptureActivityPhase.receiving &&
        !isRealtime &&
        source != CaptureActivitySource.audioUpload) {
      return '正在同步离线闪念';
    }
    return phase.label;
  }
}

@immutable
class CaptureActivitySnapshot {
  const CaptureActivitySnapshot({
    this.active,
    this.queuedCount = 0,
    this.activities = const [],
  });

  final CaptureActivityItem? active;
  final int queuedCount;
  final List<CaptureActivityItem> activities;

  bool get isActive => active != null;
  bool get canOpenSession => active?.canOpenSession ?? false;
}
