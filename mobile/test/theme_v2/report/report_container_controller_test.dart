import 'dart:async';

import 'package:eureka/theme_v2/report/report_container_controller.dart';
import 'package:eureka/theme_v2/report/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportContainerController', () {
    test('does not load until requested and exposes priority groups', () async {
      final repository = _Repository(_overview());
      final controller = ReportContainerController(repository: repository);
      addTearDown(controller.dispose);

      expect(repository.loadCount, 0);
      expect(controller.status, ReportContainerStatus.idle);

      await controller.load();

      expect(repository.loadCount, 1);
      expect(controller.status, ReportContainerStatus.ready);
      expect(controller.pendingDecisionRuns.single.id, 'decision');
      expect(controller.inProgressRuns.map((run) => run.id), [
        'planning',
        'generating',
        'failed',
      ]);
      expect(controller.completedReports.single.id, 'report-1');
    });

    test('partial empty and offline loads expose distinct states', () async {
      final partial = ReportContainerController(
        repository: _Repository(
          ReportOverview(
            activeRuns: [_run('planning', 'planning')],
            failedSources: const [
              ReportSourceFailure(source: 'reports', isOffline: false),
            ],
          ),
        ),
      );
      addTearDown(partial.dispose);
      await partial.load();
      expect(partial.status, ReportContainerStatus.partial);

      final empty = ReportContainerController(
        repository: _Repository(ReportOverview()),
      );
      addTearDown(empty.dispose);
      await empty.load();
      expect(empty.status, ReportContainerStatus.empty);

      final offline = ReportContainerController(
        repository: _SequenceRepository([
          const ReportLoadFailure('offline', isOffline: true),
          _overview(),
        ]),
      );
      addTearDown(offline.dispose);
      await offline.load();
      expect(offline.status, ReportContainerStatus.offline);
      await offline.retry();
      expect(offline.status, ReportContainerStatus.ready);
    });

    test('refresh retains the current snapshot while loading', () async {
      final next = Completer<ReportOverview>();
      final repository = _DeferredRepository(_overview(), next.future);
      final controller = ReportContainerController(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();

      final refreshing = controller.load();
      expect(controller.status, ReportContainerStatus.loading);
      expect(controller.overview?.completedReports.single.id, 'report-1');

      next.complete(ReportOverview());
      await refreshing;
      expect(controller.status, ReportContainerStatus.empty);
    });
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

class _DeferredRepository implements ReportRepository {
  _DeferredRepository(this.first, this.second);

  final ReportOverview first;
  final Future<ReportOverview> second;
  var calls = 0;

  @override
  Future<ReportOverview> loadOverview() {
    calls++;
    return calls == 1 ? Future.value(first) : second;
  }
}

ReportOverview _overview() => ReportOverview(
  activeRuns: [
    _run('decision', 'awaiting_selection'),
    _run('planning', 'planning'),
    _run('generating', 'generating'),
    _run('failed', 'failed'),
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

ReportRunSummary _run(String id, String state) => ReportRunSummary(
  id: id,
  origin: 'user_initiated',
  state: state,
  intent: '$id intent',
  activeStage: state == 'generating' ? 'content_generation' : null,
  pendingDecision: state == 'awaiting_selection'
      ? const {'type': 'plan_selection'}
      : const {},
  planOptions: state == 'awaiting_selection'
      ? const [
          {
            'id': 'option-1',
            'recommended': true,
            'title': '待确认的报告方案',
            'summary': '选择后开始生成',
          },
        ]
      : const [],
  failureMessage: state == 'failed' ? '网络调研失败' : null,
  reportId: null,
  createdAt: null,
  updatedAt: null,
);
