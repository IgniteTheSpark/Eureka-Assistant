import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/capture_activity_models.dart';
import 'package:eureka/theme_v2/capture/capture_activity_top_bar.dart';
import 'package:eureka/theme_v2/capture/reka_companion_controller.dart';
import 'package:eureka/theme_v2/capture/reka_terminal.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/reka_mini.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:eureka/voice_input/reka_voice_capture.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture activity keeps root header and opens Reka terminal', (
    tester,
  ) async {
    final coordinator = CaptureActivityCoordinator();
    final voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _UnusedVoiceService()),
      sendFlash: (_, _) async {},
      haptic: () {},
    );
    final companion = RekaCompanionController(
      voice: voice,
      activities: coordinator,
    );
    final selected = <CaptureActivityItem>[];
    addTearDown(() async {
      companion.dispose();
      await voice.close();
      voice.dispose();
      coordinator.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          captureActivityCoordinator: coordinator,
          rekaVoiceCoordinator: voice,
          rekaCompanionController: companion,
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

    expect(find.byType(CaptureActivityTopBar), findsNothing);
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
    expect(find.byType(RekaTerminal), findsOneWidget);
    expect(find.byKey(RekaMini.targetKey), findsOneWidget);
    expect(find.bySemanticsLabel('设备：未连接'), findsOneWidget);
    expect(find.bySemanticsLabel('通知'), findsOneWidget);

    await tester.tap(find.byKey(RekaTerminal.bodyKey));
    expect(selected, hasLength(1));
    expect(selected.single.recordingId, 'recording-1');
  });
}

class _UnusedVoiceService implements VoiceInputServiceClient {
  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) {
    throw StateError('voice must not start in this test');
  }
}
