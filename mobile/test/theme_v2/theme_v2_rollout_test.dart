import 'package:eureka/config.dart';
import 'package:eureka/theme_v2/theme_v2_rollout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'theme_v2_test_app.dart';

void main() {
  testWidgets('compile-time Theme V2 config selects the app root shell', (
    tester,
  ) async {
    const expectedThemeV2 = bool.fromEnvironment(
      'THEME_V2',
      defaultValue: false,
    );

    await tester.pumpWidget(
      const ThemeV2TestApp(
        child: AppRootShell(
          legacyShell: Text('production legacy shell'),
          themeV2Shell: Text('production theme v2 shell'),
        ),
      ),
    );

    expect(AppConfig.themeV2, expectedThemeV2);
    expect(
      find.text('production theme v2 shell'),
      expectedThemeV2 ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('production legacy shell'),
      expectedThemeV2 ? findsNothing : findsOneWidget,
    );
  });

  testWidgets('Theme V2 flag selects the Theme V2 shell', (tester) async {
    await tester.pumpWidget(
      const ThemeV2TestApp(
        child: ThemeV2Rollout(
          enabled: true,
          legacyShell: Text('legacy shell'),
          themeV2Shell: Text('theme v2 shell'),
        ),
      ),
    );

    expect(find.text('theme v2 shell'), findsOneWidget);
    expect(find.text('legacy shell'), findsNothing);
  });

  testWidgets('Theme V2 rollout defaults to the legacy shell', (tester) async {
    await tester.pumpWidget(
      const ThemeV2TestApp(
        child: ThemeV2Rollout(
          legacyShell: Text('legacy shell'),
          themeV2Shell: Text('theme v2 shell'),
        ),
      ),
    );

    expect(find.text('legacy shell'), findsOneWidget);
    expect(find.text('theme v2 shell'), findsNothing);
  });
}
