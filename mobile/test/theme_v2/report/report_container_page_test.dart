import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/report/report_container_controller.dart';
import 'package:eureka/theme_v2/report/report_container_page.dart';
import 'package:eureka/theme_v2/report/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('priority layer precedes active work and completed library', (
    tester,
  ) async {
    final controller = ReportContainerController(
      repository: _Repository(_overview()),
    );
    addTearDown(controller.dispose);
    await controller.load();
    String? openedRun;
    String? openedReport;
    var createCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportContainerPage(
          controller: controller,
          autoLoad: false,
          onCreate: () => createCount++,
          onOpenRun: (run) => openedRun = run.id,
          onOpenReport: (report) => openedReport = report.id,
        ),
      ),
    );

    expect(find.text('报告'), findsOneWidget);
    expect(find.text('等待你确认'), findsOneWidget);
    expect(find.text('生成中/需要处理'), findsOneWidget);
    expect(find.text('报告库'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('等待你确认')).dy,
      lessThan(tester.getTopLeft(find.text('生成中/需要处理')).dy),
    );
    expect(
      tester.getTopLeft(find.text('生成中/需要处理')).dy,
      lessThan(tester.getTopLeft(find.text('报告库')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('report-run-decision')));
    await tester.tap(find.byKey(const ValueKey('report-item-report-1')));
    await tester.tap(find.byKey(const ValueKey('report-create')));

    expect(openedRun, 'decision');
    expect(openedReport, 'report-1');
    expect(createCount, 1);
  });

  testWidgets('empty report container offers creation without making a run', (
    tester,
  ) async {
    final repository = _Repository(ReportOverview());
    final controller = ReportContainerController(repository: repository);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportContainerPage(
          controller: controller,
          autoLoad: false,
          onCreate: () {},
          onOpenRun: (_) {},
          onOpenReport: (_) {},
        ),
      ),
    );

    expect(find.text('还没有报告'), findsOneWidget);
    expect(find.text('创建报告'), findsOneWidget);
    expect(repository.loadCount, 1);
  });

  testWidgets('offline retry action has a stable key', (tester) async {
    final controller = ReportContainerController(
      repository: _SequenceRepository([
        const ReportLoadFailure('offline', isOffline: true),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ReportContainerPage(controller: controller, autoLoad: false),
      ),
    );

    expect(find.byKey(const ValueKey('report-retry')), findsOneWidget);
  });
}

class _Repository implements ReportRepository {
  _Repository(this.overview);

  final ReportOverview overview;
  var loadCount = 0;

  @override
  Future<ReportOverview> loadOverview() async {
    loadCount++;
    return overview;
  }
}

class _SequenceRepository implements ReportRepository {
  _SequenceRepository(this.values);

  final List<Object> values;

  @override
  Future<ReportOverview> loadOverview() async {
    final value = values.removeAt(0);
    if (value is ReportOverview) return value;
    throw value;
  }
}

ReportOverview _overview() => ReportOverview(
  activeRuns: [
    ReportRunSummary(
      id: 'decision',
      origin: 'user_initiated',
      state: 'awaiting_selection',
      intent: '总结跑步训练',
      activeStage: null,
      pendingDecision: const {'type': 'plan_selection'},
      planOptions: const [
        {
          'id': 'option-1',
          'recommended': true,
          'title': '跑步训练复盘',
          'summary': '选择后开始生成',
        },
      ],
      failureMessage: null,
      reportId: null,
      createdAt: null,
      updatedAt: null,
    ),
    ReportRunSummary(
      id: 'generating',
      origin: 'user_initiated',
      state: 'generating',
      intent: '汽车灵感升华',
      activeStage: 'content_generation',
      pendingDecision: {},
      planOptions: [],
      failureMessage: null,
      reportId: null,
      createdAt: null,
      updatedAt: null,
    ),
  ],
  completedReports: const [
    CompletedReportSummary(
      id: 'report-1',
      title: '七月网球战报',
      summary: '12 场 · 8 胜',
      html: '<html></html>',
      baseFamily: 'data_trend',
      createdAt: null,
    ),
  ],
);
