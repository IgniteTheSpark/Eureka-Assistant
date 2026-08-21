import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('circle pressure expands beyond its resting feather with energy', () {
    const resting = ThemeV2DitherSource.circle(
      center: Offset(40, 40),
      radius: 20,
    );
    const moving = ThemeV2DitherSource.circle(
      center: Offset(40, 40),
      radius: 20,
      energy: .7,
    );

    expect(
      themeV2DitherPressureAt(const Offset(40, 40), moving),
      greaterThan(.9),
    );
    expect(themeV2DitherPressureAt(const Offset(80, 40), resting), 0);
    expect(
      themeV2DitherPressureAt(const Offset(80, 40), moving),
      greaterThan(.1),
    );
  });

  test('capsule pressure covers its body but not its exterior', () {
    const source = ThemeV2DitherSource.capsule(
      center: Offset(120, 30),
      size: Size(180, 48),
      energy: .2,
    );

    expect(
      themeV2DitherPressureAt(const Offset(60, 30), source),
      greaterThan(.8),
    );
    expect(themeV2DitherPressureAt(const Offset(120, 80), source), 0);
  });

  test('signal and asset fields use independent flow vectors', () {
    expect(
      const ThemeV2DitherFieldConfig.signal().flowDirection,
      const Offset(1, .08),
    );
    expect(
      const ThemeV2DitherFieldConfig.asset().flowDirection,
      const Offset(.1, 1),
    );
    expect(
      const ThemeV2DitherFieldConfig.signal().waveSpeed,
      greaterThan(const ThemeV2DitherFieldConfig.asset().waveSpeed),
    );
  });

  testWidgets('field keeps the shader surface non-interactive', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: ThemeV2DitherField(
            key: ValueKey('field'),
            config: ThemeV2DitherFieldConfig.signal(),
            sources: [
              ThemeV2DitherSource.capsule(
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
