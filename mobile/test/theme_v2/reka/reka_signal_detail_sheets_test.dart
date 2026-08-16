import 'dart:async';

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/reka/reka_report_detail_sheet.dart';
import 'package:eureka/theme_v2/reka/reka_rhythm_detail_sheet.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rhythm sheet uses Period-only evidence and returns record', (
    tester,
  ) async {
    RekaRhythmDetailAction? action;
    final item = TodayRekaItem(
      id: 'rhythm-1',
      type: 'rhythm_gap',
      title: '跑步还没有记录',
      body: '你通常在周三晚上 20:00 记录',
      link: '',
      createdAt: DateTime(2026, 8, 14, 10),
      naturalKey: 'rhythm:running:weekly:2:晚上:2026-W33',
      targetType: 'skill',
      targetId: 'running',
      actions: const ['open', 'dismiss'],
      evidence: const {
        'cadence': 'weekly',
        'weekdays': <int>[2],
        'period': '晚上',
        'sample_n': 7,
      },
    );

    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showRekaRhythmDetailSheet(
                context,
                item,
              ).then((value) => action = value),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('节律提醒'), findsOneWidget);
    expect(find.textContaining('周三晚上'), findsOneWidget);
    expect(find.textContaining('最近 28 天有 7 次记录'), findsOneWidget);
    expect(find.textContaining('本周还没有跑步记录'), findsOneWidget);
    expect(find.textContaining('20:00'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reka-rhythm-record')));
    await tester.pumpAndSettle();
    expect(action, RekaRhythmDetailAction.record);
  });

  testWidgets('report sheet renders all three actionable phases', (
    tester,
  ) async {
    final cases = <({TodayRekaItem item, String body, String action})>[
      (
        item: _report(
          phase: 'opportunity',
          targetType: 'trigger_execution',
          targetId: 'execution-1',
          evidence: const {'event_title': '产品评审会'},
        ),
        body: '产品评审会',
        action: '生成报告方案',
      ),
      (
        item: _report(
          phase: 'plan_ready',
          targetType: 'report_run',
          targetId: 'run-1',
          evidence: const {
            'asset_count': 4,
            'plan': {'report_goal': '梳理决策与风险'},
          },
        ),
        body: '4 条材料',
        action: '查看并确认方案',
      ),
      (
        item: _report(
          phase: 'report_ready',
          targetType: 'report',
          targetId: 'report-1',
          evidence: const {'title': '产品路线研究', 'summary': '三个决策点已经收敛。'},
        ),
        body: '三个决策点已经收敛',
        action: '查看完整报告',
      ),
    ];

    for (final entry in cases) {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  unawaited(showRekaReportDetailSheet(context, entry.item)),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.textContaining(entry.body), findsWidgets);
      expect(find.text(entry.action), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reka-report-close')));
      await tester.pumpAndSettle();
    }
  });
}

TodayRekaItem _report({
  required String phase,
  required String targetType,
  required String targetId,
  required Map<String, dynamic> evidence,
}) => TodayRekaItem(
  id: 'report-$phase',
  type: 'report',
  title: '报告发现',
  body: '报告发现详情',
  link: '',
  createdAt: DateTime(2026, 8, 14, 10),
  naturalKey: 'report:chain-1:$phase',
  targetType: targetType,
  targetId: targetId,
  actions: const ['open', 'dismiss'],
  reportPhase: phase,
  chainId: 'chain-1',
  evidence: evidence,
);

Widget _host(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(body: child),
);
