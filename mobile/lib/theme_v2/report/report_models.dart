import 'package:flutter/foundation.dart';

@immutable
class ReportRunSummary {
  const ReportRunSummary({
    required this.id,
    required this.origin,
    required this.state,
    required this.intent,
    required this.activeStage,
    required this.pendingDecision,
    required this.planOptions,
    required this.failureMessage,
    required this.reportId,
    required this.createdAt,
    required this.updatedAt,
  });

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
          final value = option['title']?.toString().trim() ?? '';
          if (value.isNotEmpty) return value;
        }
      }
      if (planOptions.isNotEmpty) {
        final value = planOptions.first['title']?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
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
      final value = selected?['summary']?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
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
    final failure = (json['failure'] as Map?)?.cast<String, dynamic>();
    return ReportRunSummary(
      id: id,
      origin: json['origin']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      intent: json['intent']?.toString() ?? '',
      activeStage: _optionalString(json['active_stage']),
      pendingDecision:
          (json['pending_decision'] as Map?)?.cast<String, dynamic>() ??
          const {},
      planOptions: (json['plan_options'] as List? ?? const [])
          .whereType<Map>()
          .map((option) => option.cast<String, dynamic>())
          .toList(growable: false),
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
  });

  final String id;
  final String title;
  final String summary;
  final String html;
  final String? baseFamily;
  final DateTime? createdAt;

  static CompletedReportSummary? fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json['id']);
    if (id == null) return null;
    final shareCard = (json['share_card'] as Map?)?.cast<String, dynamic>();
    return CompletedReportSummary(
      id: id,
      title: _optionalString(json['title']) ?? '报告',
      summary: _optionalString(shareCard?['summary']) ?? '',
      html: json['html']?.toString() ?? '',
      baseFamily: _optionalString(json['base_family']),
      createdAt: _date(json['created_at']),
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

DateTime? _date(dynamic value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toLocal();
}
