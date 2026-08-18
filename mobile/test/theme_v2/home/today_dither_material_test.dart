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

  testWidgets('region watermark supports opposite anchors without callbacks', (
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
    final discoveryLabel = tester.widget<Text>(find.text('Reka 发现'));
    expect(discoveryLabel.style?.fontSize, greaterThanOrEqualTo(14));
    expect(discoveryLabel.style?.fontWeight, FontWeight.w700);
    expect(discoveryLabel.style?.color?.a, greaterThanOrEqualTo(.56));
    expect(
      tester.getCenter(find.text('Reka 发现')).dx,
      lessThan(tester.getCenter(find.text('Reka 生成')).dx),
    );
    expect(find.bySemanticsLabel('查看全部 Reka 发现'), findsNothing);
    expect(find.bySemanticsLabel('打开资产库'), findsNothing);
  });

  testWidgets('zero-count region watermark remains visible and clickable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: TodayRegionWatermark(
          count: 0,
          label: 'Reka 发现',
          alignment: Alignment.bottomLeft,
          onPressed: () => taps++,
          semanticLabel: '查看全部 Reka 发现',
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('Reka 发现'), findsOneWidget);
    expect(find.bySemanticsLabel('查看全部 Reka 发现'), findsOneWidget);
    final target = find.ancestor(
      of: find.text('Reka 发现'),
      matching: find.byType(GestureDetector),
    );
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).width, lessThan(160));
    await tester.tap(find.text('Reka 发现'));
    expect(taps, 1);
  });

  testWidgets('region watermark keeps contrast in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.dark),
        home: const TodayRegionWatermark(
          count: 0,
          label: 'Reka 生成',
          alignment: Alignment.bottomRight,
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Reka 生成'));
    expect(label.style?.fontSize, greaterThanOrEqualTo(14));
    expect(label.style?.fontWeight, FontWeight.w700);
    expect(label.style?.color?.a, greaterThanOrEqualTo(.72));
  });

  testWidgets('region watermark count and label share one entry', (
    tester,
  ) async {
    var openCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: TodayRegionWatermark(
            count: 12,
            label: 'Reka 生成',
            alignment: Alignment.topRight,
            onPressed: () => openCalls++,
            semanticLabel: '打开资产库',
          ),
        ),
      ),
    );

    await tester.tap(find.text('12'));
    expect(openCalls, 1);

    await tester.tap(find.text('Reka 生成'));
    expect(openCalls, 2);

    await tester.tapAt(
      tester.getCenter(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 7,
        ),
      ),
    );
    expect(openCalls, 3);
  });

  testWidgets(
    'region watermark preserves positive counts and normalizes only negatives',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildThemeV2Theme(Brightness.light),
          home: const Column(
            children: [
              TodayRegionWatermark(
                count: -4,
                label: 'Reka 发现',
                alignment: Alignment.topLeft,
              ),
              TodayRegionWatermark(
                count: 1000,
                label: 'Reka 生成',
                alignment: Alignment.topRight,
              ),
            ],
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    },
  );

  testWidgets('region watermark can keep its label before the count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(
          body: TodayRegionWatermark(
            count: 12,
            label: 'Reka 生成',
            alignment: Alignment.topRight,
            labelFirst: true,
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Reka 生成')).dy,
      lessThan(tester.getTopLeft(find.text('12')).dy),
    );
  });

  testWidgets('opposite watermark labels keep equal visual seam gaps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const Scaffold(
          body: SizedBox(
            width: 360,
            height: 300,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 150,
                  child: TodayRegionWatermark(
                    count: 1,
                    label: 'Reka 发现',
                    alignment: Alignment.bottomLeft,
                    padding: EdgeInsets.only(bottom: 8),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 150,
                  height: 150,
                  child: TodayRegionWatermark(
                    count: 1,
                    label: 'Reka 生成',
                    alignment: Alignment.topRight,
                    padding: EdgeInsets.only(top: 8),
                    labelFirst: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final discoveryGap = 150 - tester.getBottomRight(find.text('Reka 发现')).dy;
    final generationGap = tester.getTopLeft(find.text('Reka 生成')).dy - 150;
    expect(discoveryGap, closeTo(generationGap, .1));
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
