import 'dart:async';

import 'package:eureka/data_revision.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/home_agenda_panel.dart';
import 'package:eureka/theme_v2/home/home_controller.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/home/home_today_panel.dart';
import 'package:eureka/theme_v2/home/theme_v2_asset_bubble_field.dart';
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
        size: const Size(360, 640),
        child: ThemeV2HomePage(
          controller: controller,
          repository: const _FakeHomeRepository(TodayData.empty),
          now: DateTime(2026, 7, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final document = find.byKey(ThemeV2HomePage.panelKey);
    expect(document, findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-page-title-home')),
      findsOneWidget,
    );
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

  testWidgets('Today uses three aligned independent regions at 411x960', (
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
    final chamber = find.byKey(HomeTodayPanel.gravityChamberKey);
    final pageTitle = find.byKey(const ValueKey('theme-v2-page-title-home'));

    expect(tester.getTopLeft(pageTitle).dx, 18);
    expect(tester.getTopLeft(nextMoment).dx, 18);
    expect(tester.getTopLeft(rekaQueue).dx, 18);
    expect(tester.getTopLeft(chamber).dx, 18);
    expect(tester.getSize(nextMoment), const Size(375, 126));
    expect(tester.getSize(rekaQueue), const Size(375, 188));
    expect(tester.getSize(chamber).height, greaterThanOrEqualTo(340));
    expect(
      tester.getTopLeft(rekaQueue).dy - tester.getBottomLeft(nextMoment).dy,
      12,
    );
    expect(
      tester.getTopLeft(chamber).dy - tester.getBottomLeft(rekaQueue).dy,
      12,
    );
    expect(find.text('NEXT / 10:30'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('分钟后'), findsOneWidget);
    expect(find.text('今日共 1 项'), findsOneWidget);
    expect(find.text('下一时刻'), findsNothing);
    expect(find.text('Reka 生成'), findsOneWidget);
    expect(find.byType(ThemeV2AssetBubbleField), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1')),
      findsOneWidget,
    );
  });

  testWidgets('NEXT switches to compact hours at sixty minutes and above', (
    tester,
  ) async {
    _setReferenceView(tester);
    final data = TodayData(
      chain: [
        ChainItem(
          kind: 'event',
          id: 'event-hours',
          title: '提醒自己起床喝牛奶',
          at: DateTime(2026, 8, 7, 8),
          timed: true,
        ),
      ],
      noTimeTodos: const [],
      pool: const [],
      poolTrueCount: 0,
      flashCount: 0,
    );

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(data),
          now: DateTime(2026, 8, 7, 0, 36),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7.4'), findsOneWidget);
    expect(find.text('小时后'), findsOneWidget);
    expect(find.text('444'), findsNothing);
    expect(find.text('分钟后'), findsNothing);
  });

  testWidgets('short Home scrolls as one document without chamber scrolling', (
    tester,
  ) async {
    _setView(tester, const Size(360, 640));
    final manyAssets = List.generate(
      50,
      (index) => PoolAsset(
        id: 'asset-$index',
        type: 'notes',
        domain: 'work',
        title: 'Asset $index',
        payload: const {},
        createdAt: DateTime(2026, 8, 3, 10).add(Duration(minutes: index)),
      ),
    );
    final data = TodayData(
      chain: const [],
      noTimeTodos: const [],
      pool: manyAssets,
      poolTrueCount: manyAssets.length,
      flashCount: 0,
    );
    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(data),
          now: DateTime(2026, 8, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final document = find.byKey(ThemeV2HomePage.panelKey);
    final chamber = find.byKey(HomeTodayPanel.gravityChamberKey);
    final pageScrollable = find.descendant(
      of: document,
      matching: find.byType(Scrollable),
    );
    expect(document, findsOneWidget);
    expect(
      find.descendant(of: chamber, matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(pageScrollable, findsOneWidget);

    await tester.scrollUntilVisible(chamber, 240, scrollable: pageScrollable);
    await tester.pump();
    expect(tester.getBottomLeft(chamber).dy, lessThanOrEqualTo(640 - 24));
  });

  testWidgets('Home forwards inactive state to Today asset physics', (
    tester,
  ) async {
    _setReferenceView(tester);
    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(_fixture),
          now: DateTime(2026, 7, 31, 9, 48),
          active: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ThemeV2AssetBubbleField>(find.byType(ThemeV2AssetBubbleField))
          .active,
      isFalse,
    );
  });

  testWidgets('Today asset bubbles fall under gravity when motion is enabled', (
    tester,
  ) async {
    _setReferenceView(tester);
    await tester.pumpWidget(
      _HomeHost(
        disableAnimations: false,
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(_fixture),
          now: DateTime(2026, 7, 31, 9, 48),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final bubble = find.bySemanticsLabel('打开资产 访谈摘录');
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getCenter(bubble).dy, greaterThan(before.dy));
  });

  testWidgets('empty Reka queue does not paint a fake scrollbar rail', (
    tester,
  ) async {
    _setReferenceView(tester);
    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: const _FakeHomeRepository(TodayData.empty),
          now: DateTime(2026, 8, 2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final queue = find.byKey(HomeTodayPanel.rekaQueueKey);
    final rails = find.descendant(
      of: queue,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 2,
      ),
    );
    expect(rails, findsNothing);
  });

  testWidgets(
    'Reka queue uses explicit signals instead of unscheduled todos and keeps rows equal',
    (tester) async {
      _setReferenceView(tester);
      final data = TodayData(
        chain: const [],
        noTimeTodos: [_queueItem(title: '不应进入 Reka 的待办')],
        pool: const [],
        poolTrueCount: 0,
        flashCount: 0,
        rekaQueue: [
          TodayRekaItem(
            id: 'signal-1',
            type: 'rhythm_gap',
            title: '跑步训练还没有记录',
            body: '你通常会在上午记录，可以现在补上一笔。',
            link: '',
            createdAt: DateTime(2026, 8, 4, 9),
            targetType: 'skill',
            targetId: 'running_training',
            actions: const ['open', 'dismiss'],
          ),
          TodayRekaItem(
            id: 'signal-2',
            type: 'overdue',
            title: '提交费用单 已到截止时间',
            body: '这项待办仍未完成，可以现在处理或调整时间。',
            link: '',
            createdAt: DateTime(2026, 8, 4, 8),
            targetType: 'asset',
            targetId: 'todo-1',
            actions: const ['open', 'complete', 'reschedule', 'dismiss'],
          ),
        ],
      );

      await tester.pumpWidget(
        _HomeHost(
          child: ThemeV2HomePage(
            repository: _FakeHomeRepository(data),
            now: DateTime(2026, 8, 4, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('不应进入 Reka 的待办'), findsNothing);
      expect(find.text('跑步训练还没有记录'), findsOneWidget);
      expect(find.text('提交费用单 已到截止时间'), findsOneWidget);
      expect(find.text('报告生成失败'), findsNothing);
      expect(
        find.byKey(const ValueKey('theme-v2-reka-icon-rhythm_gap')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('theme-v2-reka-icon-overdue')),
        findsOneWidget,
      );
      final first = find.byKey(const ValueKey('theme-v2-reka-row-signal-1'));
      final second = find.byKey(const ValueKey('theme-v2-reka-row-signal-2'));
      expect(tester.getSize(first), tester.getSize(second));
      expect(tester.getSize(first).height, greaterThanOrEqualTo(44));
    },
  );

  testWidgets('overdue action menu completes and removes the signal', (
    tester,
  ) async {
    _setReferenceView(tester);
    final actions = <String>[];
    final data = TodayData(
      chain: const [],
      noTimeTodos: const [],
      pool: const [],
      poolTrueCount: 0,
      flashCount: 0,
      rekaQueue: [
        TodayRekaItem(
          id: 'signal-overdue',
          type: 'overdue',
          title: '提交费用单 已到截止时间',
          body: '仍未完成',
          link: '',
          createdAt: DateTime(2026, 8, 10, 9),
          targetType: 'asset',
          targetId: 'todo-1',
          actions: const ['open', 'complete', 'reschedule', 'dismiss'],
        ),
      ],
    );

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(data),
          now: DateTime(2026, 8, 10, 10),
          onRekaAction: (item, action) async => actions.add(action),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('theme-v2-reka-menu-signal-overdue')),
    );
    await tester.pumpAndSettle();
    expect(find.text('标记完成'), findsOneWidget);
    expect(find.text('调整时间'), findsOneWidget);
    expect(find.text('忽略提醒'), findsOneWidget);

    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();

    expect(actions, ['complete']);
    expect(find.text('提交费用单 已到截止时间'), findsNothing);
    expect(find.text('暂时没有新的发现'), findsOneWidget);
  });

  testWidgets('rhythm signal only offers dismiss beyond its row open action', (
    tester,
  ) async {
    _setReferenceView(tester);
    final data = TodayData(
      chain: const [],
      noTimeTodos: const [],
      pool: const [],
      poolTrueCount: 0,
      flashCount: 0,
      rekaQueue: [
        TodayRekaItem(
          id: 'signal-rhythm',
          type: 'rhythm_gap',
          title: '消费还没有记录',
          body: '可以现在补上一笔',
          link: '',
          createdAt: DateTime(2026, 8, 10, 9),
          targetType: 'skill',
          targetId: 'expense',
          actions: const ['open', 'dismiss'],
        ),
      ],
    );

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: _FakeHomeRepository(data),
          now: DateTime(2026, 8, 10, 10),
          onRekaAction: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('theme-v2-reka-menu-signal-rhythm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('忽略提醒'), findsOneWidget);
    expect(find.text('标记完成'), findsNothing);
    expect(find.text('调整时间'), findsNothing);
  });

  testWidgets('empty Reka exposes report history and creation entry points', (
    tester,
  ) async {
    _setReferenceView(tester);
    var reportsOpened = 0;
    var reportCreated = 0;

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          repository: const _FakeHomeRepository(TodayData.empty),
          now: DateTime(2026, 8, 10),
          onOpenReports: () => reportsOpened++,
          onCreateReport: () => reportCreated++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('查看历史报告'));
    await tester.tap(find.bySemanticsLabel('生成新报告'));

    expect(reportsOpened, 1);
    expect(reportCreated, 1);
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
    expect(find.text('今日共 2 项'), findsOneWidget);
  });

  testWidgets('Agenda remains a bounded document section', (tester) async {
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
    expect(tester.getSize(find.byType(HomeAgendaPanel)).height, 720);
    expect(
      tester.getSize(find.bySemanticsLabel('收起日程')),
      const Size.square(44),
    );
  });

  testWidgets('Agenda uses a chronological grouped timeline at 411x960', (
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

    expect(
      find.byKey(const ValueKey('theme-v2-agenda-scroll')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('theme-v2-agenda-spine')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-agenda-group-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('theme-v2-agenda-group-1')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('theme-v2-agenda-group-0')))
          .dx,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('theme-v2-agenda-time-0')))
            .dx,
      ),
    );
    expect(find.text('今日安排'), findsOneWidget);
    expect(find.text('7月31日 · 周五'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-agenda-generated-chamber')),
      findsNothing,
    );
  });

  testWidgets('Agenda scrolls beyond five groups and keeps every item', (
    tester,
  ) async {
    _setReferenceView(tester);
    final controller = ThemeV2HomeController(
      initialPresentation: HomePresentation.agenda,
    );
    addTearDown(controller.dispose);
    final items = [
      for (var index = 0; index < 7; index++)
        ChainItem(
          kind: index.isEven ? 'event' : 'todo',
          id: 'item-$index',
          title: '安排 $index',
          at: DateTime(2026, 8, 4, 8 + index),
          timed: true,
        ),
    ];

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          controller: controller,
          repository: _FakeHomeRepository(
            TodayData(
              chain: items,
              noTimeTodos: const [],
              pool: const [],
              poolTrueCount: 0,
              flashCount: 0,
            ),
          ),
          now: DateTime(2026, 8, 4, 7),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('theme-v2-agenda-group-6')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('theme-v2-agenda-scroll')),
        matching: find.byType(Scrollable),
      ),
    );

    expect(find.text('安排 6'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-agenda-item-event-item-6')),
      findsOneWidget,
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

    final openAction = find.bySemanticsLabel('打开日程');
    expect(tester.getSize(openAction), const Size.square(44));
    final openRect = tester.getRect(openAction);
    await tester.tap(openAction);
    await tester.pumpAndSettle();
    expect(find.byType(HomeAgendaPanel), findsOneWidget);

    final closeAction = find.bySemanticsLabel('收起日程');
    expect(tester.getSize(closeAction), const Size.square(44));
    expect(tester.getRect(closeAction), openRect);
    await tester.tap(closeAction);
    await tester.pumpAndSettle();
    expect(find.byType(HomeTodayPanel), findsOneWidget);
  });

  testWidgets(
    'Agenda contains only events and todos without todo status copy',
    (tester) async {
      _setReferenceView(tester);
      final controller = ThemeV2HomeController(
        initialPresentation: HomePresentation.agenda,
      );
      addTearDown(controller.dispose);
      final data = TodayData(
        chain: [
          ChainItem(
            kind: 'todo',
            id: 'todo-visible',
            title: '提交费用单',
            at: DateTime(2026, 8, 4, 10, 30),
            timed: true,
          ),
          ChainItem(
            kind: 'note',
            id: 'note-hidden',
            title: '不属于日程的随记',
            at: DateTime(2026, 8, 4, 11),
            timed: true,
          ),
        ],
        noTimeTodos: const [],
        pool: const [],
        poolTrueCount: 0,
        flashCount: 0,
      );

      await tester.pumpWidget(
        _HomeHost(
          child: ThemeV2HomePage(
            controller: controller,
            repository: _FakeHomeRepository(data),
            now: DateTime(2026, 8, 4, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('提交费用单'), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
      expect(find.text('不属于日程的随记'), findsNothing);
      expect(find.text('待处理'), findsNothing);
      expect(find.text('已完成'), findsNothing);
    },
  );

  testWidgets('Agenda event card shows its full time range', (tester) async {
    _setReferenceView(tester);
    final controller = ThemeV2HomeController(
      initialPresentation: HomePresentation.agenda,
    );
    addTearDown(controller.dispose);
    final data = TodayData(
      chain: [
        ChainItem(
          kind: 'event',
          id: 'event-range',
          title: '周会',
          at: DateTime(2026, 8, 6, 15, 30),
          dur: const Duration(minutes: 30),
          timed: true,
          sub: '事件',
        ),
      ],
      noTimeTodos: const [],
      pool: const [],
      poolTrueCount: 0,
      flashCount: 0,
    );

    await tester.pumpWidget(
      _HomeHost(
        child: ThemeV2HomePage(
          controller: controller,
          repository: _FakeHomeRepository(data),
          now: DateTime(2026, 8, 6, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('15:30–16:00'), findsOneWidget);
    expect(find.text('周会'), findsOneWidget);
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
  _setView(tester, const Size(411, 960));
}

void _setView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
  const _HomeHost({
    required this.child,
    this.disableAnimations = true,
    this.size = const Size(411, 960),
  });

  final Widget child;
  final bool disableAnimations;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: 1,
        padding: EdgeInsets.only(top: 44),
        disableAnimations: disableAnimations,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(body: SafeArea(bottom: false, child: child)),
      ),
    );
  }
}
