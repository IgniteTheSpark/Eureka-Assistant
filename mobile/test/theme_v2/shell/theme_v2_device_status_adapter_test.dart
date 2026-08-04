import 'package:eureka/device/device_controller.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_device_status_adapter.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../theme_v2_test_app.dart';

void main() {
  test('maps device states into typed presence and direct targets', () {
    final disconnected = ThemeV2DeviceStatusAdapter.summarize(
      const ThemeV2DeviceStatusSnapshot(),
    );
    final card = ThemeV2DeviceStatusAdapter.summarize(
      const ThemeV2DeviceStatusSnapshot(
        cardState: DeviceConnState.connected,
        cardIsBound: true,
      ),
    );
    final ring = ThemeV2DeviceStatusAdapter.summarize(
      const ThemeV2DeviceStatusSnapshot(ringConnected: true),
    );
    final dual = ThemeV2DeviceStatusAdapter.summarize(
      const ThemeV2DeviceStatusSnapshot(
        cardState: DeviceConnState.connected,
        cardIsBound: true,
        ringConnected: true,
      ),
    );

    expect(disconnected.presence, ThemeV2DevicePresence.none);
    expect(card.presence, ThemeV2DevicePresence.card);
    expect(ring.presence, ThemeV2DevicePresence.ring);
    expect(dual.presence, ThemeV2DevicePresence.both);
    expect(card.directTarget, ThemeV2DeviceTarget.card);
    expect(ring.directTarget, ThemeV2DeviceTarget.ring);
    expect(dual.directTarget, isNull);
  });

  test('only surfaces card attention while the card remains bound', () {
    final unboundError = ThemeV2DeviceStatusAdapter.summarize(
      const ThemeV2DeviceStatusSnapshot(
        cardState: DeviceConnState.error,
        cardError: '蓝牙权限不可用',
        ringConnected: true,
      ),
    );
    final boundError = ThemeV2DeviceStatusAdapter.summarize(
      const ThemeV2DeviceStatusSnapshot(
        cardState: DeviceConnState.error,
        cardIsBound: true,
        cardError: '蓝牙权限不可用',
        ringConnected: true,
      ),
    );

    expect(unboundError.presence, ThemeV2DevicePresence.ring);
    expect(boundError.kind, DeviceStatusSummaryKind.attention);
    expect(boundError.presence, ThemeV2DevicePresence.both);
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
