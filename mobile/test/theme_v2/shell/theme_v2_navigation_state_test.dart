import 'package:eureka/pages/device_pairing_page.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_typography.dart';
import 'package:eureka/theme_v2/home/theme_v2_home_page.dart';
import 'package:eureka/theme_v2/home/home_agenda_panel.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/home/today_dot_experiment_page.dart';
import 'package:eureka/theme_v2/home/today_reka_scene.dart';
import 'package:eureka/theme_v2/reka/reka_signal_repository.dart';
import 'package:eureka/theme_v2/reka/reka_signals_page.dart';
import 'package:eureka/today/today_data.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:eureka/theme_v2/library/library_navigation.dart';
import 'package:eureka/theme_v2/library/theme_v2_library_page.dart';
import 'package:eureka/theme_v2/device/theme_v2_card_device_detail_page.dart';
import 'package:eureka/theme_v2/device/theme_v2_ring_device_detail_page.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/reka_mini.dart';
import 'package:eureka/theme_v2/shell/reka_shell_companion.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => themeModeNotifier.value = ThemeMode.light);
  tearDown(() => themeModeNotifier.value = ThemeMode.light);

  testWidgets('only the selected root page keeps its dither field active', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: DeviceStatusSummary.disconnected(),
          homeRepository: _HomeRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<ThemeV2CalendarPage>(
            find.byType(ThemeV2CalendarPage, skipOffstage: false),
          )
          .active,
      isFalse,
    );
    expect(
      tester
          .widget<ThemeV2LibraryPage>(
            find.byType(ThemeV2LibraryPage, skipOffstage: false),
          )
          .active,
      isFalse,
    );

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    expect(
      tester
          .widget<ThemeV2CalendarPage>(
            find.byType(ThemeV2CalendarPage, skipOffstage: false),
          )
          .active,
      isTrue,
    );
    expect(
      tester
          .widget<ThemeV2LibraryPage>(
            find.byType(ThemeV2LibraryPage, skipOffstage: false),
          )
          .active,
      isFalse,
    );

    await tester.tap(find.bySemanticsLabel('资产'));
    await tester.pump();
    expect(
      tester
          .widget<ThemeV2CalendarPage>(
            find.byType(ThemeV2CalendarPage, skipOffstage: false),
          )
          .active,
      isFalse,
    );
    expect(
      tester
          .widget<ThemeV2LibraryPage>(
            find.byType(ThemeV2LibraryPage, skipOffstage: false),
          )
          .active,
      isTrue,
    );
  });

  testWidgets('tab and controller state survive tab and theme changes', (
    tester,
  ) async {
    final todayController = ValueNotifier<int>(0);
    final calendarController = ValueNotifier<int>(0);
    final libraryController = ValueNotifier<int>(0);
    addTearDown(todayController.dispose);
    addTearDown(calendarController.dispose);
    addTearDown(libraryController.dispose);

    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          pages: [
            ThemeV2PageScaffold(
              key: ValueKey('today-page'),
              body: _StateProbe(name: 'today', controller: todayController),
            ),
            ThemeV2PageScaffold(
              key: ValueKey('calendar-page'),
              body: _StateProbe(
                name: 'calendar',
                controller: calendarController,
              ),
            ),
            ThemeV2PageScaffold(
              key: ValueKey('library-page'),
              body: _StateProbe(name: 'library', controller: libraryController),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('today increment'));
    await tester.pump();
    expect(find.text('today state 1 controller 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    await tester.tap(find.text('calendar increment'));
    await tester.pump();
    expect(find.text('calendar state 1 controller 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('资产'));
    await tester.pump();
    await tester.tap(find.text('library increment'));
    await tester.pump();
    expect(find.text('library state 1 controller 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('切换到夜间'));
    await tester.pumpAndSettle();
    expect(themeModeNotifier.value, ThemeMode.dark);
    expect(find.text('library state 1 controller 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('今日'));
    await tester.pump();
    expect(find.text('today state 1 controller 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    expect(find.text('calendar state 1 controller 1'), findsOneWidget);
  });

  testWidgets('root page states survive immersive and standard Tab switches', (
    tester,
  ) async {
    final keys = List.generate(3, (_) => GlobalKey<_MountedProbeState>());
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          pages: [
            ThemeV2PageScaffold(
              extendBodyBehindChrome: true,
              body: _MountedProbe(key: keys[0]),
            ),
            ThemeV2PageScaffold(body: _MountedProbe(key: keys[1])),
            ThemeV2PageScaffold(body: _MountedProbe(key: keys[2])),
          ],
        ),
      ),
    );
    final states = keys.map((key) => key.currentState).toList();

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('资产'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('今日'));
    await tester.pump();

    expect(keys.map((key) => key.currentState), orderedEquals(states));
    expect(states.map((state) => state!.disposeCount), everyElement(0));
    expect(states.map((state) => state!.deactivateCount), everyElement(0));
  });

  testWidgets('page scaffold declares nav dock and keyboard inset policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          pages: [
            ThemeV2PageScaffold(
              showTopNav: false,
              showDock: false,
              resizeToAvoidBottomInset: false,
              body: Text('immersive page'),
            ),
            ThemeV2PageScaffold(body: Text('calendar')),
            ThemeV2PageScaffold(body: Text('library')),
          ],
        ),
      ),
    );

    expect(find.text('immersive page'), findsOneWidget);
    expect(find.bySemanticsLabel('UReka logo'), findsNothing);
    expect(find.bySemanticsLabel('今日'), findsNothing);
    expect(
      tester
          .widget<Scaffold>(
            find.descendant(
              of: find.byType(ThemeV2PageScaffold),
              matching: find.byType(Scaffold),
            ),
          )
          .resizeToAvoidBottomInset,
      isFalse,
    );
  });

  testWidgets('real shell installs Theme V2 typography and tokens once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          pages: [
            ThemeV2PageScaffold(body: _ThemeProbe()),
            ThemeV2PageScaffold(body: Text('calendar')),
            ThemeV2PageScaffold(body: Text('library')),
          ],
        ),
      ),
    );

    expect(
      find.textContaining('font:${ThemeV2Typography.primaryFont}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('accent:${ThemeV2Tokens.light.accent}'),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('切换到夜间'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('font:${ThemeV2Typography.primaryFont}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('accent:${ThemeV2Tokens.dark.accent}'),
      findsOneWidget,
    );
  });

  testWidgets('production shell mounts the Theme V2 calendar surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHost(
        child: ThemeV2AppShell(initialIndex: 1, showStartupOverlays: false),
      ),
    );
    await tester.pump();

    expect(find.byType(ThemeV2CalendarPage), findsOneWidget);
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
  });

  testWidgets('production Today exposes top navigation and floating dock', (
    tester,
  ) async {
    final selected = <ThemeV2DeviceTarget>[];
    var notificationTaps = 0;
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          initialIndex: 0,
          todayDotExperimentOverride: false,
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          onDeviceSelected: selected.add,
          onNotificationsPressed: () => notificationTaps++,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ThemeV2HomePage), findsOneWidget);
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
    expect(find.text('目标'), findsNothing);

    await tester.tap(find.bySemanticsLabel('设备：未连接'));
    await tester.tap(find.bySemanticsLabel('通知'));
    expect(selected, [ThemeV2DeviceTarget.pairing]);
    expect(notificationTaps, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('今日'));
    await tester.pump();
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
  });

  testWidgets(
    'Today dot experiment replaces only Home and opens Session directly',
    (tester) async {
      tester.view.physicalSize = const Size(411, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var createReportCount = 0;
      var startChatCount = 0;
      await tester.pumpWidget(
        _ThemeHost(
          child: ThemeV2AppShell(
            showStartupOverlays: false,
            deviceStatus: const DeviceStatusSummary.disconnected(),
            homeRepository: const _HomeRepository(),
            todayDotExperimentOverride: true,
            onCreateReport: () => createReportCount++,
            onStartChat: () => startChatCount++,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TodayDotExperimentPage), findsOneWidget);
      expect(find.byType(ThemeV2HomePage), findsNothing);
      expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
      expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);

      await tester.tap(find.byKey(TodayRekaScene.rekaTargetKey));
      await tester.pump();

      expect(createReportCount, 0);
      expect(startChatCount, 1);
      expect(find.byType(PopupMenuItem), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Today to Calendar exposes only the proxy for 260ms', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHost(
        disableAnimations: false,
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: DeviceStatusSummary.disconnected(),
          homeRepository: _HomeRepository(),
          todayDotExperimentOverride: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(TodayRekaScene.rekaTargetKey), findsOneWidget);
    expect(find.byKey(RekaMini.targetKey), findsNothing);

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsOneWidget);
    expect(find.byKey(TodayRekaScene.rekaTargetKey), findsNothing);
    expect(find.byKey(RekaMini.targetKey), findsNothing);

    await tester.pump(const Duration(milliseconds: 259));
    expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsNothing);
    expect(find.byKey(RekaMini.targetKey), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('今日'));
    await tester.pump();
    expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsOneWidget);
    expect(find.byKey(TodayRekaScene.rekaTargetKey), findsNothing);
    expect(find.byKey(RekaMini.targetKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsNothing);
    expect(find.byKey(TodayRekaScene.rekaTargetKey), findsOneWidget);
    expect(find.byKey(RekaMini.targetKey), findsNothing);
  });

  testWidgets('reduced motion handoff crossfades without travel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: DeviceStatusSummary.disconnected(),
          homeRepository: _HomeRepository(),
          todayDotExperimentOverride: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pump();
    final initialCenter = tester.getCenter(
      find.byKey(RekaShellCompanion.handoffVisualKey),
    );
    await tester.pump(const Duration(milliseconds: 130));
    expect(
      tester.getCenter(find.byKey(RekaShellCompanion.handoffVisualKey)),
      initialCenter,
    );
    expect(find.byKey(TodayRekaScene.rekaTargetKey), findsNothing);
    expect(find.byKey(RekaMini.targetKey), findsNothing);

    await tester.pump(const Duration(milliseconds: 130));
    expect(find.byKey(RekaShellCompanion.handoffProxyKey), findsNothing);
    expect(find.byKey(RekaMini.targetKey), findsOneWidget);
  });

  testWidgets('root pages share the floating Top Dock', (tester) async {
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          todayDotExperimentOverride: true,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          homeRepository: const _HomeRepository(),
        ),
      ),
    );
    await tester.pump();

    final scaffold = tester.widget<ThemeV2PageScaffold>(
      find.byType(ThemeV2PageScaffold),
    );
    final nav = tester.widget<ThemeV2GlobalTopNav>(
      find.byType(ThemeV2GlobalTopNav),
    );
    expect(scaffold.extendBodyBehindChrome, isTrue);
    expect(nav.transparentSurface, isTrue);
    expect(nav.floatingDock, isTrue);

    await tester.tap(find.bySemanticsLabel('日历'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ThemeV2PageScaffold>(find.byType(ThemeV2PageScaffold))
          .extendBodyBehindChrome,
      isFalse,
    );
    expect(
      tester
          .widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav))
          .transparentSurface,
      isTrue,
    );
    expect(
      tester
          .widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav))
          .floatingDock,
      isTrue,
    );

    await tester.tap(find.bySemanticsLabel('资产'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav))
          .floatingDock,
      isTrue,
    );
  });

  testWidgets('Today Next capsule opens the local agenda and keeps Today', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          todayDotExperimentOverride: true,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          homeRepository: const _HomeRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TodayDotExperimentPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeAgendaPanel), findsOneWidget);
    expect(
      tester
          .widget<ThemeV2FloatingDock>(find.byType(ThemeV2FloatingDock))
          .selectedIndex,
      0,
    );
  });

  testWidgets('Today experiment keeps floating chrome in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          todayDotExperimentOverride: true,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          homeRepository: const _HomeRepository(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('切换到夜间'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ThemeV2PageScaffold>(find.byType(ThemeV2PageScaffold))
          .extendBodyBehindChrome,
      isTrue,
    );
    expect(
      tester
          .widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav))
          .transparentSurface,
      isTrue,
    );
    expect(
      tester
          .widget<ThemeV2GlobalTopNav>(find.byType(ThemeV2GlobalTopNav))
          .floatingDock,
      isTrue,
    );
  });

  testWidgets('Home Reka entry opens signals instead of notifications', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          todayDotExperimentOverride: true,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          homeRepository: _HomeRepository(
            TodayData.empty.withRekaQueue([
              TodayRekaItem(
                id: 'signal-1',
                type: 'rhythm_gap',
                title: '跑步还没有记录',
                body: '可以现在补上一笔',
                link: '',
                createdAt: DateTime(2026, 8, 16),
              ),
            ]),
          ),
          rekaSignalRepository: _RekaRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(find.byType(RekaSignalsPage), findsOneWidget);
    expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsNothing);
    expect(find.text('Reka 发现'), findsOneWidget);
  });

  testWidgets('production shell routes each direct device target', (
    tester,
  ) async {
    const cases = <(DeviceStatusSummary, Type)>[
      (DeviceStatusSummary.disconnected(), DevicePairingPage),
      (
        DeviceStatusSummary.connected(
          presence: ThemeV2DevicePresence.card,
          label: '录音卡已连接',
        ),
        ThemeV2CardDeviceDetailPage,
      ),
      (
        DeviceStatusSummary.connected(
          presence: ThemeV2DevicePresence.ring,
          label: '戒指已连接',
        ),
        ThemeV2RingDeviceDetailPage,
      ),
    ];

    for (final (summary, pageType) in cases) {
      await tester.pumpWidget(
        _ThemeHost(
          child: ThemeV2AppShell(
            showStartupOverlays: false,
            deviceStatus: summary,
            pages: const [
              ThemeV2PageScaffold(body: Text('today')),
              ThemeV2PageScaffold(body: Text('calendar')),
              ThemeV2PageScaffold(body: Text('library')),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('设备：${summary.label}'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(pageType), findsOneWidget);
      expect(tester.takeException(), isNull);
      final routeContext = tester.element(find.byType(pageType));
      expect(
        Theme.of(routeContext).textTheme.bodyMedium?.fontFamily,
        ThemeV2Typography.primaryFont,
      );
      expect(Theme.of(routeContext).extension<ThemeV2Tokens>(), isNotNull);
      expect(Theme.of(routeContext).extension<EurekaTheme>(), isNotNull);

      Navigator.of(tester.element(find.byType(pageType))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  });

  testWidgets('Calendar secondary surfaces hide the dock', (tester) async {
    final controller = CalendarController()
      ..openDay(DateTime(2026, 7, 3))
      ..openSchedule();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          initialIndex: 1,
          showStartupOverlays: false,
          calendarController: controller,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsNothing);
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);

    controller.backToDay();
    await tester.pump();
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsNothing);
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);

    controller.backToOverview();
    await tester.pump();
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
  });

  testWidgets('Library surfaces coordinate shell chrome and local back', (
    tester,
  ) async {
    final navigation = LibraryNavigationController();
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      _ThemeHost(
        child: ThemeV2AppShell(
          initialIndex: 2,
          showStartupOverlays: false,
          libraryNavigation: navigation,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);

    navigation.open(LibrarySurface.allContainers);
    await tester.pump();
    expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsNothing);

    navigation.open(LibrarySurface.pinnedConfiguration);
    await tester.pump();
    expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
    expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(navigation.surface, LibrarySurface.allContainers);

    navigation.home();
    navigation.open(LibrarySurface.containerIndex);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('资产'));
    await tester.pump();
    expect(navigation.surface, LibrarySurface.hub);
  });
}

class _ThemeHost extends StatelessWidget {
  const _ThemeHost({required this.child, this.disableAnimations = true});

  final Widget child;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(411, 960),
        devicePixelRatio: 1,
        disableAnimations: disableAnimations,
        textScaler: TextScaler.noScaling,
      ),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, child) => MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          darkTheme: buildEurekaTheme(EurekaColors.dark),
          themeMode: mode,
          home: child,
        ),
        child: child,
      ),
    );
  }
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.name, required this.controller});

  final String name;
  final ValueNotifier<int> controller;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  var count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: widget.controller,
            builder: (_, controllerValue, _) =>
                Text('${widget.name} state $count controller $controllerValue'),
          ),
          TextButton(
            onPressed: () {
              setState(() => count++);
              widget.controller.value++;
            },
            child: Text('${widget.name} increment'),
          ),
        ],
      ),
    );
  }
}

class _MountedProbe extends StatefulWidget {
  const _MountedProbe({super.key});

  @override
  State<_MountedProbe> createState() => _MountedProbeState();
}

class _MountedProbeState extends State<_MountedProbe> {
  var disposeCount = 0;
  var deactivateCount = 0;

  @override
  void deactivate() {
    deactivateCount++;
    super.deactivate();
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) {
    return Text(
      'font:${Theme.of(context).textTheme.bodyMedium?.fontFamily}\n'
      'accent:${ThemeV2Tokens.of(context).accent}',
    );
  }
}

class _HomeRepository implements ThemeV2HomeRepository {
  const _HomeRepository([this.data = TodayData.empty]);

  final TodayData data;

  @override
  Future<TodayData> load() async => data;
}

class _RekaRepository implements RekaSignalRepository {
  @override
  Future<void> completeTodo(String assetId) async {}

  @override
  Future<void> dismiss(String signalId) async {}

  @override
  Future<void> snooze(String signalId, DateTime remindAgainAt) async {}

  @override
  Future<RekaSignalBatch> load({String timezoneName = 'Asia/Shanghai'}) async =>
      const RekaSignalBatch(
        signals: [],
        partialFailures: [],
        generatedAt: null,
      );
}
