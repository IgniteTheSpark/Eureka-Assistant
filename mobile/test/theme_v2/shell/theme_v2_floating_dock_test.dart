import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Dock restores one compact three-destination shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThemeV2FloatingDock(selectedIndex: 1, onDestinationSelected: (_) {}),
      ),
    );

    expect(
      tester.getSize(find.byKey(ThemeV2FloatingDock.dockKey)),
      const Size(169, 60),
    );
    expect(find.byKey(ThemeV2FloatingDock.cockpitKey), findsNothing);
    for (final label in const ['今日', '日历', '资产']) {
      final size = tester.getSize(find.bySemanticsLabel(label));
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testWidgets('Today keeps no empty Reka recess or hit target', (tester) async {
    await tester.pumpWidget(
      _host(
        ThemeV2FloatingDock(selectedIndex: 0, onDestinationSelected: (_) {}),
      ),
    );

    expect(find.byKey(ThemeV2FloatingDock.cockpitKey), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Reka，')), findsNothing);
  });

  testWidgets('safe area remains outside the fixed Dock composition', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThemeV2FloatingDock(selectedIndex: 2, onDestinationSelected: (_) {}),
        bottomPadding: 48,
      ),
    );

    expect(
      tester.getSize(find.byKey(ThemeV2FloatingDock.compositionKey)),
      const Size(169, 60),
    );
    final compositionBottom = tester
        .getBottomLeft(find.byKey(ThemeV2FloatingDock.compositionKey))
        .dy;
    final viewportBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
    expect(viewportBottom - compositionBottom, 48);
  });
}

Widget _host(Widget child, {double bottomPadding = 0}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 700),
      padding: EdgeInsets.only(bottom: bottomPadding),
    ),
    child: Scaffold(body: SizedBox(width: 400, height: 700, child: child)),
  ),
);
