import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/app_events.dart';
import 'package:eureka/pages/notifications_page.dart';
import 'package:eureka/pages/report_viewer_page.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
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
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient(
        (_) async => _json({
          'id': 'run-live',
          'state': 'failed',
          'error': 'generation failed',
        }),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    unawaited(
      openNotificationTarget(
        'report_failed',
        'report-run:run-live',
        reportApi: api,
      ),
    );
    await tester.pumpAndSettle();

    final page = tester.widget<ReportRunPage>(find.byType(ReportRunPage));
    expect(page.runId, 'run-live');
  });

  testWidgets('legacy opener resolves a report-run link when type is omitted', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient(
        (_) async => _json({
          'id': 'run-legacy',
          'state': 'failed',
          'error': 'generation failed',
        }),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final opened = openReportNotificationTarget(
      navigatorKey.currentContext!,
      'report-run:run-legacy',
      api: api,
    );
    await tester.pumpAndSettle();

    final page = tester.widget<ReportRunPage>(find.byType(ReportRunPage));
    expect(page.runId, 'run-legacy');
    navigatorKey.currentState!.pop();
    await opened;
  });

  testWidgets('notification history opens a typed report target', (
    tester,
  ) async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add('${request.method} ${request.url.path}');
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/notifications':
            return _json({
              'notifications': [
                _notification(
                  id: 'history-run-notification',
                  type: 'report_failed',
                  title: '报告生成失败',
                  link: 'report-run:run-history',
                ),
              ],
              'unread': 1,
            });
          case 'POST /api/notifications/history-run-notification/read':
            return _json({'ok': true});
          case 'GET /api/report-generation-runs/run-history':
            return _json({
              'id': 'run-history',
              'state': 'failed',
              'error': 'generation failed',
            });
          default:
            return http.Response('not found', 404);
        }
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: NotificationsPage(api: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('报告生成失败'));
    await tester.pumpAndSettle();

    final page = tester.widget<ReportRunPage>(find.byType(ReportRunPage));
    expect(page.runId, 'run-history');
    expect(
      requested,
      contains('POST /api/notifications/history-run-notification/read'),
    );
    expect(requested, contains('GET /api/report-generation-runs/run-history'));
  });

  testWidgets('deleted report from notification history does not throw', (
    tester,
  ) async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add('${request.method} ${request.url.path}');
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/notifications':
            return _json({
              'notifications': [
                _notification(
                  id: 'deleted-report-notification',
                  type: 'report_done',
                  title: '已删除的报告',
                  link: 'report:deleted-report',
                ),
              ],
              'unread': 1,
            });
          case 'POST /api/notifications/deleted-report-notification/read':
            return _json({'ok': true});
          case 'GET /api/reports/deleted-report':
            return http.Response('not found', 404);
          default:
            return http.Response('not found', 404);
        }
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: NotificationsPage(api: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('已删除的报告'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.byType(ReportViewerPage), findsNothing);
    expect(requested, contains('GET /api/reports/deleted-report'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('live report_done fetches a report and pushes its route', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add('${request.method} ${request.url.path}');
        return _json({
          'id': 'report-live',
          'title': '实时报告',
          'html': '<html>live report</html>',
        });
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final opened = openNotificationTarget(
      'report_done',
      'report:report-live',
      reportApi: api,
    );
    await tester.runAsync(() => observer.reportRoutePushed.future);

    expect(requested, ['GET /api/reports/report-live']);
    expect(observer.pushCount, 2);
    navigatorKey.currentState!.pop();
    await opened;
    await tester.pump();
  });

  testWidgets('live invalid or explicitly unknown links do not push a route', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    await openNotificationTarget('report_done', 'report-run:wrong-kind');
    await openReportNotificationTarget(
      navigatorKey.currentContext!,
      'report-run:run-1',
      type: 'unknown',
    );
    await tester.pump();

    expect(observer.pushCount, 1);
    expect(find.byType(ReportRunPage), findsNothing);
  });
}

Map<String, dynamic> _notification({
  required String id,
  required String type,
  required String title,
  required String link,
}) => {
  'id': id,
  'type': type,
  'title': title,
  'body': '',
  'link': link,
  'read': false,
  'created_at': '2026-08-04T12:00:00Z',
};

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _RecordingNavigatorObserver extends NavigatorObserver {
  final reportRoutePushed = Completer<void>();
  var pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount += 1;
    if (previousRoute != null && !reportRoutePushed.isCompleted) {
      reportRoutePushed.complete();
    }
    super.didPush(route, previousRoute);
  }
}
