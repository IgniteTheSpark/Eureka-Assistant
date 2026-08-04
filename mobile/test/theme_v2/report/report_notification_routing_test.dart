import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/app_events.dart';
import 'package:eureka/pages/report_viewer_page.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/report/report_notification_target.dart';
import 'package:eureka/theme_v2/report/report_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('all report notification types resolve to one typed target model', () {
    expect(
      resolveReportNotificationTarget(
        'report_available',
        'report-start:execution-1:2',
      ),
      const ReportNotificationTarget(
        kind: ReportNotificationTargetKind.triggerRun,
        id: 'execution-1',
      ),
    );
    expect(
      resolveReportNotificationTarget('report_plan_ready', 'report-run:run-1'),
      const ReportNotificationTarget(
        kind: ReportNotificationTargetKind.run,
        id: 'run-1',
      ),
    );
    expect(
      resolveReportNotificationTarget('report_failed', 'report-run:run-2'),
      const ReportNotificationTarget(
        kind: ReportNotificationTargetKind.run,
        id: 'run-2',
      ),
    );
    expect(
      resolveReportNotificationTarget('report_done', 'report:report-1'),
      const ReportNotificationTarget(
        kind: ReportNotificationTargetKind.completedReport,
        id: 'report-1',
      ),
    );
  });

  test(
    'completed notification fetches the report and builds its viewer',
    () async {
      final requested = <String>[];
      final api = ApiClient(
        baseUrl: 'https://reports.test',
        enableLogging: false,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 'report-1',
                'title': '七月网球战报',
                'html': '<html>report</html>',
              }),
            ),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);

      final page = await loadReportNotificationTargetPage(
        'report_done',
        'report:report-1',
        api: api,
      );

      expect(page, isA<ReportViewerPage>());
      expect((page as ReportViewerPage).title, '七月网球战报');
      expect(page.enableLegacyEnhancements, isFalse);
      expect(requested, ['GET /api/reports/report-1']);
    },
  );

  test(
    'failed notification reopens its existing run without a fetch',
    () async {
      final page = await loadReportNotificationTargetPage(
        'report_failed',
        'report-run:run-failed',
      );

      expect(page, isA<ReportRunPage>());
      expect((page as ReportRunPage).runId, 'run-failed');
    },
  );

  test('a deleted completed report is a best-effort no-op', () async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    addTearDown(api.close);

    await expectLater(
      loadReportNotificationTargetPage(
        'report_done',
        'report:deleted-report',
        api: api,
      ),
      completion(isNull),
    );
  });

  testWidgets('live notification routing opens the same report run target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    unawaited(openNotificationTarget('report_failed', 'report-run:run-live'));
    await tester.pumpAndSettle();

    final page = tester.widget<ReportRunPage>(find.byType(ReportRunPage));
    expect(page.runId, 'run-live');
  });
}
