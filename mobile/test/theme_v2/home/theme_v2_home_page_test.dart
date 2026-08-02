import 'dart:async';

import 'package:eureka/data_revision.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/home_agenda_panel.dart';
import 'package:eureka/theme_v2/home/home_controller.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/home/home_today_panel.dart';
import 'package:eureka/theme_v2/home/theme_v2_home_page.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => dataRevision.value = 0);

  test(
    'fake repository returns supported Today data without Goal state',
    () async {
      const expected = TodayData.empty;
      final repository = _FakeHomeRepository(expected);

      expect(await repository.load(), same(expected));
    },
  );

  testWidgets('Home promotes Today and exposes no secondary layer', (
    tester,
  ) async {
    _setReferenceView(tester);
    final controller = ThemeV2HomeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          controller: controller,
          repository: const _FakeHomeRepository(TodayData.empty),
          now: DateTime(2026, 7, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(ThemeV2HomePage.panelKey);
    expect(tester.getTopLeft(panel), const Offset(8, 54));
    expect(tester.getSize(panel), const Size(395, 790));
    expect(find.byType(HomeTodayPanel), findsOneWidget);
    expect(find.text('目标'), findsNothing);
    expect(find.bySemanticsLabel('打开目标'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.left ||
                widget.axisDirection == AxisDirection.right),
      ),
      findsNothing,
    );
  });

  testWidgets('Today follows the Pen default composition at 411x960', (
    tester,
  ) async {
    _setReferenceView(tester);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(_fixture),
          now: DateTime(2026, 7, 31, 9, 48),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nextMoment = find.byKey(const ValueKey('theme-v2-today-next-moment'));
    final rekaQueue = find.byKey(const ValueKey('theme-v2-today-reka-queue'));
    final bubbleField = find.byKey(
      const ValueKey('theme-v2-today-asset-bubble-field'),
    );

    expect(tester.getTopLeft(nextMoment), const Offset(20, 106));
    expect(tester.getSize(nextMoment), const Size(371, 126));
    expect(tester.getTopLeft(rekaQueue), const Offset(20, 240));
    expect(tester.getSize(rekaQueue), const Size(371, 188));
    expect(tester.getTopLeft(bubbleField), const Offset(8, 54));
    expect(tester.getSize(bubbleField), const Size(395, 790));
    expect(find.text('NEXT / 10:30'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('分钟后'), findsOneWidget);
    expect(find.text('今日共 1 项  ↗'), findsOneWidget);
    expect(find.text('下一时刻'), findsNothing);
    expect(find.text('今日生成'), findsOneWidget);
  });

  testWidgets('Today chooses NEXT from the unfinished full-day chain', (
    tester,
  ) async {
    _setReferenceView(tester);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(_agendaFixture),
          now: DateTime(2026, 7, 31, 9, 48),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEXT / 10:30'), findsOneWidget);
    expect(find.text('NEXT / 09:00'), findsNothing);
    expect(find.text('今日共 2 项  ↗'), findsOneWidget);
  });

  testWidgets('Agenda uses the same promoted panel geometry', (tester) async {
    _setReferenceView(tester);
    final controller = ThemeV2HomeController(
      initialPresentation: HomePresentation.agenda,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          controller: controller,
          repository: const _FakeHomeRepository(TodayData.empty),
          now: DateTime(2026, 7, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeAgendaPanel), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ThemeV2HomePage.panelKey)),
      const Size(395, 790),
    );
    expect(
      tester.getSize(find.bySemanticsLabel('收起日程')),
      const Size.square(44),
    );
  });

  testWidgets('Agenda follows the Pen fishbone composition at 411x960', (
    tester,
  ) async {
    _setReferenceView(tester);
    final controller = ThemeV2HomeController(
      initialPresentation: HomePresentation.agenda,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          controller: controller,
          repository: _FakeHomeRepository(_agendaFixture),
          now: DateTime(2026, 7, 31, 9, 48),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final spine = find.byKey(const ValueKey('theme-v2-agenda-spine'));
    final firstCard = find.byKey(const ValueKey('theme-v2-agenda-card-0'));
    final secondCard = find.byKey(const ValueKey('theme-v2-agenda-card-1'));

    expect(tester.getTopLeft(spine), const Offset(205, 150));
    expect(tester.getSize(spine), const Size(1, 606));
    expect(tester.getTopLeft(firstCard), const Offset(26, 138));
    expect(tester.getSize(firstCard), const Size(148, 78));
    expect(tester.getTopLeft(secondCard), const Offset(237, 222));
    expect(tester.getSize(secondCard), const Size(148, 78));
    expect(find.text('今日安排'), findsOneWidget);
    expect(find.text('7月31日 · 周五'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-agenda-generated-chamber')),
      findsNothing,
    );
  });

  testWidgets('Agenda opens from Today and returns with explicit actions', (
    tester,
  ) async {
    _setReferenceView(tester);
    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(_fixture),
          now: DateTime(2026, 7, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.bySemanticsLabel('打开日程')), const Size(116, 44));
    await tester.tap(find.bySemanticsLabel('打开日程'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeAgendaPanel), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('收起日程'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeTodayPanel), findsOneWidget);
  });

  test('queue filtering uses explicit metadata and preserves user text', () {
    final ordinary = _queueItem(title: '更新个人目标');
    final goalDerived = _queueItem(
      title: '系统进度消息',
      card: const {'queue_type': 'goal_progress'},
    );
    final goalLinked = _queueItem(
      title: '系统建议',
      card: const {'goal_id': 'goal-1'},
    );

    expect(supportedHomeQueueItems([ordinary, goalDerived, goalLinked]), [
      same(ordinary),
    ]);
  });

  testWidgets('initial failure exposes retry and can recover', (tester) async {
    _setReferenceView(tester);
    final repository = _ScriptedRepository([
      () => Future<TodayData>.error(StateError('offline')),
      () async => _fixture,
    ]);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: repository,
          now: DateTime(2026, 7, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日加载失败'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('NEXT / 10:30'), findsOneWidget);
    expect(repository.loadCount, 2);
  });

  testWidgets('refresh retains prior Today data until replacement arrives', (
    tester,
  ) async {
    _setReferenceView(tester);
    final refresh = Completer<TodayData>();
    final repository = _ScriptedRepository([
      () async => _fixture,
      () => refresh.future,
    ]);

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: repository,
          now: DateTime(2026, 7, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('团队周会'), findsOneWidget);

    bumpData();
    await tester.pump();

    expect(find.text('团队周会'), findsOneWidget);
    expect(find.bySemanticsLabel('正在刷新今日'), findsOneWidget);

    refresh.complete(TodayData.empty);
    await tester.pumpAndSettle();
    expect(find.text('团队周会'), findsNothing);
    expect(repository.loadCount, 2);
  });
}

void _setReferenceView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 960);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

final _fixture = TodayData(
  chain: [
    ChainItem(
      kind: 'event',
      id: 'event-1',
      title: '团队周会',
      at: DateTime(2026, 7, 31, 10, 30),
      timed: true,
      sub: '会议室 A',
    ),
  ],
  noTimeTodos: [_queueItem(title: '整理研究笔记')],
  pool: [
    PoolAsset(
      id: 'asset-1',
      type: 'note',
      domain: 'work',
      title: '访谈摘录',
      payload: const {'content': '访谈摘录'},
      createdAt: DateTime(2026, 7, 31, 9),
    ),
  ],
  poolTrueCount: 1,
  flashCount: 2,
  todoDone: 1,
  todoTotal: 2,
);

final _agendaFixture = TodayData(
  chain: [
    ChainItem(
      kind: 'event',
      id: 'event-1',
      title: '线上复盘会',
      at: DateTime(2026, 7, 31, 9),
      timed: true,
      sub: '45 分钟',
      dur: const Duration(minutes: 45),
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-1',
      title: '提交费用单',
      at: DateTime(2026, 7, 31, 10, 30),
      timed: true,
      sub: '待办',
    ),
  ],
  noTimeTodos: [_queueItem(title: '整理研究笔记')],
  pool: _fixture.pool,
  poolTrueCount: _fixture.poolTrueCount,
  flashCount: _fixture.flashCount,
);

ChainItem _queueItem({
  required String title,
  Map<String, dynamic> card = const {},
}) {
  return ChainItem(
    kind: 'todo',
    id: title,
    title: title,
    at: DateTime(2026, 7, 31),
    timed: false,
    card: card,
  );
}

class _FakeHomeRepository implements ThemeV2HomeRepository {
  const _FakeHomeRepository(this.value);

  final TodayData value;

  @override
  Future<TodayData> load() async => value;
}

class _ScriptedRepository implements ThemeV2HomeRepository {
  _ScriptedRepository(this._loads);

  final List<Future<TodayData> Function()> _loads;
  int loadCount = 0;

  @override
  Future<TodayData> load() {
    final index = loadCount.clamp(0, _loads.length - 1);
    loadCount++;
    return _loads[index]();
  }
}

class _HomeHost extends StatelessWidget {
  const _HomeHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(
        size: Size(411, 960),
        devicePixelRatio: 1,
        padding: EdgeInsets.only(top: 44),
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(body: SafeArea(bottom: false, child: child)),
      ),
    );
  }
}
