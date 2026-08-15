import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/theme_v2/home/today_dithered_reka.dart';
import 'package:eureka/theme_v2/home/today_output_coordinator.dart';
import 'package:eureka/theme_v2/home/today_reka_capture_cue.dart';
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

  test('capture actions use distinct old-school terminal eye patterns', () {
    final signatures = <String>{};
    for (final action in TodayRekaCaptureAction.values) {
      final left = todayRekaEyePattern(action, left: true).join(',');
      final right = todayRekaEyePattern(action, left: false).join(',');
      signatures.add('$left|$right');
    }

    expect(signatures, hasLength(TodayRekaCaptureAction.values.length));
    expect(
      todayRekaEyePattern(TodayRekaCaptureAction.failed, left: true),
      isNot(todayRekaEyePattern(TodayRekaCaptureAction.failed, left: false)),
    );
  });

  testWidgets('capture changes fallback eyes without taking drag transform', (
    tester,
  ) async {
    const draggingPose = TodayRekaPose(
      state: TodayRekaMotionState.dragging,
      tiltXDegrees: -6,
      tiltYDegrees: 8,
    );
    Widget reka(TodayRekaCaptureCue captureCue) => MaterialApp(
      home: Center(
        child: TodayDitheredReka(
          pose: draggingPose,
          active: true,
          reduceMotion: false,
          refreshSignal: 0,
          captureCue: captureCue,
          forceFallback: true,
        ),
      ),
    );

    await tester.pumpWidget(reka(const TodayRekaCaptureCue.idle()));
    final idleTransform = List<double>.of(
      tester
          .widget<Transform>(find.byKey(TodayDitheredReka.fallbackKey))
          .transform
          .storage,
    );
    final idlePixels = find
        .descendant(
          of: find.byKey(TodayDitheredReka.leftEyeKey),
          matching: find.byType(ColoredBox),
        )
        .evaluate()
        .length;

    await tester.pumpWidget(
      reka(
        const TodayRekaCaptureCue(action: TodayRekaCaptureAction.understanding),
      ),
    );

    expect(
      tester
          .widget<Transform>(find.byKey(TodayDitheredReka.fallbackKey))
          .transform
          .storage,
      orderedEquals(idleTransform),
    );
    expect(
      find
          .descendant(
            of: find.byKey(TodayDitheredReka.leftEyeKey),
            matching: find.byType(ColoredBox),
          )
          .evaluate()
          .length,
      isNot(idlePixels),
    );
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
      const Size.square(288),
    );
    final eyePixel = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byKey(TodayDitheredReka.leftEyeKey),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(eyePixel.color, const Color(0xFF78FF74));
  });

  testWidgets('fallback eyes look upward while emitting a Signal', (
    tester,
  ) async {
    Widget reka(TodayOutputCue cue) => MaterialApp(
      home: Center(
        child: TodayDitheredReka(
          pose: idlePose,
          active: true,
          reduceMotion: false,
          refreshSignal: 0,
          cue: cue,
          forceFallback: true,
        ),
      ),
    );

    await tester.pumpWidget(reka(const TodayOutputCue.idle()));
    final idle = tester.getCenter(find.byKey(TodayDitheredReka.leftEyeKey));
    await tester.pumpWidget(
      reka(
        const TodayOutputCue(
          phase: TodayOutputPhase.emit,
          kind: TodayOutputKind.signal,
          id: 'signal-1',
        ),
      ),
    );

    expect(
      tester.getCenter(find.byKey(TodayDitheredReka.leftEyeKey)).dy,
      lessThan(idle.dy),
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
