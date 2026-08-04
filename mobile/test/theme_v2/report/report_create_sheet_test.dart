import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/report/report_container_controller.dart';
import 'package:eureka/theme_v2/report/report_container_page.dart';
import 'package:eureka/theme_v2/report/report_create_sheet.dart';
import 'package:eureka/theme_v2/report/report_repository.dart';
import 'package:eureka/theme_v2/report/report_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('manual creation requires intent and returns the created run', (
    tester,
  ) async {
    final api = _api((request) async {
      expect(jsonDecode(request.body), {
        'origin': 'user_initiated',
        'intent': '总结最近的跑步训练',
      });
      return _json({
        'id': 'run-manual',
        'state': 'planning',
        'intent': '总结最近的跑步训练',
      });
    });
    addTearDown(api.close);
    String? createdRunId;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: ReportCreateSheet(
            api: api,
            onCreated: (runId) => createdRunId = runId,
          ),
        ),
      ),
    );

    final submit = find.byKey(const ValueKey('report-create-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(
      tester.getSize(submit).height,
      greaterThanOrEqualTo(ThemeV2Sizes.minTouchTarget),
    );

    await tester.enterText(
      find.byKey(const ValueKey('report-create-intent')),
      '总结最近的跑步训练',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pump();

    expect(createdRunId, 'run-manual');
  });

  testWidgets('failed creation keeps the intent available for retry', (
    tester,
  ) async {
    var attempts = 0;
    final api = _api((request) async {
      attempts++;
      if (attempts == 1) {
        return _json({'detail': 'not configured'}, statusCode: 503);
      }
      return _json({'id': 'run-retried', 'state': 'planning'});
    });
    addTearDown(api.close);
    String? createdRunId;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: ReportCreateSheet(
            api: api,
            onCreated: (runId) => createdRunId = runId,
          ),
        ),
      ),
    );

    final field = find.byKey(const ValueKey('report-create-intent'));
    await tester.enterText(field, '分析最近的工作记录');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-create-submit')));
    await tester.pumpAndSettle();

    expect(find.text('报告服务尚未配置完成'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller?.text, '分析最近的工作记录');
    final submit = find.byKey(const ValueKey('report-create-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pump();

    expect(createdRunId, 'run-retried');
    expect(attempts, 2);
  });

  testWidgets('opening the report container does not create a report run', (
    tester,
  ) async {
    final requests = <String>[];
    final api = _api((request) async {
      requests.add('${request.method} ${request.url.path}');
      return _json([]);
    });
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportContainerPage(api: api),
      ),
    );
    await tester.pump();

    expect(
      requests,
      containsAll(<String>[
        'GET /api/report-generation-runs',
        'GET /api/reports',
      ]),
    );
    expect(requests.where((request) => request.startsWith('POST')), isEmpty);
  });

  testWidgets('keyboard submission opens the created report run', (
    tester,
  ) async {
    final requests = <String>[];
    final api = _api((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'POST') {
        expect(jsonDecode(request.body), {
          'origin': 'user_initiated',
          'intent': '总结最近的跑步训练',
        });
        return _json({'id': 'run-manual', 'state': 'planning'});
      }
      return _json({'id': 'run-manual', 'state': 'planning'});
    });
    final controller = ReportContainerController(
      repository: _EmptyRepository(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportContainerPage(
          api: api,
          controller: controller,
          autoLoad: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('report-create')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const ValueKey('report-create-intent')),
      '总结最近的跑步训练',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ReportRunPage), findsOneWidget);
    expect(requests, [
      'POST /api/report-generation-runs',
      'GET /api/report-generation-runs/run-manual',
    ]);
  });
}

class _EmptyRepository implements ReportRepository {
  @override
  Future<ReportOverview> loadOverview() async => ReportOverview();
}

ApiClient _api(Future<http.Response> Function(http.Request request) handler) =>
    ApiClient(
      client: MockClient(handler),
      baseUrl: 'https://reports.test',
      enableLogging: false,
    );

http.Response _json(Object body, {int statusCode = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
