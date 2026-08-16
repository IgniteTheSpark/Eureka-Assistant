import 'package:flutter/foundation.dart';

enum RekaSignalKind { overdue, rhythmGap, report }

enum RekaSignalTargetType { asset, skill, triggerExecution, reportRun, report }

enum RekaSignalAction { open, complete, reschedule, snooze, dismiss }

enum RekaReportPhase { opportunity, planReady, reportReady }

@immutable
class RekaSignalTarget {
  const RekaSignalTarget({required this.type, required this.id});

  final RekaSignalTargetType type;
  final String id;
}

@immutable
class RekaSignal {
  const RekaSignal({
    required this.id,
    required this.naturalKey,
    required this.kind,
    required this.title,
    required this.body,
    required this.target,
    required this.actions,
    required this.deliveredAt,
    this.expiresAt,
    this.reportPhase,
    this.chainId,
    this.evidence = const {},
    this.reportRunId,
    this.reportId,
  });

  final String id;
  final String naturalKey;
  final RekaSignalKind kind;
  final String title;
  final String body;
  final RekaSignalTarget target;
  final List<RekaSignalAction> actions;
  final DateTime deliveredAt;
  final DateTime? expiresAt;
  final RekaReportPhase? reportPhase;
  final String? chainId;
  final Map<String, dynamic> evidence;
  final String? reportRunId;
  final String? reportId;

  static RekaSignal? tryParse(Map<String, dynamic> json) {
    final id = _text(json['id']);
    final naturalKey = _text(json['natural_key']);
    final title = _text(json['title']);
    final body = _text(json['body']);
    final kind = _kind(json['kind']);
    final deliveredAt = DateTime.tryParse(_text(json['delivered_at']));
    final targetJson = json['target'];
    if (id.isEmpty ||
        naturalKey.isEmpty ||
        title.isEmpty ||
        kind == null ||
        deliveredAt == null ||
        targetJson is! Map) {
      return null;
    }

    final targetType = _targetType(targetJson['type']);
    final targetId = _text(targetJson['id']);
    if (targetType == null || targetId.isEmpty) return null;

    final rawActions = json['actions'];
    final actions = rawActions is List
        ? rawActions.map(_action).whereType<RekaSignalAction>().toList()
        : <RekaSignalAction>[];
    return RekaSignal(
      id: id,
      naturalKey: naturalKey,
      kind: kind,
      title: title,
      body: body,
      target: RekaSignalTarget(type: targetType, id: targetId),
      actions: List<RekaSignalAction>.unmodifiable(actions),
      deliveredAt: deliveredAt,
      expiresAt: DateTime.tryParse(_text(json['expires_at'])),
      reportPhase: _reportPhase(json['phase']),
      chainId: _nullableText(json['chain_id']),
      evidence: json['evidence'] is Map
          ? Map<String, dynamic>.unmodifiable(
              (json['evidence'] as Map).cast<String, dynamic>(),
            )
          : const {},
      reportRunId: _nullableText(json['report_run_id']),
      reportId: _nullableText(json['report_id']),
    );
  }
}

String _text(Object? value) => value is String ? value.trim() : '';
String? _nullableText(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

RekaSignalKind? _kind(Object? value) => switch (_text(value)) {
  'overdue' => RekaSignalKind.overdue,
  'rhythm_gap' => RekaSignalKind.rhythmGap,
  'report' => RekaSignalKind.report,
  _ => null,
};

RekaSignalTargetType? _targetType(Object? value) => switch (_text(value)) {
  'asset' => RekaSignalTargetType.asset,
  'skill' => RekaSignalTargetType.skill,
  'trigger_execution' => RekaSignalTargetType.triggerExecution,
  'report_run' => RekaSignalTargetType.reportRun,
  'report' => RekaSignalTargetType.report,
  _ => null,
};

RekaSignalAction? _action(Object? value) => switch (_text(value)) {
  'open' => RekaSignalAction.open,
  'complete' => RekaSignalAction.complete,
  'reschedule' => RekaSignalAction.reschedule,
  'snooze' => RekaSignalAction.snooze,
  'dismiss' => RekaSignalAction.dismiss,
  _ => null,
};

RekaReportPhase? _reportPhase(Object? value) => switch (_text(value)) {
  'opportunity' => RekaReportPhase.opportunity,
  'plan_ready' => RekaReportPhase.planReady,
  'report_ready' => RekaReportPhase.reportReady,
  _ => null,
};
