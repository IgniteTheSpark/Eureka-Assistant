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
  final now = DateTime(2026, 7, 31, 8, 30);

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
        expect(tester.getTopLeft(dock), const Offset(121, 888));
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
      id: 'event-weekly',
      title: '产品周会',
      at: _eventTime,
      timed: true,
      sub: '项目空间 · 45 分钟',
      domain: 'work',
    ),
  ],
  noTimeTodos: [
    ChainItem(
      kind: 'todo',
      id: 'todo-notes',
      title: '整理用户访谈笔记',
      at: _todoDate,
      timed: false,
      sub: '工作',
      domain: 'work',
    ),
  ],
  pool: [
    PoolAsset(
      id: 'asset-note',
      type: 'note',
      domain: 'work',
      title: '访谈摘录',
      payload: {'content': '访谈摘录'},
      createdAt: _assetTime1,
    ),
    PoolAsset(
      id: 'asset-expense',
      type: 'expense',
      domain: 'life',
      title: '午餐记录',
      payload: {'amount': 42},
      createdAt: _assetTime2,
    ),
    PoolAsset(
      id: 'asset-contact',
      type: 'contact',
      domain: 'social',
      title: '林晓',
      payload: {'name': '林晓'},
      createdAt: _assetTime3,
    ),
  ],
  poolTrueCount: 3,
  flashCount: 2,
  todoDone: 1,
  todoTotal: 3,
);

final _eventTime = DateTime(2026, 7, 31, 10, 30);
final _todoDate = DateTime(2026, 7, 31);
final _assetTime1 = DateTime(2026, 7, 31, 9, 5);
final _assetTime2 = DateTime(2026, 7, 31, 12, 10);
final _assetTime3 = DateTime(2026, 7, 31, 14, 20);

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
