import 'package:eureka/device/device_controller.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_device_status_adapter.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../theme_v2_test_app.dart';

void main() {
  test('maps card, ring, and card errors into stable summaries', () {
    expect(
      ThemeV2DeviceStatusAdapter.summarize(
        const ThemeV2DeviceStatusSnapshot(),
      ).kind,
      DeviceStatusSummaryKind.disconnected,
    );
    expect(
      ThemeV2DeviceStatusAdapter.summarize(
        const ThemeV2DeviceStatusSnapshot(
          cardState: DeviceConnState.connected,
          cardIsBound: true,
        ),
      ).label,
      '录音卡已连接',
    );
    expect(
      ThemeV2DeviceStatusAdapter.summarize(
        const ThemeV2DeviceStatusSnapshot(ringConnected: true),
      ).label,
      '戒指已连接',
    );
    expect(
      ThemeV2DeviceStatusAdapter.summarize(
        const ThemeV2DeviceStatusSnapshot(
          cardState: DeviceConnState.connected,
          cardIsBound: true,
          ringConnected: true,
        ),
      ).label,
      '双设备已连接',
    );
    expect(
      ThemeV2DeviceStatusAdapter.summarize(
        const ThemeV2DeviceStatusSnapshot(
          cardState: DeviceConnState.error,
          cardError: '蓝牙权限不可用',
          ringConnected: true,
        ),
      ).kind,
      DeviceStatusSummaryKind.attention,
    );
  });

  testWidgets('production shell reacts to live device changes in place', (
    tester,
  ) async {
    final source = ValueNotifier<ThemeV2DeviceStatusSnapshot>(
      const ThemeV2DeviceStatusSnapshot(),
    );
    final adapter = ThemeV2DeviceStatusAdapter.fromSnapshots(source);
    addTearDown(source.dispose);
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      ThemeV2TestApp(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatusAdapter: adapter,
          pages: const [
            ThemeV2PageScaffold(body: Text('today-live-state')),
            ThemeV2PageScaffold(body: Text('calendar-live-state')),
            ThemeV2PageScaffold(body: Text('library-live-state')),
          ],
        ),
      ),
    );

    final originalShell = tester.element(find.byType(ThemeV2AppShell));
    expect(find.bySemanticsLabel('设备：未连接'), findsOneWidget);

    source.value = const ThemeV2DeviceStatusSnapshot(
      cardState: DeviceConnState.connected,
      cardIsBound: true,
    );
    await tester.pump();
    expect(find.bySemanticsLabel('设备：录音卡已连接'), findsOneWidget);
    expect(tester.element(find.byType(ThemeV2AppShell)), same(originalShell));

    source.value = const ThemeV2DeviceStatusSnapshot(ringConnected: true);
    await tester.pump();
    expect(find.bySemanticsLabel('设备：戒指已连接'), findsOneWidget);
    expect(tester.element(find.byType(ThemeV2AppShell)), same(originalShell));
  });
}
