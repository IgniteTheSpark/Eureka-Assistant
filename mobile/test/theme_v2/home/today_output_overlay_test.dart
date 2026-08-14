import 'package:eureka/theme_v2/home/today_output_coordinator.dart';
import 'package:eureka/theme_v2/home/today_output_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('signal aligns, rises and completes exactly once', (
    tester,
  ) async {
    var completed = 0;
    Offset? handoff;
    final phases = <TodayOutputPhase>[];
    const item = TodayOutputItem(
      kind: TodayOutputKind.signal,
      id: 'signal-1',
      source: Offset(200, 440),
      reduceMotion: false,
    );
    await tester.pumpWidget(
      _host(
        TodayOutputOverlay(
          item: item,
          signalBoundaryY: 74,
          assetFloorY: 760,
          onPhaseChanged: phases.add,
          onHandoff: (point) => handoff = point,
          onComplete: () => completed++,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('today-output-seed')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today-output-signal-trail')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 760));
    await tester.pump();
    expect(completed, 1);
    expect(handoff?.dy, 74);
    expect(
      phases,
      containsAllInOrder([
        TodayOutputPhase.charge,
        TodayOutputPhase.emit,
        TodayOutputPhase.handoff,
        TodayOutputPhase.recover,
      ]),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
  });

  testWidgets('Reduce Motion reveals then hands off without travel', (
    tester,
  ) async {
    var completed = 0;
    Offset? handoff;
    const item = TodayOutputItem(
      kind: TodayOutputKind.asset,
      id: 'asset-1',
      source: Offset(120, 300),
      reduceMotion: true,
    );
    await tester.pumpWidget(
      _host(
        TodayOutputOverlay(
          item: item,
          signalBoundaryY: 74,
          assetFloorY: 760,
          onHandoff: (point) => handoff = point,
          onComplete: () => completed++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byKey(const ValueKey('today-output-seed')), findsNothing);
    expect(handoff?.dy, 760);
    expect(completed, 1);
  });

  testWidgets('seed chooses the left side when Reka is near the right edge', (
    tester,
  ) async {
    const item = TodayOutputItem(
      kind: TodayOutputKind.asset,
      id: 'asset-motion',
      source: Offset(350, 300),
      reduceMotion: false,
    );
    await tester.pumpWidget(
      _host(
        TodayOutputOverlay(
          item: item,
          side: TodayOutputSide.left,
          signalBoundaryY: 74,
          assetFloorY: 760,
          onComplete: () {},
        ),
      ),
    );

    expect(
      tester.getCenter(find.byKey(const ValueKey('today-output-seed'))).dx,
      lessThan(item.source.dx),
    );
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 411, height: 800, child: child)),
);
