import 'dart:io';

import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_dithered_reka.dart';
import 'package:eureka/theme_v2/home/today_dot_experiment_page.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/home/today_reka_scene.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey<String>('today-reka-experiment-golden');

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

  setUp(() => themeModeNotifier.value = ThemeMode.light);
  tearDown(() => themeModeNotifier.value = ThemeMode.light);

  for (final scenario in _GoldenScenario.values) {
    testWidgets('Today Reka ${scenario.name} light', (tester) async {
      final controller = TodayRekaMotionController();
      addTearDown(controller.dispose);

      await _pumpGolden(
        tester,
        surface: surface,
        scenario: scenario,
        controller: controller,
      );

      expect(find.text('7月31日 · 周五'), findsOneWidget);
      expect(find.text('今天很安静，我在这里。'), findsNothing);
      expect(find.byKey(ThemeV2GlobalTopNav.floatingDockKey), findsOneWidget);
      expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
      expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
      expect(find.byKey(TodayDitheredReka.leftEyeKey), findsOneWidget);
      expect(find.byKey(TodayDitheredReka.rightEyeKey), findsOneWidget);

      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/today-reka-${scenario.fileName}.png'),
      );
    });
  }
}

enum _GoldenScenario { idle, dragging, reduceMotion, tallIdle }

extension on _GoldenScenario {
  Size get size => this == _GoldenScenario.tallIdle
      ? const Size(411, 1080)
      : const Size(411, 960);

  bool get reduceMotion => this == _GoldenScenario.reduceMotion;

  String get fileName => switch (this) {
    _GoldenScenario.idle => 'idle-411-light',
    _GoldenScenario.dragging => 'dragging-411-light',
    _GoldenScenario.reduceMotion => 'reduce-motion-411-light',
    _GoldenScenario.tallIdle => 'idle-411-tall-light',
  };
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required Key surface,
  required _GoldenScenario scenario,
  required TodayRekaMotionController controller,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = scenario.size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  Widget rekaBuilder(
    BuildContext context,
    TodayRekaPose pose,
    bool active,
    bool reduceMotion,
    int refreshSignal,
  ) => TodayDitheredReka(
    pose: pose,
    active: active,
    reduceMotion: reduceMotion,
    refreshSignal: refreshSignal,
    forceFallback: true,
  );

  Widget build() => _GoldenHost(
    size: scenario.size,
    disableAnimations: scenario.reduceMotion,
    child: RepaintBoundary(
      key: surface,
      child: ThemeV2PageScaffold(
        extendBodyBehindChrome: true,
        topNav: const ThemeV2GlobalTopNav(
          floatingDock: true,
          transparentSurface: true,
          deviceStatus: DeviceStatusSummary.disconnected(),
          onDeviceSelected: _noopDeviceTarget,
          onNotificationsPressed: _noop,
        ),
        dock: const ThemeV2FloatingDock(
          selectedIndex: 0,
          onDestinationSelected: _noopIndex,
        ),
        body: TodayDotExperimentPage(
          extendUnderChrome: true,
          now: DateTime(2026, 7, 31),
          active: true,
          rekaController: controller,
          rekaBuilder: rekaBuilder,
        ),
      ),
    ),
  );

  await tester.pumpWidget(build());
  await tester.pump();
  if (scenario == _GoldenScenario.dragging) {
    final start = controller.rekaCenter;
    controller.beginDrag(start);
    controller.updateDrag(
      start + const Offset(92, -36),
      const Duration(milliseconds: 60),
    );
    await tester.pumpWidget(build());
    await tester.pump();
  }
}

class _GoldenHost extends StatelessWidget {
  const _GoldenHost({
    required this.child,
    required this.size,
    required this.disableAnimations,
  });

  final Widget child;
  final Size size;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: const MediaQueryData(
      devicePixelRatio: 1,
      padding: EdgeInsets.only(top: 44),
      platformBrightness: Brightness.light,
      textScaler: TextScaler.noScaling,
    ).copyWith(size: size, disableAnimations: disableAnimations),
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      theme: buildThemeV2Theme(Brightness.light),
      home: child,
    ),
  );
}

void _noop() {}
void _noopIndex(int _) {}
void _noopDeviceTarget(ThemeV2DeviceTarget _) {}
