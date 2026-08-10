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
    expect(find.text('模型暂时不可用'), findsOneWidget);
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

  testWidgets('completed run without report id shows a recoverable error', (
    tester,
  ) async {
    var runLoads = 0;
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        runLoads++;
        return _json({'id': 'run-missing-report', 'state': 'completed'});
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(runId: 'run-missing-report', api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('报告内容暂时无法打开'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-run-open-retry')), findsOneWidget);
    expect(find.text('报告已完成，正在打开…'), findsNothing);
    expect(runLoads, greaterThanOrEqualTo(1));
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

  testWidgets('report adjustment uses three distinct stepper screens', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async => _json(_planRun())),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(runId: 'run-plan', api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('report-recommended-plan')),
      findsOneWidget,
    );
    expect(find.text('球队建设会前调研'), findsOneWidget);
    expect(find.textContaining('公开调研 皇家马德里、巴塞罗那'), findsOneWidget);
    expect(find.text('一键生成'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-plan-stepper')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-step-plan')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-additional-focus')), findsNothing);
    expect(find.byKey(const ValueKey('report-final-summary')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('report-run-adjust')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-step-scope')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('report-additional-focus')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('report-open-evidence-picker')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('report-open-evidence-picker')),
      findsOneWidget,
    );
    expect(find.text('球队建设会前调研'), findsNothing);
    expect(find.byKey(const ValueKey('report-final-summary')), findsNothing);
    expect(find.textContaining('时间范围'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('report-step-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-step-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-final-summary')), findsOneWidget);
    expect(find.text('球队建设会前调研'), findsOneWidget);
    expect(find.text('1 项参考资产'), findsOneWidget);
    expect(find.text('皇家马德里、巴塞罗那'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-additional-focus')), findsNothing);
  });

  testWidgets('stepper preserves edits and submits only from final step', (
    tester,
  ) async {
    final requests = <String>[];
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') return _json(_planRun());
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (request.method == 'PUT') {
          return _json({
            ..._planRun(),
            'plan_revision': 4,
            'plan_draft': bodies.last,
          });
        }
        return _json({
          'id': 'run-plan',
          'state': 'generating',
          'plan_revision': 4,
        });
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(runId: 'run-plan', api: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('report-run-adjust')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('report-additional-focus')),
      '重点关注年轻球员培养',
    );
    await tester.tap(find.byKey(const ValueKey('report-step-next')));
    await tester.pumpAndSettle();

    expect(find.text('重点关注年轻球员培养'), findsOneWidget);
    expect(requests, ['GET /api/report-generation-runs/run-plan']);

    await tester.tap(find.byKey(const ValueKey('report-step-back')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('report-additional-focus')),
          )
          .controller
          ?.text,
      '重点关注年轻球员培养',
    );

    await tester.tap(find.byKey(const ValueKey('report-step-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-run-confirm-generate')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(requests, [
      'GET /api/report-generation-runs/run-plan',
      'PUT /api/report-generation-runs/run-plan/plan-draft',
      'POST /api/report-generation-runs/run-plan/generate',
    ]);
    expect(bodies.first['additional_focus'], '重点关注年轻球员培养');
    expect(bodies.last, {
      'selected_option_id': 'briefing',
      'expected_plan_revision': 4,
    });
  });
}

Map<String, dynamic> _planRun() => {
  'id': 'run-plan',
  'state': 'awaiting_selection',
  'plan_revision': 3,
  'plan_options': [
    {
      'id': 'briefing',
      'recommended': true,
      'title': '球队建设会前调研',
      'summary': '结合日程与公开阵容资料准备讨论',
      'web_search': {'policy': 'required', 'reason': '需要公开阵容资料'},
      'illustration': {'policy': 'optional', 'reason': '可生成主题插图'},
    },
  ],
  'plan_draft': {
    'selected_option_id': 'briefing',
    'attention_questions': ['两队建设策略有何差异？'],
    'evidence_scope': {
      'references': [
        {'kind': 'event', 'id': 'event-1'},
      ],
    },
    'public_research_scope': {
      'entities': [
        {'id': 'real-madrid', 'kind': 'organization', 'name': '皇家马德里'},
        {'id': 'barcelona', 'kind': 'organization', 'name': '巴塞罗那'},
      ],
      'questions': ['当前阵容'],
      'freshness': 'current',
    },
    'blockers': [],
  },
};

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
