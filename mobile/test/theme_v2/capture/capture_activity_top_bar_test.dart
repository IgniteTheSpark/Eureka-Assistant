import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_models.dart';
import 'package:eureka/theme_v2/capture/capture_activity_top_bar.dart';
import 'package:eureka/theme_v2/capture/thinking_orb.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CaptureActivityItem item({
    CaptureActivityPhase phase = CaptureActivityPhase.organizing,
    String? sessionId,
    String? inputTurnId,
    int? resultCount,
  }) => CaptureActivityItem(
    aliases: const {'recording:recording-1'},
    source: CaptureActivitySource.ring,
    phase: phase,
    isRealtime: true,
    occurredAt: DateTime.utc(2026, 8, 7),
    sessionId: sessionId,
    inputTurnId: inputTurnId,
    resultCount: resultCount,
  );

  testWidgets('renders one orb, source, phase and queued count in 56px', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(
        child: CaptureActivityTopBar(
          item: item(),
          queuedCount: 2,
          onTap: () {},
        ),
      ),
    );

    expect(find.byType(ThinkingOrb), findsOneWidget);
    expect(find.text('UREKA 戒指'), findsOneWidget);
    expect(find.text('正在整理'), findsOneWidget);
    expect(find.text('另有 2 条'), findsOneWidget);
    expect(tester.getSize(find.byType(CaptureActivityTopBar)).height, 56);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(CaptureActivityTopBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, isNot(Colors.black));
  });

  testWidgets('tap is disabled before a real Session turn exists', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _Host(
        child: CaptureActivityTopBar(
          item: item(),
          queuedCount: 0,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byType(CaptureActivityTopBar));
    expect(taps, 0);

    await tester.pumpWidget(
      _Host(
        child: CaptureActivityTopBar(
          item: item(sessionId: 'session-1', inputTurnId: 'turn-1'),
          queuedCount: 0,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byType(CaptureActivityTopBar));
    expect(taps, 1);
  });

  testWidgets('success copy includes the real result count', (tester) async {
    await tester.pumpWidget(
      _Host(
        child: CaptureActivityTopBar(
          item: item(phase: CaptureActivityPhase.done, resultCount: 3),
          queuedCount: 0,
        ),
      ),
    );

    expect(find.text('已整理 · 3 项'), findsOneWidget);
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: Scaffold(body: child),
    );
  }
}
