import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/home/today_reka_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scene uses the standard background and renders only Reka', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TodayRekaScene(
          refreshSignal: 0,
          onRekaTap: (_) {},
          rekaBuilder: _fakeReka,
        ),
      ),
    );

    expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
    expect(find.byKey(TodayRekaScene.rekaRenderKey), findsOneWidget);
    expect(find.text('今天很安静，我在这里。'), findsNothing);
    expect(
      tester.getSize(find.byKey(TodayRekaScene.rekaTargetKey)),
      const Size.square(200),
    );
  });

  testWidgets('scene accepts a deterministic date', (tester) async {
    await tester.pumpWidget(
      _host(
        TodayRekaScene(
          refreshSignal: 0,
          now: DateTime(2026, 7, 31),
          onRekaTap: (_) {},
          rekaBuilder: _fakeReka,
        ),
      ),
    );

    expect(find.text('7月31日 · 周五'), findsOneWidget);
  });

  testWidgets('empty background drag does not move Reka', (tester) async {
    final controller = TodayRekaMotionController();
    await tester.pumpWidget(
      _host(
        TodayRekaScene(
          controller: controller,
          refreshSignal: 0,
          onRekaTap: (_) {},
          rekaBuilder: _fakeReka,
        ),
      ),
    );
    final before = controller.rekaCenter;

    await tester.dragFrom(const Offset(700, 120), const Offset(-90, 80));
    await tester.pump();

    expect(controller.rekaCenter, before);
  });

  testWidgets('drag moves Reka, creates tilt, and does not tap', (
    tester,
  ) async {
    final controller = TodayRekaMotionController();
    var taps = 0;
    await tester.pumpWidget(
      _host(
        TodayRekaScene(
          controller: controller,
          refreshSignal: 0,
          onRekaTap: (_) => taps++,
          rekaBuilder: _fakeReka,
        ),
        disableAnimations: false,
      ),
    );
    final before = controller.rekaCenter;

    await tester.drag(
      find.byKey(TodayRekaScene.rekaTargetKey),
      const Offset(90, -30),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(controller.rekaCenter.dx, greaterThan(before.dx + 40));
    expect(controller.pose.tiltYDegrees, isNot(0));
    expect(taps, 0);
  });

  testWidgets('tap reports the live 200 square global anchor', (tester) async {
    Rect? anchor;
    await tester.pumpWidget(
      _host(
        TodayRekaScene(
          refreshSignal: 0,
          onRekaTap: (value) => anchor = value,
          rekaBuilder: _fakeReka,
        ),
      ),
    );
    final target = find.byKey(TodayRekaScene.rekaTargetKey);

    await tester.tap(target);
    await tester.pump();

    expect(anchor, isNotNull);
    expect(anchor!.center, tester.getCenter(target));
    expect(anchor!.size, const Size.square(200));
  });

  testWidgets('inactive scene cancels an active drag', (tester) async {
    final controller = TodayRekaMotionController();
    Widget build(bool active) => _host(
      TodayRekaScene(
        active: active,
        controller: controller,
        refreshSignal: 0,
        onRekaTap: (_) {},
        rekaBuilder: _fakeReka,
      ),
    );
    await tester.pumpWidget(build(true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(TodayRekaScene.rekaTargetKey)),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(controller.state, TodayRekaMotionState.dragging);

    await tester.pumpWidget(build(false));
    expect(controller.state, TodayRekaMotionState.idle);
    await gesture.cancel();
  });

  testWidgets(
    'inactive scene keeps its last valid layout when chrome shrinks',
    (tester) async {
      final controller = TodayRekaMotionController();
      Widget build({required bool active, required double height}) => _host(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: height,
            child: TodayRekaScene(
              active: active,
              controller: controller,
              topChromeInset: 76,
              bottomChromeInset: 80,
              refreshSignal: 0,
              onRekaTap: (_) {},
              rekaBuilder: _fakeReka,
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(active: true, height: 600));
      final validBounds = controller.safeBounds;

      await tester.pumpWidget(build(active: false, height: 464));

      expect(tester.takeException(), isNull);
      expect(controller.safeBounds, validBounds);
    },
  );

  testWidgets('idle animation does not run a Flutter scene ticker', (
    tester,
  ) async {
    var builds = 0;
    Widget builder(
      BuildContext context,
      TodayRekaPose pose,
      bool active,
      bool reduceMotion,
      int refreshSignal,
    ) {
      builds++;
      return const SizedBox.expand();
    }

    await tester.pumpWidget(
      _host(
        TodayRekaScene(
          refreshSignal: 0,
          onRekaTap: (_) {},
          rekaBuilder: builder,
        ),
        disableAnimations: false,
      ),
    );
    final afterLayout = builds;
    await tester.pump(const Duration(seconds: 1));

    expect(builds, afterLayout);
  });
}

Widget _fakeReka(
  BuildContext context,
  TodayRekaPose pose,
  bool active,
  bool reduceMotion,
  int refreshSignal,
) => const SizedBox.expand();

Widget _host(Widget child, {bool disableAnimations = true}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(411, 860),
      devicePixelRatio: 1,
      disableAnimations: disableAnimations,
      textScaler: TextScaler.noScaling,
    ),
    child: Scaffold(body: child),
  ),
);
