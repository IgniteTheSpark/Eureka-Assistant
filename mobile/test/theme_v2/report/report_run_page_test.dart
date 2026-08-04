import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/report/report_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('user-initiated run uses generic report copy', (tester) async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'id': 'run-1',
              'state': 'failed',
              'intent': '总结最近的跑步训练',
              'failure': {
                'stage': 'content_generation',
                'message': '模型暂时不可用',
                'retry_from': 'generation',
              },
            }),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(runId: 'run-1', api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('报告'), findsOneWidget);
    expect(find.text('报告生成没有完成'), findsOneWidget);
    expect(find.textContaining('会前调研'), findsNothing);
    expect(find.byKey(const ValueKey('report-run-cancel')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('report-run-cancel'))).height,
      greaterThanOrEqualTo(ThemeV2Sizes.minTouchTarget),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('report-run-retry'))).height,
      greaterThanOrEqualTo(ThemeV2Sizes.minTouchTarget),
    );
  });

  testWidgets('cancelling an active run returns to its report container', (
    tester,
  ) async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return _json({'id': 'run-1', 'state': 'generating'});
        }
        expect(request.url.path, '/api/report-generation-runs/run-1/cancel');
        expect(jsonDecode(request.body), isEmpty);
        return _json({'id': 'run-1', 'state': 'cancelled'});
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportRunPage(runId: 'run-1', api: api),
                ),
              ),
              child: const Text('报告容器'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('报告容器'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-run-cancel')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('报告容器'), findsOneWidget);
    expect(requested, [
      'GET /api/report-generation-runs/run-1',
      'POST /api/report-generation-runs/run-1/cancel',
    ]);
  });

  testWidgets('failed cancellation stays visible and can be retried', (
    tester,
  ) async {
    var cancelAttempts = 0;
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return _json({'id': 'run-1', 'state': 'generating'});
        }
        cancelAttempts++;
        if (cancelAttempts == 1) {
          return http.Response('unavailable', 503);
        }
        return _json({'id': 'run-1', 'state': 'cancelled'});
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(_containerApp(api));
    await _openActiveRun(tester);
    await tester.tap(find.byKey(const ValueKey('report-run-cancel')));
    await tester.pump();

    expect(find.text('报告服务尚未配置完成'), findsOneWidget);
    final retry = find.byKey(const ValueKey('report-run-cancel-retry'));
    expect(retry, findsOneWidget);
    expect(
      tester.getSize(retry).height,
      greaterThanOrEqualTo(ThemeV2Sizes.minTouchTarget),
    );

    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('报告容器'), findsOneWidget);
    expect(cancelAttempts, 2);
  });

  testWidgets('plan and clarification submission controls meet touch target', (
    tester,
  ) async {
    var response = <String, dynamic>{
      'id': 'run-1',
      'state': 'awaiting_selection',
      'plan_options': [
        {'id': 'option-1', 'title': '训练复盘', 'summary': '总结训练'},
      ],
    };
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async => _json(response)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(runId: 'run-1', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('report-run-generate'))).height,
      greaterThanOrEqualTo(ThemeV2Sizes.minTouchTarget),
    );

    response = <String, dynamic>{
      'id': 'run-2',
      'state': 'awaiting_selection',
      'pending_decision': {
        'type': 'clarification',
        'questions': [
          {'id': 'audience', 'question': '读者是谁？', 'required': false},
        ],
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(
          key: const ValueKey('run-2'),
          runId: 'run-2',
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('report-run-clarification-submit')),
          )
          .height,
      greaterThanOrEqualTo(ThemeV2Sizes.minTouchTarget),
    );
  });
}

Widget _containerApp(ApiClient api) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Builder(
    builder: (context) => Scaffold(
      body: FilledButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReportRunPage(runId: 'run-1', api: api),
          ),
        ),
        child: const Text('报告容器'),
      ),
    ),
  ),
);

Future<void> _openActiveRun(WidgetTester tester) async {
  await tester.tap(find.text('报告容器'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
