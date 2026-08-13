import 'package:eureka/theme_v2/session/session_thinking_time.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'formats running thinking time at second minute and hour boundaries',
    () {
      expect(formatThinkingTimer(Duration.zero), '00:00');
      expect(formatThinkingTimer(const Duration(seconds: 8)), '00:08');
      expect(formatThinkingTimer(const Duration(seconds: 59)), '00:59');
      expect(formatThinkingTimer(const Duration(seconds: 60)), '01:00');
      expect(formatThinkingTimer(const Duration(seconds: 68)), '01:08');
      expect(formatThinkingTimer(const Duration(seconds: 3599)), '59:59');
      expect(formatThinkingTimer(const Duration(seconds: 3600)), '1:00:00');
    },
  );

  test('formats final thinking time in natural Chinese', () {
    expect(formatThinkingSummary(0), '思考不足 1 秒');
    expect(formatThinkingSummary(999), '思考不足 1 秒');
    expect(formatThinkingSummary(8000), '思考 8 秒');
    expect(formatThinkingSummary(68000), '思考 1 分 8 秒');
    expect(formatThinkingSummary(3728000), '思考 1 小时 2 分 8 秒');
    expect(formatThinkingSummary(-50), '思考不足 1 秒');
  });

  testWidgets(
    'live timer updates locally and is excluded from live semantics',
    (tester) async {
      final startedAt = DateTime(2026, 8, 13, 10);
      var now = startedAt;
      await tester.pumpWidget(
        _testHost(SessionThinkingTimer(startedAt: startedAt, now: () => now)),
      );
      expect(find.text('00:00'), findsOneWidget);

      now = startedAt.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:01'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byType(SessionThinkingTimer))
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
    },
  );

  testWidgets('final footer uses natural language and never shows tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testHost(const SessionThinkingFooter(elapsedMs: 68000)),
    );

    expect(find.text('思考 1 分 8 秒'), findsOneWidget);
    expect(find.textContaining('token'), findsNothing);
  });
}

Widget _testHost(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(body: child),
);
