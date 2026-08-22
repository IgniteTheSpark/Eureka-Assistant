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
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_title.dart';
import 'package:eureka/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Today experiment override preserves explicit false', (
    tester,
  ) async {
    const shell = ThemeV2AppShell(
      todayDotExperimentOverride: false,
      showStartupOverlays: false,
    );
    expect(shell.todayDotExperimentOverride, isFalse);
  });

  setUp(() => themeModeNotifier.value = ThemeMode.light);
  tearDown(() => themeModeNotifier.value = ThemeMode.light);

  testWidgets(
    'root page title exposes shared typography and header semantics',
    (tester) async {
      await tester.pumpWidget(
        const _PureThemeV2Host(child: ThemeV2PageTitle(title: '今日')),
      );

      final text = tester.widget<Text>(find.text('今日'));
      expect(text.style?.fontSize, 22);
      expect(text.style?.fontWeight, FontWeight.w700);
      final semantics = tester.widget<Semantics>(
        find.ancestor(of: find.text('今日'), matching: find.byType(Semantics)),
      );
      expect(semantics.properties.header, isTrue);
    },
  );

  testWidgets(
    'global top nav exposes logo, device, theme, and notification actions',
    (tester) async {
      final selected = <ThemeV2DeviceTarget>[];
      var notificationTaps = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _TestHost(
          child: ThemeV2GlobalTopNav(
            deviceStatus: const DeviceStatusSummary.disconnected(),
            onDeviceSelected: selected.add,
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
      expect(selected, [ThemeV2DeviceTarget.pairing]);
      expect(notificationTaps, 1);

      semantics.dispose();
    },
  );

  testWidgets('logo fires callback when onLogoPressed set', (tester) async {
    var profileTaps = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _TestHost(
        child: ThemeV2GlobalTopNav(
          deviceStatus: const DeviceStatusSummary.disconnected(),
          onDeviceSelected: _noopDeviceTarget,
          onNotificationsPressed: _noop,
          onLogoPressed: () => profileTaps++,
        ),
      ),
    );

    expect(find.bySemanticsLabel('UReka logo'), findsOneWidget);
    final size = tester.getSize(find.bySemanticsLabel('UReka logo'));
    expect(size.width, greaterThanOrEqualTo(44), reason: 'profile hit target');
    expect(size.height, greaterThanOrEqualTo(44), reason: 'profile hit target');

    await tester.tap(find.bySemanticsLabel('UReka logo'));
    expect(profileTaps, 1);
    expect(tester.takeException(), isNull);

    semantics.dispose();
  });

  testWidgets('logo remains visible when no logo callback is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestHost(
        child: ThemeV2GlobalTopNav(
          deviceStatus: const DeviceStatusSummary.disconnected(),
          onDeviceSelected: _noopDeviceTarget,
          onNotificationsPressed: _noop,
        ),
      ),
    );

    expect(find.bySemanticsLabel('UReka logo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating top dock matches bottom dock surface and fits 360px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const _TestHost(
        size: Size(360, 800),
        child: Align(
          alignment: Alignment.topCenter,
          child: ThemeV2GlobalTopNav(
            floatingDock: true,
            transparentSurface: true,
            deviceStatus: DeviceStatusSummary.disconnected(),
            onDeviceSelected: _noopDeviceTarget,
            onNotificationsPressed: _noop,
          ),
        ),
      ),
    );

    final dock = find.byKey(ThemeV2GlobalTopNav.floatingDockKey);
    expect(tester.getSize(dock), const Size(328, 60));
    expect(
      tester.getSize(find.byType(ThemeV2GlobalTopNav)).height,
      ThemeV2GlobalTopNav.floatingExtent,
    );
    final material = tester.widget<Material>(dock);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(material.elevation, ThemeV2FloatingDock.elevation);
    expect(material.shadowColor, ThemeV2FloatingDock.lightShadowColor);
    expect(material.color, ThemeV2Tokens.light.surface.withValues(alpha: .82));
    expect(
      shape.borderRadius,
      BorderRadius.circular(ThemeV2FloatingDock.lightRadius),
    );
    expect(shape.side.color, ThemeV2Tokens.light.border);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected device entries use accessible icon-only controls', (
    tester,
  ) async {
    for (final summary in [
      const DeviceStatusSummary.connected(
        presence: ThemeV2DevicePresence.card,
        label: '录音卡已连接',
      ),
      const DeviceStatusSummary.connected(
        presence: ThemeV2DevicePresence.ring,
        label: '戒指已连接',
      ),
      const DeviceStatusSummary.connected(
        presence: ThemeV2DevicePresence.both,
        label: '双设备已连接',
      ),
    ]) {
      await tester.pumpWidget(
        _TestHost(
          child: ThemeV2GlobalTopNav(
            deviceStatus: summary,
            onDeviceSelected: _noopDeviceTarget,
            onNotificationsPressed: _noop,
          ),
        ),
      );

      expect(find.text(summary.label), findsNothing);
      final deviceEntry = find.bySemanticsLabel('设备：${summary.label}');
      expect(deviceEntry, findsOneWidget);
      final size = tester.getSize(deviceEntry);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('device entry emits direct pairing, card, and ring targets', (
    tester,
  ) async {
    final selected = <ThemeV2DeviceTarget>[];
    const cases = <(DeviceStatusSummary, ThemeV2DeviceTarget)>[
      (DeviceStatusSummary.disconnected(), ThemeV2DeviceTarget.pairing),
      (
        DeviceStatusSummary.connected(
          presence: ThemeV2DevicePresence.card,
          label: '录音卡已连接',
        ),
        ThemeV2DeviceTarget.card,
      ),
      (
        DeviceStatusSummary.connected(
          presence: ThemeV2DevicePresence.ring,
          label: '戒指已连接',
        ),
        ThemeV2DeviceTarget.ring,
      ),
    ];

    for (final (summary, target) in cases) {
      await tester.pumpWidget(
        _TestHost(
          child: ThemeV2GlobalTopNav(
            deviceStatus: summary,
            onDeviceSelected: selected.add,
            onNotificationsPressed: _noop,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('设备：${summary.label}'));
      expect(selected.removeLast(), target);
    }
  });

  testWidgets('dual-device entry chooses a target from an anchored menu', (
    tester,
  ) async {
    for (final width in [360.0, 411.0]) {
      for (final target in [
        ThemeV2DeviceTarget.card,
        ThemeV2DeviceTarget.ring,
      ]) {
        final selected = <ThemeV2DeviceTarget>[];
        await tester.pumpWidget(
          _TestHost(
            size: Size(width, 800),
            child: ThemeV2GlobalTopNav(
              deviceStatus: const DeviceStatusSummary.connected(
                presence: ThemeV2DevicePresence.both,
                label: '双设备已连接',
              ),
              onDeviceSelected: selected.add,
              onNotificationsPressed: _noop,
            ),
          ),
        );

        final entry = find.bySemanticsLabel('设备：双设备已连接');
        final entrySize = tester.getSize(entry);
        final entryRect = tester.getRect(entry);
        expect(entrySize.width, greaterThanOrEqualTo(44));
        expect(entrySize.height, greaterThanOrEqualTo(44));
        await tester.tap(entry);
        await tester.pumpAndSettle();

        expect(selected, isEmpty);
        expect(find.text('UReka 录音卡'), findsOneWidget);
        expect(find.text('UReka 戒指'), findsOneWidget);
        expect(find.text('已连接'), findsNWidgets(2));
        final menuItems = find.byType(PopupMenuItem<ThemeV2DeviceTarget>);
        expect(menuItems, findsNWidgets(2));
        final itemRects = [
          for (final item in menuItems.evaluate())
            tester.getRect(find.byWidget(item.widget)),
        ];
        final popupBounds = itemRects.reduce(
          (bounds, rect) => bounds.expandToInclude(rect),
        );
        expect(popupBounds.top, greaterThanOrEqualTo(entryRect.bottom));
        expect(
          (popupBounds.left - entryRect.left).abs() <= 12 ||
              (popupBounds.right - entryRect.right).abs() <= 12,
          isTrue,
          reason: 'popup must align to the device button at width $width',
        );
        expect(
          find.descendant(
            of: menuItems,
            matching: find.byIcon(Icons.contactless_outlined),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: menuItems,
            matching: find.byIcon(Icons.circle_outlined),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'width $width');

        await tester.tap(
          find.text(
            target == ThemeV2DeviceTarget.card ? 'UReka 录音卡' : 'UReka 戒指',
          ),
        );
        await tester.pumpAndSettle();

        expect(selected, [target]);
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    }
  });

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
    expect(tester.getSize(dock), ThemeV2FloatingDock.shellSize);
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
      Icons.home_rounded,
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

    await tester.pumpWidget(
      const _TestHost(
        size: Size(360, 800),
        bottomPadding: 24,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ThemeV2FloatingDock(
            selectedIndex: 1,
            onDestinationSelected: _noopIndex,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.bySemanticsLabel('今日'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.home_outlined,
    );
  });

  testWidgets('floating dock uses semantic light and stable dark palettes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _PureThemeV2Host(
        child: ThemeV2FloatingDock(
          selectedIndex: 0,
          onDestinationSelected: _noopIndex,
        ),
      ),
    );

    final lightMaterial = tester.widget<Material>(
      find.byKey(ThemeV2FloatingDock.dockKey),
    );
    final lightShape = lightMaterial.shape! as RoundedRectangleBorder;
    expect(
      lightMaterial.color,
      ThemeV2Tokens.light.surface.withValues(alpha: .82),
    );
    expect(lightMaterial.shadowColor, Colors.black.withValues(alpha: 0.12));
    expect(lightShape.borderRadius, BorderRadius.circular(18));
    expect(lightShape.side.color, ThemeV2Tokens.light.border);
    expect(lightShape.side.width, 1);

    await tester.pumpWidget(
      const _PureThemeV2Host(
        brightness: Brightness.dark,
        child: ThemeV2FloatingDock(
          selectedIndex: 0,
          onDestinationSelected: _noopIndex,
        ),
      ),
    );

    final darkMaterial = tester.widget<Material>(
      find.byKey(ThemeV2FloatingDock.dockKey),
    );
    final darkShape = darkMaterial.shape! as RoundedRectangleBorder;
    expect(
      darkMaterial.color,
      ThemeV2Tokens.dark.surface.withValues(alpha: .88),
    );
    expect(darkMaterial.shadowColor, Colors.black.withValues(alpha: 0.22));
    expect(darkShape.borderRadius, BorderRadius.circular(20));
    expect(darkShape.side, BorderSide(color: ThemeV2Tokens.dark.border));
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

void _noopDeviceTarget(ThemeV2DeviceTarget _) {}

void _noop() {}

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
  const _PureThemeV2Host({
    required this.child,
    this.brightness = Brightness.light,
  });

  final Widget child;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildThemeV2Theme(brightness),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: child),
        ),
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
