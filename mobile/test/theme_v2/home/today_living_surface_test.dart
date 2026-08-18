import 'package:flutter/foundation.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/home/today_living_surface.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scene has two container fields and no local Reka dither', (
    tester,
  ) async {
    final clock = ValueNotifier(DateTime(2026, 8, 14, 10));
    var openRekaCalls = 0;
    var openLibraryCalls = 0;
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      _host(
        rekaCenter: const Offset(112, 330),
        disableAnimations: true,
        clock: clock,
        onOpenReka: () => openRekaCalls++,
        onOpenAssetLibrary: () => openLibraryCalls++,
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('today-local-dither-field')),
      findsNothing,
    );
    expect(find.byType(ThemeV2DitherField), findsNWidgets(2));
    expect(find.byKey(const ValueKey('today-container-seam')), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('Reka 发现'), findsOneWidget);
    expect(find.text('Reka 生成'), findsOneWidget);
    expect(find.bySemanticsLabel('查看全部 Reka 发现'), findsOneWidget);
    expect(find.bySemanticsLabel('打开资产库'), findsOneWidget);
    await tester.tap(find.text('Reka 发现'));
    await tester.tap(find.text('Reka 生成'));
    expect(openRekaCalls, 1);
    expect(openLibraryCalls, 1);
  });

  testWidgets('shared dither motion pauses with the app lifecycle', (
    tester,
  ) async {
    final clock = ValueNotifier(DateTime(2026, 8, 14, 10));
    addTearDown(clock.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      _host(
        rekaCenter: const Offset(200, 420),
        disableAnimations: false,
        clock: clock,
      ),
    );
    await tester.pump();
    final field = tester.widget<ThemeV2DitherField>(
      find.byKey(const ValueKey('today-signal-dither-field')),
    );
    final motion = field.motion!;
    final before = motion.value;

    await tester.pump(const Duration(seconds: 1));
    expect(motion.value, greaterThan(before));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = motion.value;
    await tester.pump(const Duration(seconds: 1));

    expect(motion.value, paused);
  });

  testWidgets('next schedule shares the dither containers right edge', (
    tester,
  ) async {
    final clock = ValueNotifier(DateTime(2026, 8, 14, 10));
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      _host(
        rekaCenter: const Offset(200, 420),
        disableAnimations: true,
        clock: clock,
      ),
    );

    expect(
      tester.getTopRight(find.byKey(const ValueKey('today-next-schedule'))).dx,
      tester
          .getTopRight(find.byKey(const ValueKey('today-signal-dither-field')))
          .dx,
    );
  });
}

Widget _host({
  required Offset rekaCenter,
  required bool disableAnimations,
  required ValueListenable<DateTime> clock,
  VoidCallback? onOpenReka,
  VoidCallback? onOpenAssetLibrary,
}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(411, 800),
      devicePixelRatio: 1,
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(
      body: SizedBox(
        width: 411,
        height: 800,
        child: TodayLivingSurface(
          data: TodayData.empty,
          now: clock.value,
          active: true,
          clock: clock,
          rekaCenter: rekaCenter,
          onOpenReka: onOpenReka,
          onOpenAssetLibrary: onOpenAssetLibrary,
        ),
      ),
    ),
  ),
);
