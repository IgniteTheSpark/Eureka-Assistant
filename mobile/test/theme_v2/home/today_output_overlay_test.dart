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
    for (var index = 0; index < 3; index++) {
      expect(find.byKey(ValueKey('today-output-trail-$index')), findsOneWidget);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(handoff, isNull);
    expect(completed, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(handoff?.dy, 74);
    await tester.pump(const Duration(milliseconds: 400));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byKey(const ValueKey('today-output-seed')), findsNothing);
    expect(handoff?.dy, 760);
    expect(completed, 1);
  });

  testWidgets(
    'asset ball chooses the left side when Reka is near the right edge',
    (tester) async {
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
            assetVisual: const SizedBox(key: ValueKey('final-asset-ball')),
            onComplete: () {},
          ),
        ),
      );

      expect(
        tester.getCenter(find.byKey(const ValueKey('final-asset-ball'))).dx,
        lessThan(item.source.dx),
      );
      expect(find.byKey(const ValueKey('today-output-seed')), findsNothing);
      expect(find.byKey(const ValueKey('today-output-trail-0')), findsNothing);
    },
  );

  testWidgets('animated Asset hands off visibly inside the chamber floor', (
    tester,
  ) async {
    TodayAssetHandoff? handoff;
    const item = TodayOutputItem(
      kind: TodayOutputKind.asset,
      id: 'asset-visible-handoff',
      source: Offset(180, 300),
      reduceMotion: false,
    );
    await tester.pumpWidget(
      _host(
        TodayOutputOverlay(
          item: item,
          signalBoundaryY: 74,
          assetFloorY: 760,
          assetVisual: const SizedBox(key: ValueKey('final-asset-ball')),
          onAssetHandoff: (value) => handoff = value,
          onComplete: () {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1450));
    expect(handoff, isNull);
    await tester.pump(const Duration(milliseconds: 120));
    expect(handoff?.center.dy, 744);
    expect(handoff?.velocity.dy, greaterThan(0));
  });

  testWidgets('asset paints a final bubble without terminal seed or trail', (
    tester,
  ) async {
    const item = TodayOutputItem(
      kind: TodayOutputKind.asset,
      id: 'asset-final-ball',
      source: Offset(180, 300),
      reduceMotion: false,
    );
    await tester.pumpWidget(
      _host(
        TodayOutputOverlay(
          item: item,
          signalBoundaryY: 74,
          assetFloorY: 760,
          assetVisual: const SizedBox(key: ValueKey('final-asset-ball')),
          onComplete: () {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('final-asset-ball')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-output-seed')), findsNothing);
    expect(find.byKey(const ValueKey('today-output-trail-0')), findsNothing);
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 411, height: 800, child: child)),
);
