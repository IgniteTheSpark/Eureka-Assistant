import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/reka/reka_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps phased Report metadata into the Today queue', () {
    final items = mapTodayRekaSignals([
      RekaSignal(
        id: 'plan-ready',
        naturalKey: 'report:execution-1:plan_ready',
        kind: RekaSignalKind.report,
        title: '报告方案已准备好',
        body: '可以查看方案。',
        target: const RekaSignalTarget(
          type: RekaSignalTargetType.reportRun,
          id: 'run-1',
        ),
        actions: const [RekaSignalAction.open, RekaSignalAction.dismiss],
        deliveredAt: DateTime.utc(2026, 8, 10, 10),
        reportPhase: RekaReportPhase.planReady,
        chainId: 'execution-1',
        evidence: const {'asset_count': 4},
        reportRunId: 'run-1',
      ),
    ]);

    final item = items.single;
    expect(item.reportPhase, 'plan_ready');
    expect(item.chainId, 'execution-1');
    expect(item.evidence, {'asset_count': 4});
    expect(item.reportRunId, 'run-1');
    expect(item.reportId, isNull);
  });
}
