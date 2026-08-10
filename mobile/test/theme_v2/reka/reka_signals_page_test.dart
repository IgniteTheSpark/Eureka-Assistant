import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/reka/reka_signal.dart';
import 'package:eureka/theme_v2/reka/reka_signal_repository.dart';
import 'package:eureka/theme_v2/reka/reka_signals_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists overdue and rhythm signals and opens their targets', (
    tester,
  ) async {
    final repository = _FakeRepository(
      RekaSignalBatch(
        signals: [_overdue(), _rhythm()],
        partialFailures: const [],
        generatedAt: DateTime(2026, 8, 10, 10),
      ),
    );
    String? opened;

    await tester.pumpWidget(
      _Host(
        child: RekaSignalsPage(
          repository: repository,
          onOpenTarget: (_, item) async => opened = item.id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reka 发现'), findsOneWidget);
    expect(find.text('提交费用单 已到截止时间'), findsOneWidget);
    expect(find.text('消费还没有记录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-reka-icon-overdue')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('theme-v2-reka-icon-rhythm_gap')),
      findsOneWidget,
    );

    await tester.tap(find.text('提交费用单 已到截止时间'));
    expect(opened, 'overdue-1');
  });

  testWidgets('dismisses one signal without turning it into a receipt', (
    tester,
  ) async {
    final repository = _FakeRepository(
      RekaSignalBatch(
        signals: [_overdue()],
        partialFailures: const [],
        generatedAt: DateTime(2026, 8, 10, 10),
      ),
    );

    await tester.pumpWidget(
      _Host(child: RekaSignalsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('theme-v2-reka-menu-overdue-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('忽略提醒'));
    await tester.pumpAndSettle();

    expect(repository.dismissed, ['overdue-1']);
    expect(find.text('提交费用单 已到截止时间'), findsNothing);
    expect(find.text('暂时没有新的发现'), findsOneWidget);
  });

  testWidgets('empty state links report history and proactive creation', (
    tester,
  ) async {
    final repository = _FakeRepository(
      RekaSignalBatch(
        signals: const [],
        partialFailures: const [],
        generatedAt: DateTime(2026, 8, 10, 10),
      ),
    );
    var reports = 0;
    var create = 0;

    await tester.pumpWidget(
      _Host(
        child: RekaSignalsPage(
          repository: repository,
          onOpenReports: () => reports++,
          onCreateReport: () => create++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看历史报告'));
    await tester.tap(find.text('生成新报告'));
    expect(reports, 1);
    expect(create, 1);
  });

  testWidgets('partial source failure keeps healthy signals visible', (
    tester,
  ) async {
    final repository = _FakeRepository(
      RekaSignalBatch(
        signals: [_overdue()],
        partialFailures: const ['rhythm_gap'],
        generatedAt: DateTime(2026, 8, 10, 10),
      ),
    );

    await tester.pumpWidget(
      _Host(child: RekaSignalsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 类发现暂时未能刷新，下拉可重试'), findsOneWidget);
    expect(find.text('提交费用单 已到截止时间'), findsOneWidget);
  });

  testWidgets('total load failure exposes retry and recovers', (tester) async {
    final repository = _FakeRepository(
      const RekaSignalBatch(
        signals: [],
        partialFailures: [],
        generatedAt: null,
      ),
      loadValues: [
        Exception('offline'),
        const RekaSignalBatch(
          signals: [],
          partialFailures: [],
          generatedAt: null,
        ),
      ],
    );

    await tester.pumpWidget(
      _Host(child: RekaSignalsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reka 发现加载失败'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂时没有新的发现'), findsOneWidget);
    expect(repository.loadCount, 2);
  });

  testWidgets('mutation failure retains the signal and reports the error', (
    tester,
  ) async {
    final repository = _FakeRepository(
      RekaSignalBatch(
        signals: [_overdue()],
        partialFailures: const [],
        generatedAt: DateTime(2026, 8, 10, 10),
      ),
      dismissError: Exception('offline'),
    );

    await tester.pumpWidget(
      _Host(child: RekaSignalsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('theme-v2-reka-menu-overdue-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('忽略提醒'));
    await tester.pumpAndSettle();

    expect(find.text('提交费用单 已到截止时间'), findsOneWidget);
    expect(find.text('操作失败，请稍后重试'), findsOneWidget);
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(theme: buildThemeV2Theme(Brightness.light), home: child);
}

class _FakeRepository implements RekaSignalRepository {
  _FakeRepository(this.batch, {this.loadValues, this.dismissError});

  final RekaSignalBatch batch;
  final List<Object>? loadValues;
  final Object? dismissError;
  final dismissed = <String>[];
  var loadCount = 0;

  @override
  Future<void> completeTodo(String assetId) async {}

  @override
  Future<void> dismiss(String signalId) async {
    if (dismissError case final error?) throw error;
    dismissed.add(signalId);
  }

  @override
  Future<RekaSignalBatch> load({String timezoneName = 'Asia/Shanghai'}) async {
    loadCount++;
    final values = loadValues;
    if (values == null || values.isEmpty) return batch;
    final value = values.removeAt(0);
    if (value is RekaSignalBatch) return value;
    throw value;
  }
}

RekaSignal _overdue() => RekaSignal(
  id: 'overdue-1',
  naturalKey: 'overdue:todo-1:2026-08-10',
  kind: RekaSignalKind.overdue,
  title: '提交费用单 已到截止时间',
  body: '仍未完成',
  target: const RekaSignalTarget(
    type: RekaSignalTargetType.asset,
    id: 'todo-1',
  ),
  actions: const [
    RekaSignalAction.open,
    RekaSignalAction.complete,
    RekaSignalAction.reschedule,
    RekaSignalAction.dismiss,
  ],
  deliveredAt: DateTime(2026, 8, 10, 9),
);

RekaSignal _rhythm() => RekaSignal(
  id: 'rhythm-1',
  naturalKey: 'rhythm:expense:daily:any:2026-08-10',
  kind: RekaSignalKind.rhythmGap,
  title: '消费还没有记录',
  body: '可以现在补上一笔',
  target: const RekaSignalTarget(
    type: RekaSignalTargetType.skill,
    id: 'expense',
  ),
  actions: const [RekaSignalAction.open, RekaSignalAction.dismiss],
  deliveredAt: DateTime(2026, 8, 10, 8),
);
