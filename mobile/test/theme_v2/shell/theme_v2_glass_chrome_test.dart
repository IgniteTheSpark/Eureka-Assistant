import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_glass_chrome.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('floating top nav and dock use the shared glass chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              ThemeV2GlobalTopNav(
                floatingDock: true,
                deviceStatus: const DeviceStatusSummary.disconnected(),
                onDeviceSelected: (_) {},
                onNotificationsPressed: () {},
              ),
              const Spacer(),
              ThemeV2FloatingDock(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ThemeV2GlassChrome), findsNWidgets(2));
    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });
}
