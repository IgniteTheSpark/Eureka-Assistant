import 'package:flutter/foundation.dart';

@immutable
class ReportRunSummary {
  ReportRunSummary({
    required this.id,
    required this.origin,
    required this.state,
    required this.intent,
    required this.activeStage,
    required Map<String, dynamic> pendingDecision,
    required List<Map<String, dynamic>> planOptions,
    required this.failureMessage,
    required this.reportId,
    required this.createdAt,
    required this.updatedAt,
  }) : pendingDecision = _freezeJsonMap(pendingDecision),
       planOptions = List.unmodifiable(planOptions.map(_freezeJsonMap));

  final String id;
  final String origin;
  final String state;
  final String intent;
  final String? activeStage;
  final Map<String, dynamic> pendingDecision;
  final List<Map<String, dynamic>> planOptions;
  final String? failureMessage;
  final String? reportId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get needsDecision => state == 'awaiting_selection';

  String get title {
    if (needsDecision) {
      for (final option in planOptions) {
        if (option['recommended'] == true) {
          if (_optionalString(option['title']) case final value?) return value;
        }
      }
      if (planOptions.isNotEmpty) {
        if (_optionalString(planOptions.first['title']) case final value?) {
          return value;
        }
      }
    }
    if (intent.trim().isNotEmpty) return intent.trim();
    return '报告任务';
  }

  String get summary {
    if (needsDecision) {
      final selected = planOptions.cast<Map<String, dynamic>?>().firstWhere(
        (option) => option?['recommended'] == true,
        orElse: () => planOptions.isEmpty ? null : planOptions.first,
      );
      if (_optionalString(selected?['summary']) case final value?) return value;
    }
    if (failureMessage?.trim().isNotEmpty == true) {
      return failureMessage!.trim();
    }
    return switch (state) {
      'planning' => '正在准备报告方案',
      'generating' => '正在生成报告',
      'failed' => '报告生成需要处理',
      _ => '报告任务',
    };
  }

  static ReportRunSummary? fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json['id']);
    if (id == null) return null;
    final failure = _jsonMap(json['failure']);
    return ReportRunSummary(
      id: id,
      origin: _optionalString(json['origin']) ?? '',
      state: _state(json['state']) ?? '',
      intent: _optionalString(json['intent']) ?? '',
      activeStage: _optionalString(json['active_stage']),
      pendingDecision: _jsonMap(json['pending_decision']) ?? const {},
      planOptions: _jsonMaps(json['plan_options']),
      failureMessage: _optionalString(failure?['message']),
      reportId: _optionalString(json['report_id']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

@immutable
class CompletedReportSummary {
  const CompletedReportSummary({
    required this.id,
    required this.title,
    required this.summary,
    required this.html,
    required this.baseFamily,
    required this.createdAt,
    this.palette,
    this.illustrationStatus = 'not_required',
    this.revision = 1,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String summary;
  final String html;
  final String? baseFamily;
  final String? palette;
  final DateTime? createdAt;
  final String illustrationStatus;
  final int revision;
  final DateTime? updatedAt;

  static CompletedReportSummary? fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json['id']);
    if (id == null) return null;
    final shareCard = _jsonMap(json['share_card']);
    final spec = _jsonMap(json['spec']);
    return CompletedReportSummary(
      id: id,
      title: _optionalString(json['title']) ?? '报告',
      summary: _optionalString(shareCard?['summary']) ?? '',
      html: _optionalString(json['html']) ?? '',
      baseFamily: _optionalString(json['base_family']),
      palette: _optionalString(spec?['palette']),
      createdAt: _date(json['created_at']),
      illustrationStatus:
          _optionalString(json['illustration_status']) ?? 'not_required',
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      updatedAt: _date(json['updated_at']),
    );
  }
}

@immutable
class ReportSourceFailure {
  const ReportSourceFailure({required this.source, required this.isOffline});

  final String source;
  final bool isOffline;
}

@immutable
class ReportOverview {
  ReportOverview({
    List<ReportRunSummary> activeRuns = const [],
    List<CompletedReportSummary> completedReports = const [],
    List<ReportSourceFailure> failedSources = const [],
  }) : activeRuns = List.unmodifiable(activeRuns),
       completedReports = List.unmodifiable(completedReports),
       failedSources = List.unmodifiable(failedSources);

  final List<ReportRunSummary> activeRuns;
  final List<CompletedReportSummary> completedReports;
  final List<ReportSourceFailure> failedSources;

  bool get isEmpty => activeRuns.isEmpty && completedReports.isEmpty;
}

class ReportLoadFailure implements Exception {
  const ReportLoadFailure(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}

String? _optionalString(dynamic value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

String? _requiredString(dynamic value) => _optionalString(value);

String? _state(dynamic value) => value is String ? value : null;

Map<String, dynamic>? _jsonMap(dynamic value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Map<String, dynamic>> _jsonMaps(dynamic value) {
  if (value is! List) return const [];
  return [for (final item in value) ?_jsonMap(item)];
}

Map<String, dynamic> _freezeJsonMap(Map<String, dynamic> value) =>
    Map.unmodifiable({
      for (final entry in value.entries)
        entry.key: _freezeJsonValue(entry.value),
    });

dynamic _freezeJsonValue(dynamic value) {
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key is String)
          entry.key as String: _freezeJsonValue(entry.value),
    });
  }
  if (value is List) return List.unmodifiable(value.map(_freezeJsonValue));
  return value;
}

DateTime? _date(dynamic value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toLocal();
}
