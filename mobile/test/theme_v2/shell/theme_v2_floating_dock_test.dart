import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Dock owns one 248x64 shell and one 76x72 cockpit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThemeV2FloatingDock(
          selectedIndex: 1,
          onDestinationSelected: (_) {},
          rekaCockpit: const SizedBox(key: ValueKey('cockpit-child')),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(ThemeV2FloatingDock.dockKey)),
      const Size(248, 64),
    );
    expect(
      tester.getSize(find.byKey(ThemeV2FloatingDock.cockpitKey)),
      const Size(76, 72),
    );
    expect(find.byKey(const ValueKey('cockpit-child')), findsOneWidget);
    for (final label in const ['今日', '日历', '资产']) {
      final size = tester.getSize(find.bySemanticsLabel(label));
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testWidgets('Today keeps an empty recess without a Reka hit target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThemeV2FloatingDock(selectedIndex: 0, onDestinationSelected: (_) {}),
      ),
    );

    expect(find.byKey(ThemeV2FloatingDock.cockpitKey), findsOneWidget);
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
      const Size(248, 98),
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
