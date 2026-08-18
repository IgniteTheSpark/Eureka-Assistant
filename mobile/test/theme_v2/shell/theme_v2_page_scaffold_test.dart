import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page scaffold owns one dither behind body and chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const ThemeV2PageScaffold(
          body: SizedBox.expand(key: ValueKey('test-body')),
          topNav: SizedBox(height: 56, key: ValueKey('test-top-nav')),
          dock: SizedBox(height: 60, key: ValueKey('test-dock')),
        ),
      ),
    );

    expect(find.byKey(ThemeV2DitherField.shaderSurfaceKey), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(ThemeV2DitherField.shaderSurfaceKey)).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('test-top-nav'))).dy,
      ),
    );
  });
}
