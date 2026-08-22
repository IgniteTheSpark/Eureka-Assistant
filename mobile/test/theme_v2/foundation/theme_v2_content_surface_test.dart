import 'package:eureka/theme_v2/foundation/theme_v2_content_surface.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dense content surface uses a high-opacity reading layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const ThemeV2ContentSurface(
          opacity: ThemeV2ContentOpacity.dense,
          child: Text('清晰内容'),
        ),
      ),
    );

    final box = tester.widget<ColoredBox>(find.byType(ColoredBox).last);
    expect(box.color.a, greaterThanOrEqualTo(.95));
  });
}
