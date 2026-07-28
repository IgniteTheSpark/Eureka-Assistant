import 'package:eureka/theme_v2/theme_v2_rollout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'theme_v2_test_app.dart';

void main() {
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
