import 'package:eureka/theme_v2/home/today_output_coordinator.dart';
import 'package:eureka/theme_v2/home/today_dither_material.dart';
import 'package:eureka/theme_v2/home/today_output_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('signal aligns, rises and completes exactly once', (
    tester,
  ) async {
    var completed = 0;
    const item = TodayOutputItem(
      kind: TodayOutputKind.signal,
      id: 'signal-1',
      source: Offset(200, 440),
      reduceMotion: false,
    );
    await tester.pumpWidget(
      _host(TodayOutputOverlay(item: item, onComplete: () => completed++)),
    );

    expect(
      find.byKey(const ValueKey('today-output-signal-signal-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('today-output-signal-trail')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(completed, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
  });

  testWidgets('Reduce Motion reveals then hands off without travel', (
    tester,
  ) async {
    var completed = 0;
    const item = TodayOutputItem(
      kind: TodayOutputKind.asset,
      id: 'asset-1',
      source: Offset(120, 300),
      reduceMotion: true,
    );
    await tester.pumpWidget(
      _host(TodayOutputOverlay(item: item, onComplete: () => completed++)),
    );
    final before = tester.getCenter(
      find.byKey(const ValueKey('today-output-asset-asset-1')),
    );
    await tester.pump(const Duration(milliseconds: 180));
    final after = tester.getCenter(
      find.byKey(const ValueKey('today-output-asset-asset-1')),
    );

    expect(after, before);
    expect(completed, 1);
  });

  testWidgets('output body shares the ambient dither motion', (tester) async {
    const motion = AlwaysStoppedAnimation<double>(.6);
    const item = TodayOutputItem(
      kind: TodayOutputKind.asset,
      id: 'asset-motion',
      source: Offset(120, 300),
      reduceMotion: false,
    );
    await tester.pumpWidget(
      _host(TodayOutputOverlay(item: item, motion: motion, onComplete: () {})),
    );

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('today-output-asset-asset-motion')),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as TodayDitherPainter;
    expect(identical(painter.motion, motion), isTrue);
    expect(painter.flow, greaterThan(0));
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 411, height: 800, child: child)),
);
