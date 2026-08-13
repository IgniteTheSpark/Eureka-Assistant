import 'dart:io';

import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_dot_experiment_page.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey<String>('today-dot-experiment-golden');
  const size = Size(411, 960);

  setUpAll(() async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'))).load();
    await (FontLoader('Geist Mono')..addFont(
          rootBundle.load('assets/fonts/GeistMono/GeistMono-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    if (pingFang.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(pingFang.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  setUp(() => themeModeNotifier.value = ThemeMode.light);
  tearDown(() => themeModeNotifier.value = ThemeMode.light);

  testWidgets('Today dot experiment empty light 411', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _GoldenHost(
        child: RepaintBoundary(
          key: surface,
          child: ThemeV2PageScaffold(
            topNav: const ThemeV2GlobalTopNav(
              deviceStatus: DeviceStatusSummary.disconnected(),
              onDeviceSelected: _noopDeviceTarget,
              onNotificationsPressed: _noop,
            ),
            dock: const ThemeV2FloatingDock(
              selectedIndex: 0,
              onDestinationSelected: _noopIndex,
            ),
            body: TodayDotExperimentPage(now: DateTime(2026, 7, 31)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('7月31日 · 周五'), findsOneWidget);
    expect(find.text('今天很安静，我在这里。'), findsOneWidget);
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
    await expectLater(
      find.byKey(surface),
      matchesGoldenFile('goldens/today-dot-empty-411-light.png'),
    );
  });
}

class _GoldenHost extends StatelessWidget {
  const _GoldenHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(
        size: Size(411, 960),
        devicePixelRatio: 1,
        padding: EdgeInsets.only(top: 44),
        platformBrightness: Brightness.light,
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        theme: buildThemeV2Theme(Brightness.light),
        home: child,
      ),
    );
  }
}

void _noop() {}
void _noopDeviceTarget(ThemeV2DeviceTarget _) {}
void _noopIndex(int _) {}
