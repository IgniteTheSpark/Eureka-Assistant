import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/thinking_orb.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('thinking orb is Flutter-native and updates by phase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const Center(
          child: ThinkingOrb(phase: CaptureActivityPhase.listening, size: 32),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ThinkingOrb),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(ThinkingOrb)), const Size.square(32));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const Center(
          child: ThinkingOrb(phase: CaptureActivityPhase.organizing, size: 32),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}
