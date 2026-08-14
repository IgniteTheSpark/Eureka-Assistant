import 'package:eureka/theme_v2/home/today_dither_material.dart';
import 'package:eureka/theme_v2/home/today_region_watermark.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bayer threshold output is deterministic', () {
    expect(
      [
        for (var y = 0; y < 4; y++)
          for (var x = 0; x < 4; x++) bayer4(x, y),
      ],
      [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5],
    );
    expect(bayer4(0, 0), bayer4(4, 4));
  });

  test('circle and strip masks keep their intended silhouettes', () {
    const size = Size(100, 60);
    const circle = TodayDitherPainter(
      shape: TodayDitherShape.circle,
      color: Colors.black,
      strength: .8,
    );
    const strip = TodayDitherPainter(
      shape: TodayDitherShape.strip,
      color: Colors.black,
      strength: .8,
    );

    expect(circle.coverageAt(size, const Offset(50, 30)), greaterThan(0));
    expect(circle.coverageAt(size, Offset.zero), 0);
    expect(strip.coverageAt(size, const Offset(50, 30)), greaterThan(0));
    expect(strip.coverageAt(size, Offset.zero), 0);
  });

  test(
    'identity seed offsets Dither drift without changing a static field',
    () {
      expect(
        todayDitherDrift(seed: 1, phase: .25, flow: 1),
        isNot(equals(todayDitherDrift(seed: 2, phase: .25, flow: 1))),
      );
      expect(todayDitherDrift(seed: 1, phase: .25, flow: 0), Offset.zero);
    },
  );

  testWidgets('region watermark is decorative and supports opposite anchors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: Stack(
            children: const [
              TodayRegionWatermark(
                count: 5,
                label: 'Reka 发现',
                alignment: Alignment.bottomLeft,
              ),
              TodayRegionWatermark(
                count: 12,
                label: 'Reka 生成',
                alignment: Alignment.bottomRight,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Reka 发现'), findsOneWidget);
    expect(find.text('Reka 生成'), findsOneWidget);
    final discoveryIgnores = tester
        .widgetList<IgnorePointer>(
          find.ancestor(
            of: find.text('Reka 发现'),
            matching: find.byType(IgnorePointer),
          ),
        )
        .where((widget) => widget.ignoring);
    final generationIgnores = tester
        .widgetList<IgnorePointer>(
          find.ancestor(
            of: find.text('Reka 生成'),
            matching: find.byType(IgnorePointer),
          ),
        )
        .where((widget) => widget.ignoring);
    expect(discoveryIgnores, hasLength(1));
    expect(generationIgnores, hasLength(1));
  });

  testWidgets('zero-count region watermark collapses', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const TodayRegionWatermark(
          count: 0,
          label: 'Reka 发现',
          alignment: Alignment.bottomLeft,
        ),
      ),
    );

    expect(find.text('0'), findsNothing);
    expect(find.text('Reka 发现'), findsNothing);
  });

  testWidgets('dither material keeps its overlay crisp and semantic', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 88,
              child: TodayDitherMaterial(
                shape: TodayDitherShape.strip,
                color: Colors.black,
                strength: .7,
                child: Text('报告方案已准备好'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('报告方案已准备好'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.widget<Text>(find.text('报告方案已准备好')).data, '报告方案已准备好');
  });
}
