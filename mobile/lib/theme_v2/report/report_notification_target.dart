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

String? reportExecutionIdFromLink(String link) {
  final parts = link.trim().split(':');
  if (parts.length != 3 || parts.first != 'report-start') return null;
  final id = parts[1].trim();
  final revision = parts[2];
  return id.isEmpty || !RegExp(r'^[1-9][0-9]*$').hasMatch(revision) ? null : id;
}

String? reportRunIdFromLink(String link) {
  final parts = link.trim().split(':');
  if (parts.length != 2 || parts.first != 'report-run') return null;
  final id = parts[1].trim();
  return id.isEmpty ? null : id;
}

String? reportIdFromLink(String link) {
  final parts = link.trim().split(':');
  if (parts.length != 2 || parts.first != 'report') return null;
  final id = parts[1].trim();
  return id.isEmpty ? null : id;
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

bool isReportNotificationType(String type) => switch (type) {
  'report_available' ||
  'report_plan_ready' ||
  'report_done' ||
  'report_failed' => true,
  _ => false,
};

Widget reportNotificationTargetPage(String link, {required String type}) {
  final target = resolveReportNotificationTarget(type, link);
  return switch (target?.kind) {
    ReportNotificationTargetKind.triggerRun => ReportRunPage(
      triggerExecutionId: target!.id,
    ),
    ReportNotificationTargetKind.run => ReportRunPage(runId: target!.id),
    _ => const SizedBox.shrink(),
  };
}

Future<Widget?> loadReportNotificationTargetPage(
  String type,
  String link, {
  ApiClient? api,
}) async {
  final target = resolveReportNotificationTarget(type, link);
  if (target == null) return null;
  switch (target.kind) {
    case ReportNotificationTargetKind.triggerRun:
      return ReportRunPage(triggerExecutionId: target.id);
    case ReportNotificationTargetKind.run:
      return ReportRunPage(runId: target.id);
    case ReportNotificationTargetKind.completedReport:
      final client = api ?? ApiClient();
      try {
        final response = await client.getJson('/api/reports/${target.id}');
        if (response is! Map) return null;
        final wrapped = response['report'];
        final report = wrapped is Map ? wrapped : response;
        return ReportViewerPage(
          title: report['title']?.toString() ?? '报告',
          html: report['html']?.toString() ?? '',
          reportId: target.id,
          enableLegacyEnhancements: false,
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
  String type = '',
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
