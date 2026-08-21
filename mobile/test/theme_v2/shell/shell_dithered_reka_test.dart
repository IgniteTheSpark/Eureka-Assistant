import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_dithered_reka.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/shell/shell_dithered_reka.dart';
import 'package:eureka/theme_v2/shell/shell_reka_presentation_controller.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('position duration only animates an active root handoff', () {
    expect(
      shellRekaPositionDuration(reduceMotion: false, handoffActive: false),
      Duration.zero,
    );
    expect(
      shellRekaPositionDuration(reduceMotion: false, handoffActive: true),
      ShellDitheredReka.transitionDuration,
    );
    expect(
      shellRekaPositionDuration(reduceMotion: true, handoffActive: true),
      Duration.zero,
    );
  });

  testWidgets('Today visual follows controller drag in one frame', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.motion.layout(
      const Size(400, 700),
      reservedInsets: const EdgeInsets.all(4),
    );
    await tester.pumpWidget(
      _host(harness.child(mode: ShellDitheredRekaMode.today)),
    );
    final before = tester.getCenter(find.byKey(ShellDitheredReka.visualKey));
    final start = harness.motion.rekaCenter;

    harness.motion.beginDrag(start);
    harness.motion.updateDrag(
      start + const Offset(90, -30),
      const Duration(milliseconds: 16),
    );
    await tester.pump();

    final after = tester.getCenter(find.byKey(ShellDitheredReka.visualKey));
    expect(after.dx - before.dx, closeTo(90, .01));
    expect(after.dy - before.dy, closeTo(-30, .01));
  });

  testWidgets('Dock mode floats one dither renderer without changing Dock', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(_host(harness.child()));

    expect(find.byType(TodayDitheredReka), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ShellDitheredReka.visibleBoundsKey)),
      ShellDitheredReka.dockVisibleSize,
    );
    expect(
      tester.getSize(find.byKey(ShellDitheredReka.targetKey)),
      const Size.square(ShellDitheredReka.targetExtent),
    );
    final dockTop = tester
        .getTopLeft(find.byKey(ThemeV2FloatingDock.dockKey))
        .dy;
    final rekaBottom = tester
        .getBottomLeft(find.byKey(ShellDitheredReka.visibleBoundsKey))
        .dy;
    expect(rekaBottom - dockTop, closeTo(15, .01));
  });

  testWidgets('Dock breathing pauses with app lifecycle', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(_host(harness.child()));

    final initial = _breathingTransform(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_breathingTransform(tester), isNot(initial));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = _breathingTransform(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_breathingTransform(tester), paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('reduce motion keeps Dock breathing transform fixed', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(_host(harness.child(), disableAnimations: true));

    final initial = _breathingTransform(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_breathingTransform(tester), initial);
  });
}

Matrix4 _breathingTransform(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(ShellDitheredReka.breathingTransformKey))
    .transform;

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 700),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(body: SizedBox(width: 400, height: 700, child: child)),
  ),
);

class _Harness {
  final TodayRekaMotionController motion = TodayRekaMotionController();
  final ShellRekaPresentationController presentation =
      ShellRekaPresentationController();

  Widget child({ShellDitheredRekaMode mode = ShellDitheredRekaMode.dock}) =>
      Stack(
        children: [
          ThemeV2FloatingDock(selectedIndex: 1, onDestinationSelected: (_) {}),
          Positioned.fill(
            child: ShellDitheredReka(
              mode: mode,
              motionController: motion,
              presentationController: presentation,
              onTap: (_) {},
              onLongPressStart: () {},
              onLongPressMove: (_) {},
              onLongPressEnd: () {},
              onLongPressCancel: () {},
            ),
          ),
        ],
      );

  void dispose() {
    motion.dispose();
    presentation.dispose();
  }
}
