import 'dart:io';

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/home_controller.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/home/theme_v2_home_page.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey('home-golden-surface');
  const size = Size(411, 960);
  final now = DateTime(2026, 7, 31, 14, 18);

  setUpAll(() async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'))).load();
    await (FontLoader('Geist Mono')..addFont(
          rootBundle.load('assets/fonts/GeistMono/GeistMono-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    if (pingFang.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(pingFang.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final presentation in HomePresentation.values) {
      final mode = brightness == Brightness.light ? 'light' : 'dark';
      final state = presentation == HomePresentation.today ? 'today' : 'agenda';

      testWidgets('Home $state 411 $mode', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final controller = ThemeV2HomeController(
          initialPresentation: presentation,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _GoldenHomeHost(
            brightness: brightness,
            child: RepaintBoundary(
              key: surface,
              child: ThemeV2PageScaffold(
                showTopNav: false,
                body: ThemeV2HomePage(
                  controller: controller,
                  repository: _FakeHomeRepository(_homeFixture),
                  now: now,
                ),
                dock: const ThemeV2FloatingDock(
                  selectedIndex: 0,
                  onDestinationSelected: _noopIndex,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final panel = find.byKey(ThemeV2HomePage.panelKey);
        expect(tester.getTopLeft(panel), const Offset(8, 54));
        expect(tester.getSize(panel), const Size(395, 790));
        expect(find.text('目标'), findsNothing);
        final dock = find.byKey(ThemeV2FloatingDock.dockKey);
        expect(dock, findsOneWidget);
        expect(tester.getTopLeft(dock), const Offset(121, 865));
        expect(tester.getSize(dock), const Size(169, 60));

        await expectLater(
          find.byKey(surface),
          matchesGoldenFile('goldens/home-$state-411-$mode.png'),
        );
      });
    }
  }
}

final _homeFixture = TodayData(
  chain: [
    ChainItem(
      kind: 'event',
      id: 'event-review',
      title: '线上复盘会',
      at: DateTime(2026, 7, 31, 9),
      timed: true,
      sub: '视频会议',
      domain: 'work',
      dur: const Duration(minutes: 45),
      done: true,
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-expense',
      title: '提交费用单',
      at: DateTime(2026, 7, 31, 10, 30),
      timed: true,
      sub: '财务',
      domain: 'work',
      done: true,
    ),
    ChainItem(
      kind: 'event',
      id: 'event-lunch',
      title: '午餐与散步',
      at: DateTime(2026, 7, 31, 12),
      timed: true,
      sub: '生活',
      domain: 'life',
      dur: const Duration(minutes: 45),
      done: true,
    ),
    ChainItem(
      kind: 'event',
      id: 'event-client',
      title: '客户需求拜访',
      at: DateTime(2026, 7, 31, 15),
      timed: true,
      sub: '线下拜访',
      domain: 'work',
      dur: const Duration(hours: 1),
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-training',
      title: '培训',
      at: DateTime(2026, 7, 31, 15),
      timed: true,
      sub: '待办',
      domain: 'work',
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-materials',
      title: '提交材料',
      at: DateTime(2026, 7, 31, 15),
      timed: true,
      sub: '待办',
      domain: 'work',
    ),
    ChainItem(
      kind: 'event',
      id: 'event-interview',
      title: '线上面试',
      at: DateTime(2026, 7, 31, 20),
      timed: true,
      sub: '视频会议',
      domain: 'work',
      dur: const Duration(minutes: 45),
    ),
  ],
  noTimeTodos: [
    ChainItem(
      kind: 'todo',
      id: 'todo-brief',
      title: '会前简报已经准备好',
      at: DateTime(2026, 7, 31),
      timed: false,
      sub: '14:00 · 客户需求拜访',
      domain: 'work',
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-flashes',
      title: '9 条闪念可以整理为一个新主题',
      at: DateTime(2026, 7, 31),
      timed: false,
      sub: '灵感整理',
      domain: 'work',
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-questions',
      title: '更新产品问题清单',
      at: DateTime(2026, 7, 31),
      timed: false,
      sub: '工作',
      domain: 'work',
    ),
    ChainItem(
      kind: 'todo',
      id: 'todo-notes',
      title: '整理用户访谈笔记',
      at: DateTime(2026, 7, 31),
      timed: false,
      sub: '研究',
      domain: 'work',
    ),
  ],
  pool: List<PoolAsset>.generate(22, (index) {
    const types = [
      'idea',
      'event',
      'todo',
      'book',
      'expense',
      'note',
      'contact',
      'location',
      'audio',
      'image',
    ];
    return PoolAsset(
      id: 'asset-$index',
      type: types[index % types.length],
      domain: index.isEven ? 'work' : 'life',
      title: '今日资产 ${index + 1}',
      payload: {'content': '今日资产 ${index + 1}'},
      createdAt: DateTime(2026, 7, 31, 8, index),
    );
  }),
  poolTrueCount: 29,
  flashCount: 9,
  todoDone: 2,
  todoTotal: 5,
);

void _noopIndex(int _) {}

class _FakeHomeRepository implements ThemeV2HomeRepository {
  const _FakeHomeRepository(this.value);

  final TodayData value;

  @override
  Future<TodayData> load() async => value;
}

class _GoldenHomeHost extends StatelessWidget {
  const _GoldenHomeHost({required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(411, 960),
        devicePixelRatio: 1,
        padding: const EdgeInsets.only(top: 44),
        platformBrightness: brightness,
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        theme: buildThemeV2Theme(Brightness.light),
        darkTheme: buildThemeV2Theme(Brightness.dark),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: child,
      ),
    );
  }
}
