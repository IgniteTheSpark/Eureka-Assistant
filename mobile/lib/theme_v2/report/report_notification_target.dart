import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import 'report_run_page.dart';

String? reportExecutionIdFromLink(String link) {
  final parts = link.trim().split(':');
  if (parts.length != 3 || parts.first != 'report-start') return null;
  final id = parts[1].trim();
  final revision = int.tryParse(parts[2]);
  return id.isEmpty || revision == null ? null : id;
}

String? reportRunIdFromLink(String link) {
  final parts = link.trim().split(':');
  if (parts.length != 2 || parts.first != 'report-run') return null;
  final id = parts[1].trim();
  return id.isEmpty ? null : id;
}

Widget reportNotificationTargetPage(String link) {
  final executionId = reportExecutionIdFromLink(link);
  if (executionId != null) {
    return ReportRunPage(triggerExecutionId: executionId);
  }
  final runId = reportRunIdFromLink(link);
  if (runId != null) return ReportRunPage(runId: runId);
  return const SizedBox.shrink();
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
  String link,
) async {
  final executionId = reportExecutionIdFromLink(link);
  final runId = reportRunIdFromLink(link);
  if (executionId == null && runId == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => executionId != null
          ? ReportRunPage(triggerExecutionId: executionId)
          : ReportRunPage(runId: runId),
    ),
  );
}
