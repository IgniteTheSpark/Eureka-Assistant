import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/report/report_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('empty report scope must be completed before generation', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return _json(_emptyScopeRun());
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportRunPage(runId: 'run-empty', api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前方案还没有参考资产，请先选择后再生成。'), findsOneWidget);
    expect(find.text('按推荐方案生成'), findsOneWidget);
    final quickGenerate = tester.widget<FilledButton>(
      find.byKey(const ValueKey('report-run-generate')),
    );
    expect(quickGenerate.onPressed, isNull);
    expect(requests, ['GET /api/report-generation-runs/run-empty']);
  });
}

Map<String, dynamic> _emptyScopeRun() => {
  'id': 'run-empty',
  'state': 'awaiting_selection',
  'plan_revision': 1,
  'plan_options': [
    {
      'id': 'daily',
      'recommended': true,
      'title': '今日执行报告',
      'summary': '整理今天的日程与代办',
      'web_search': {'policy': 'none'},
      'illustration': {'policy': 'optional'},
    },
  ],
  'plan_draft': {
    'selected_option_id': 'daily',
    'attention_questions': [],
    'evidence_scope': {'references': []},
    'public_research_scope': {},
    'blockers': [],
  },
};

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
