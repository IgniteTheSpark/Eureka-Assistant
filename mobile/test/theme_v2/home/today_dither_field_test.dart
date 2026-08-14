import 'package:eureka/theme_v2/home/today_dither_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('circle pressure is strongest at center and zero outside feather', () {
    const source = TodayDitherSource.circle(
      center: Offset(40, 40),
      radius: 20,
      energy: .7,
    );

    expect(
      todayDitherPressureAt(const Offset(40, 40), source),
      greaterThan(.9),
    );
    expect(todayDitherPressureAt(const Offset(80, 40), source), 0);
  });

  test('capsule pressure covers its body but not its exterior', () {
    const source = TodayDitherSource.capsule(
      center: Offset(120, 30),
      size: Size(180, 48),
      energy: .2,
    );

    expect(
      todayDitherPressureAt(const Offset(60, 30), source),
      greaterThan(.8),
    );
    expect(todayDitherPressureAt(const Offset(120, 80), source), 0);
  });

  test('signal and asset fields use independent flow vectors', () {
    expect(
      const TodayDitherFieldConfig.signal().flowDirection,
      const Offset(1, .08),
    );
    expect(
      const TodayDitherFieldConfig.asset().flowDirection,
      const Offset(.1, 1),
    );
    expect(
      const TodayDitherFieldConfig.signal().waveSpeed,
      greaterThan(const TodayDitherFieldConfig.asset().waveSpeed),
    );
  });

  testWidgets('field keeps the shader surface non-interactive', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: TodayDitherField(
            key: ValueKey('field'),
            config: TodayDitherFieldConfig.signal(),
            sources: [
              TodayDitherSource.capsule(
                center: Offset(120, 60),
                size: Size(180, 48),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('field')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('field')),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });
}
