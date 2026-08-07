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
    this.sessionId,
    this.inputTurnId,
    this.resultCount,
  });

  final Set<String> aliases;
  final CaptureActivitySource source;
  final CaptureActivityPhase phase;
  final bool isRealtime;
  final DateTime occurredAt;
  final String? sessionId;
  final String? inputTurnId;
  final int? resultCount;

  bool get canOpenSession =>
      (sessionId?.isNotEmpty ?? false) && (inputTurnId?.isNotEmpty ?? false);

  String get statusLabel {
    if (phase == CaptureActivityPhase.done && resultCount != null) {
      return '已整理 · $resultCount 项';
    }
    return phase.label;
  }
}

@immutable
class CaptureActivitySnapshot {
  const CaptureActivitySnapshot({this.active, this.queuedCount = 0});

  final CaptureActivityItem? active;
  final int queuedCount;

  bool get isActive => active != null;
  bool get canOpenSession => active?.canOpenSession ?? false;
}
