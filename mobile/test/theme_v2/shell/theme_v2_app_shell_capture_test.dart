import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/capture_activity_models.dart';
import 'package:eureka/theme_v2/capture/capture_activity_top_bar.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture activity replaces the complete root header', (
    tester,
  ) async {
    final coordinator = CaptureActivityCoordinator();
    final selected = <CaptureActivityItem>[];
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          captureActivityCoordinator: coordinator,
          onCaptureActivitySelected: selected.add,
          pages: const [
            ThemeV2PageScaffold(body: Text('today')),
            ThemeV2PageScaffold(body: Text('calendar')),
            ThemeV2PageScaffold(body: Text('library')),
          ],
        ),
      ),
    );

    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
    expect(find.byType(CaptureActivityTopBar), findsNothing);

    coordinator.apply(
      CaptureActivityEvent(
        aliases: const {'client:ring-task-1', 'recording:recording-1'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.understanding,
        isRealtime: true,
        sessionId: 'session-1',
        inputTurnId: 'turn-1',
        occurredAt: DateTime.utc(2026, 8, 7),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CaptureActivityTopBar), findsOneWidget);
    expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
    expect(find.bySemanticsLabel('设备：未连接'), findsNothing);
    expect(find.bySemanticsLabel('通知'), findsNothing);

    await tester.tap(find.byType(CaptureActivityTopBar));
    expect(selected, hasLength(1));
    expect(selected.single.recordingId, 'recording-1');
  });
}
