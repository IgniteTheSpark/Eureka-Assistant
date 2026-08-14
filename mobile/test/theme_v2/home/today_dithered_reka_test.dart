import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/theme_v2/home/today_dithered_reka.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';

void main() {
  const idlePose = TodayRekaPose(
    state: TodayRekaMotionState.idle,
    tiltXDegrees: 0,
    tiltYDegrees: 0,
  );

  test('local HTML assembly replaces every renderer marker', () {
    final html = buildRekaHtml(
      template:
          'const three=/*__THREE_SOURCE_JSON__*/;'
          '/*__ENGINE_SOURCE__*/'
          'init(/*__OPTIONS_JSON__*/);',
      threeSource: 'export const quote = "Reka";',
      engineSource: 'window.RekaRenderer = {};',
      options: const {'gridSize': 4, 'reduceMotion': true},
    );

    expect(html, contains(r'\"Reka\"'));
    expect(html, contains('window.RekaRenderer = {};'));
    expect(html, contains('"gridSize":4'));
    expect(html, isNot(contains('/*__')));
  });

  testWidgets('forced fallback keeps the approved head and permanent eyes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: TodayDitheredReka(
            pose: idlePose,
            active: true,
            reduceMotion: false,
            refreshSignal: 0,
            forceFallback: true,
          ),
        ),
      ),
    );

    expect(find.byKey(TodayDitheredReka.fallbackKey), findsOneWidget);
    expect(find.byKey(TodayDitheredReka.leftEyeKey), findsOneWidget);
    expect(find.byKey(TodayDitheredReka.rightEyeKey), findsOneWidget);
    expect(
      tester.getSize(find.byType(TodayDitheredReka)),
      const Size.square(216),
    );
  });

  testWidgets('fallback eyes remain visible while dragging', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: TodayDitheredReka(
            pose: TodayRekaPose(
              state: TodayRekaMotionState.dragging,
              tiltXDegrees: -6,
              tiltYDegrees: 8,
            ),
            active: true,
            reduceMotion: false,
            refreshSignal: 1,
            forceFallback: true,
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byKey(TodayDitheredReka.leftEyeKey),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
    expect(find.byKey(TodayDitheredReka.rightEyeKey), findsOneWidget);
  });

  testWidgets('renderer content is excluded from semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: TodayDitheredReka(
          pose: idlePose,
          active: true,
          reduceMotion: true,
          refreshSignal: 0,
          forceFallback: true,
        ),
      ),
    );

    expect(find.bySemanticsLabel('Reka 快捷操作，可拖动'), findsNothing);
    semantics.dispose();
  });
}
