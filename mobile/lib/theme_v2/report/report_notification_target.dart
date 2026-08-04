import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pages/report_viewer_page.dart';
import 'report_run_page.dart';

enum ReportNotificationTargetKind { triggerRun, run, completedReport }

@immutable
class ReportNotificationTarget {
  const ReportNotificationTarget({required this.kind, required this.id});

  final ReportNotificationTargetKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ReportNotificationTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

final RegExp _safeReportLinkId = RegExp(r'^[A-Za-z0-9._~-]+$');

String? _validatedReportLinkId(String value) =>
    _safeReportLinkId.hasMatch(value) ? value : null;

String? reportExecutionIdFromLink(String link) {
  final parts = link.split(':');
  if (parts.length != 3 || parts.first != 'report-start') return null;
  final id = _validatedReportLinkId(parts[1]);
  final revision = parts[2];
  return id == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(revision) ? null : id;
}

String? reportRunIdFromLink(String link) {
  final parts = link.split(':');
  if (parts.length != 2 || parts.first != 'report-run') return null;
  return _validatedReportLinkId(parts[1]);
}

String? reportIdFromLink(String link) {
  final parts = link.split(':');
  if (parts.length != 2 || parts.first != 'report') return null;
  return _validatedReportLinkId(parts[1]);
}

ReportNotificationTarget? resolveReportNotificationTarget(
  String type,
  String link,
) {
  switch (type) {
    case 'report_available':
      final id = reportExecutionIdFromLink(link);
      return id == null
          ? null
          : ReportNotificationTarget(
              kind: ReportNotificationTargetKind.triggerRun,
              id: id,
            );
    case 'report_plan_ready':
    case 'report_failed':
      final id = reportRunIdFromLink(link);
      return id == null
          ? null
          : ReportNotificationTarget(
              kind: ReportNotificationTargetKind.run,
              id: id,
            );
    case 'report_done':
      final id = reportIdFromLink(link);
      return id == null
          ? null
          : ReportNotificationTarget(
              kind: ReportNotificationTargetKind.completedReport,
              id: id,
            );
    default:
      return null;
  }
}

ReportNotificationTarget? _resolveLegacyReportNotificationTarget(String link) {
  final executionId = reportExecutionIdFromLink(link);
  if (executionId != null) {
    return ReportNotificationTarget(
      kind: ReportNotificationTargetKind.triggerRun,
      id: executionId,
    );
  }
  final runId = reportRunIdFromLink(link);
  return runId == null
      ? null
      : ReportNotificationTarget(
          kind: ReportNotificationTargetKind.run,
          id: runId,
        );
}

ReportNotificationTarget? _resolveReportNotificationTarget(
  String? type,
  String link,
) => type == null
    ? _resolveLegacyReportNotificationTarget(link)
    : resolveReportNotificationTarget(type, link);

bool isReportNotificationType(String type) => switch (type) {
  'report_available' ||
  'report_plan_ready' ||
  'report_done' ||
  'report_failed' => true,
  _ => false,
};

Widget reportNotificationTargetPage(String link, {String? type}) {
  final target = _resolveReportNotificationTarget(type, link);
  return switch (target?.kind) {
    ReportNotificationTargetKind.triggerRun => ReportRunPage(
      triggerExecutionId: target!.id,
    ),
    ReportNotificationTargetKind.run => ReportRunPage(runId: target!.id),
    _ => const SizedBox.shrink(),
  };
}

ReportViewerPage buildThemeV2ReportViewerPage(
  Map<dynamic, dynamic> response, {
  required String reportId,
  ApiClient? api,
}) {
  final wrapped = response['report'];
  final report = wrapped is Map ? wrapped : response;
  return ReportViewerPage(
    title: report['title']?.toString() ?? '报告',
    html: report['html']?.toString() ?? '',
    reportId: reportId,
    enableLegacyEnhancements: false,
    enableThemeV2Actions: true,
    themeV2Palette: (report['spec'] as Map?)?['palette']?.toString(),
    api: api,
  );
}

Future<Widget?> loadReportNotificationTargetPage(
  String? type,
  String link, {
  ApiClient? api,
}) async {
  final target = _resolveReportNotificationTarget(type, link);
  if (target == null) return null;
  switch (target.kind) {
    case ReportNotificationTargetKind.triggerRun:
      return ReportRunPage(triggerExecutionId: target.id, api: api);
    case ReportNotificationTargetKind.run:
      return ReportRunPage(runId: target.id, api: api);
    case ReportNotificationTargetKind.completedReport:
      final client = api ?? ApiClient();
      try {
        final response = await client.getJson('/api/reports/${target.id}');
        if (response is! Map) return null;
        return buildThemeV2ReportViewerPage(
          response,
          reportId: target.id,
          api: api,
        );
      } catch (_) {
        return null;
      } finally {
        if (api == null) client.close();
      }
  }
}

Future<void> dismissReportAvailableNotification(
  ApiClient api, {
  required String notificationId,
  required String link,
}) async {
  final executionId = reportExecutionIdFromLink(link);
  if (executionId == null) {
    throw const FormatException('Invalid report notification link');
  }
  await api.postJson(
    '/api/trigger-executions/$executionId/dismiss',
    const <String, dynamic>{},
  );
  await api.deleteJson('/api/notifications/$notificationId');
}

Future<void> openReportNotificationTarget(
  BuildContext context,
  String link, {
  String? type,
  ApiClient? api,
}) async {
  try {
    final page = await loadReportNotificationTargetPage(type, link, api: api);
    if (page == null || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  } catch (_) {
    // Best effort: the report or run may have been removed while opening it.
  }
}
