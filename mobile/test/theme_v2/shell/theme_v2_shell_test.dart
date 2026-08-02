import 'package:eureka/app_shell.dart';
import 'package:eureka/pages/notifications_page.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_semantics.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_async_state.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => themeModeNotifier.value = ThemeMode.light);
  tearDown(() => themeModeNotifier.value = ThemeMode.light);

  testWidgets(
    'global top nav exposes logo, device, theme, and notification actions',
    (tester) async {
      var deviceTaps = 0;
      var notificationTaps = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _TestHost(
          child: ThemeV2GlobalTopNav(
            deviceStatus: const DeviceStatusSummary.disconnected(),
            onDevicePressed: () => deviceTaps++,
            onNotificationsPressed: () => notificationTaps++,
          ),
        ),
      );

      expect(find.bySemanticsLabel('UReka logo'), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);
      expect(find.bySemanticsLabel('设备：未连接'), findsOneWidget);
      expect(find.bySemanticsLabel('切换到夜间'), findsOneWidget);
      expect(find.bySemanticsLabel('通知'), findsOneWidget);

      for (final label in ['设备：未连接', '切换到夜间', '通知']) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
      expect(
        tester.getSize(
          find.descendant(
            of: find.bySemanticsLabel('切换到夜间'),
            matching: find.byType(ThemeV2HitTarget),
          ),
        ),
        const Size.square(44),
      );
      final themeIcon = tester.widget<Icon>(
        find.descendant(
          of: find.bySemanticsLabel('切换到夜间'),
          matching: find.byType(Icon),
        ),
      );
      expect(themeIcon.size, 20);
      expect(themeIcon.color, ThemeV2Tokens.light.muted);

      await tester.tap(find.bySemanticsLabel('设备：未连接'));
      await tester.tap(find.bySemanticsLabel('通知'));
      expect(deviceTaps, 1);
      expect(notificationTaps, 1);

      semantics.dispose();
    },
  );

  testWidgets('floating dock includes bottom safe area and fits 360px', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestHost(
        size: Size(360, 800),
        bottomPadding: 24,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ThemeV2FloatingDock(
            selectedIndex: 0,
            onDestinationSelected: _noopIndex,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final safePadding = tester.widget<Padding>(
      find.byKey(ThemeV2FloatingDock.safeAreaPaddingKey),
    );
    expect(safePadding.padding, const EdgeInsets.only(bottom: 35));
    final dock = find.byKey(ThemeV2FloatingDock.dockKey);
    expect(tester.getSize(dock).width, 169);
    expect(
      tester.getCenter(dock).dx,
      tester.getCenter(find.byType(ThemeV2FloatingDock)).dx,
    );
    for (final label in ['今日', '日历', '资产']) {
      final size = tester.getSize(find.bySemanticsLabel(label));
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }

    final material = tester.widget<Material>(dock);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(18));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.bySemanticsLabel('今日'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.auto_awesome_outlined,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.bySemanticsLabel('日历'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.calendar_month_outlined,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.bySemanticsLabel('资产'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.local_library_outlined,
    );
  });

  testWidgets('async primitives render loading and empty states', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestHost(
        disableAnimations: true,
        child: ThemeV2AsyncState.loading(label: '正在加载日程'),
      ),
    );

    expect(find.byType(USkeleton), findsWidgets);
    expect(find.text('正在加载日程'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);

    await tester.pumpWidget(
      const _TestHost(
        child: ThemeV2AsyncState.empty(
          title: '暂无内容',
          message: '创建第一条记录后会显示在这里',
        ),
      ),
    );

    expect(find.text('暂无内容'), findsOneWidget);
    expect(find.text('创建第一条记录后会显示在这里'), findsOneWidget);
  });

  testWidgets('async loading works with a pure Theme V2 palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _PureThemeV2Host(child: ThemeV2AsyncState.loading(label: '正在加载资产')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('正在加载资产'), findsOneWidget);
    final skeletons = tester.widgetList<USkeleton>(find.byType(USkeleton));
    expect(skeletons, isNotEmpty);
    for (final skeleton in skeletons) {
      expect(
        skeleton.baseColor,
        ThemeV2Tokens.light.muted.withValues(alpha: 0.12),
      );
      expect(
        skeleton.glowColor,
        ThemeV2Tokens.light.muted.withValues(alpha: 0.22),
      );
    }
  });

  testWidgets('async error exposes an accessible retry action', (tester) async {
    var retries = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _TestHost(
        child: ThemeV2AsyncState.error(
          title: '加载失败',
          message: '请检查网络后重试',
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('请检查网络后重试'), findsOneWidget);
    expect(find.bySemanticsLabel('重试'), findsOneWidget);
    final size = tester.getSize(find.bySemanticsLabel('重试'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));

    await tester.tap(find.bySemanticsLabel('重试'));
    expect(retries, 1);

    semantics.dispose();
  });

  testWidgets('startup callback ignores a context unmounted before its frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _UnmountedStartupScheduler()),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(NotificationsPage), findsNothing);
  });
}

void _noopIndex(int _) {}

class _TestHost extends StatelessWidget {
  const _TestHost({
    required this.child,
    this.size = const Size(411, 960),
    this.bottomPadding = 0,
    this.disableAnimations = false,
  });

  final Widget child;
  final Size size;
  final double bottomPadding;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: 1,
        padding: EdgeInsets.only(bottom: bottomPadding),
        disableAnimations: disableAnimations,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Scaffold(body: child),
      ),
    );
  }
}

class _PureThemeV2Host extends StatelessWidget {
  const _PureThemeV2Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );
  }
}

class _UnmountedStartupScheduler extends StatefulWidget {
  const _UnmountedStartupScheduler();

  @override
  State<_UnmountedStartupScheduler> createState() =>
      _UnmountedStartupSchedulerState();
}

class _UnmountedStartupSchedulerState
    extends State<_UnmountedStartupScheduler> {
  @override
  void dispose() {
    scheduleShellStartupSurface(context, overlay: 'notifications');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
