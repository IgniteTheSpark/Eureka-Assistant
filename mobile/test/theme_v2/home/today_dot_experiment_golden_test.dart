import 'dart:io';

import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_dot_experiment_page.dart';
import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:eureka/theme_v2/home/today_dot_field_simulation.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey<String>('today-dot-experiment-golden');
  const size = Size(411, 960);

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

  for (final state in _GoldenState.values) {
    testWidgets('Today dot experiment ${state.name} light 411', (tester) async {
      final controller = TodayDotFieldController();
      final simulation = TodayDotFieldSimulation();
      addTearDown(controller.dispose);

      await _pumpGolden(
        tester,
        surface: surface,
        size: size,
        controller: controller,
        simulation: simulation,
        state: state,
      );

      expect(find.text('7月31日 · 周五'), findsOneWidget);
      expect(find.text('今天很安静，我在这里。'), findsOneWidget);
      expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/today-dot-${state.fileName}-411-light.png'),
      );
    });
  }

  testWidgets('Today dot experiment exhale tall light 411', (tester) async {
    const tallSize = Size(411, 1080);
    final controller = TodayDotFieldController();
    final simulation = TodayDotFieldSimulation();
    addTearDown(controller.dispose);

    await _pumpGolden(
      tester,
      surface: surface,
      size: tallSize,
      controller: controller,
      simulation: simulation,
      state: _GoldenState.exhale,
    );

    await expectLater(
      find.byKey(surface),
      matchesGoldenFile('goldens/today-dot-idle-411-tall-light.png'),
    );
  });
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
  Widget build(BuildContext context) {
    return MediaQuery(
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
}

enum _GoldenState { inhale, exhale, dragging, settling, reduceMotion }

extension on _GoldenState {
  String get fileName => switch (this) {
    _GoldenState.exhale => 'exhale-eyes',
    _GoldenState.dragging => 'drag',
    _GoldenState.reduceMotion => 'reduce-motion',
    _ => name,
  };
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required Key surface,
  required Size size,
  required TodayDotFieldController controller,
  required TodayDotFieldSimulation simulation,
  required _GoldenState state,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  Widget build() => _GoldenHost(
    size: size,
    disableAnimations: state == _GoldenState.reduceMotion,
    child: RepaintBoundary(
      key: surface,
      child: ThemeV2PageScaffold(
        topNav: const ThemeV2GlobalTopNav(
          deviceStatus: DeviceStatusSummary.disconnected(),
          onDeviceSelected: _noopDeviceTarget,
          onNotificationsPressed: _noop,
        ),
        dock: const ThemeV2FloatingDock(
          selectedIndex: 0,
          onDestinationSelected: _noopIndex,
        ),
        body: TodayDotExperimentPage(
          now: DateTime(2026, 7, 31),
          active: false,
          sceneController: controller,
          sceneSimulation: simulation,
        ),
      ),
    ),
  );

  await tester.pumpWidget(build());
  await tester.pump();
  _configureState(controller, simulation, state);
  await tester.pumpWidget(build());
  await tester.pump();
}

void _configureState(
  TodayDotFieldController controller,
  TodayDotFieldSimulation simulation,
  _GoldenState state,
) {
  switch (state) {
    case _GoldenState.inhale:
      controller.debugSetBreathPhase(0);
      controller.step(0, reduceMotion: false);
      _settleDots(controller, simulation, frames: 8);
      break;
    case _GoldenState.exhale:
      controller.debugSetBreathPhase(.76);
      controller.step(0, reduceMotion: false);
      _settleDots(controller, simulation, frames: 28);
      break;
    case _GoldenState.dragging:
      final start = controller.rekaCenter;
      controller.beginDrag(start);
      controller.updateDrag(
        start + const Offset(92, -36),
        const Duration(milliseconds: 60),
      );
      _settleDots(controller, simulation, frames: 18);
      break;
    case _GoldenState.settling:
      final start = controller.rekaCenter;
      controller.beginDrag(start);
      controller.updateDrag(
        start + const Offset(92, -36),
        const Duration(milliseconds: 60),
      );
      controller.endDrag();
      _settleDots(controller, simulation, frames: 6, advanceController: true);
      break;
    case _GoldenState.reduceMotion:
      controller.step(0, reduceMotion: true);
      simulation.step(
        0,
        rekaCenter: controller.rekaCenter,
        state: controller.state,
        dragEngagement: controller.dragEngagement,
        breathAmount: controller.breathAmount,
        fieldPhase: controller.breathPhase,
        reduceMotion: true,
      );
      break;
  }
}

void _settleDots(
  TodayDotFieldController controller,
  TodayDotFieldSimulation simulation, {
  required int frames,
  bool advanceController = false,
}) {
  for (var frame = 0; frame < frames; frame++) {
    if (advanceController) controller.step(1 / 60, reduceMotion: false);
    simulation.step(
      1 / 60,
      rekaCenter: controller.rekaCenter,
      state: controller.state,
      dragEngagement: controller.dragEngagement,
      breathAmount: controller.breathAmount,
      fieldPhase: controller.breathPhase,
      reduceMotion: false,
    );
  }
}

void _noop() {}
void _noopDeviceTarget(ThemeV2DeviceTarget _) {}
void _noopIndex(int _) {}
