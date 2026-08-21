import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page scaffold uses a pure background without global dither', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const ThemeV2PageScaffold(
          body: SizedBox.expand(key: ValueKey('test-body')),
          topNav: SizedBox(height: 56, key: ValueKey('test-top-nav')),
          dock: SizedBox(height: 60, key: ValueKey('test-dock')),
          companion: SizedBox.expand(key: ValueKey('test-companion')),
        ),
      ),
    );

    expect(find.byKey(ThemeV2DitherField.shaderSurfaceKey), findsNothing);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ThemeV2Tokens.light.background);
    final scaffoldRect = tester.getRect(find.byType(Scaffold));
    final bodyRect = tester.getRect(find.byKey(const ValueKey('test-body')));
    expect(
      scaffoldRect.bottom - bodyRect.bottom,
      ThemeV2FloatingDock.contentClearance,
    );
    expect(ThemeV2FloatingDock.contentClearance, 72);
    expect(find.byKey(const ValueKey('test-companion')), findsOneWidget);
  });

  testWidgets('no-Dock page renders no companion and reserves no bottom gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const ThemeV2PageScaffold(
          showDock: false,
          body: SizedBox.expand(key: ValueKey('no-dock-body')),
          companion: SizedBox.expand(key: ValueKey('hidden-companion')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('hidden-companion')), findsNothing);
    final scaffoldRect = tester.getRect(find.byType(Scaffold));
    final bodyRect = tester.getRect(find.byKey(const ValueKey('no-dock-body')));
    expect(bodyRect.bottom, scaffoldRect.bottom);
  });
}
