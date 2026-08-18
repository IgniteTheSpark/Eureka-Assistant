import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_shell.dart' show scheduleShellStartupSurface;
import '../../auth/auth_controller.dart';
import '../../config.dart';
import '../../data_revision.dart';
import '../../pages/calendar_page.dart' show calendarHome;
import '../../pages/chat_page.dart';
import '../../pages/device_pairing_page.dart';
import '../../pages/notifications_page.dart';
import '../../pet/reka_notifications.dart';
import '../../theme/app_theme.dart';
import '../calendar/calendar_controller.dart';
import '../calendar/calendar_editor_router.dart';
import '../calendar/theme_v2_calendar_page.dart';
import '../capture/capture_activity_coordinator.dart';
import '../capture/capture_activity_models.dart';
import '../capture/capture_activity_top_bar.dart';
import '../capture/capture_session_page.dart';
import '../device/theme_v2_device_route.dart';
import '../foundation/theme_v2_theme.dart';
import '../home/home_repository.dart';
import '../home/theme_v2_home_page.dart';
import '../home/today_dot_experiment_page.dart';
import '../inbox/reka_inbox_controller.dart';
import '../inbox/reka_inbox_page.dart';
import '../library/library_navigation.dart';
import '../library/theme_v2_library_page.dart';
import '../reka/reka_signal_repository.dart';
import '../reka/reka_signals_page.dart';
import '../report/report_container_page.dart';
import 'device_status_summary.dart';
import 'theme_v2_device_status_adapter.dart';
import 'theme_v2_floating_dock.dart';
import 'theme_v2_global_top_nav.dart';
import 'theme_v2_page_scaffold.dart';

/// Theme V2's real app-shell boundary.
///
/// Page bodies are injectable so shell behavior can be tested without mounting
/// network- or device-heavy production pages. The production defaults keep the
/// mature Library implementation alive during migration.
class ThemeV2AppShell extends StatefulWidget {
  const ThemeV2AppShell({
    super.key,
    this.pages,
    this.deviceStatus,
    this.deviceStatusAdapter,
    this.onDeviceSelected,
    this.onNotificationsPressed,
    this.inboxController,
    this.enableLegacyInbox = false,
    this.calendarController,
    this.libraryNavigation,
    this.homeRepository,
    this.rekaSignalRepository,
    this.captureActivityCoordinator,
    this.onCaptureActivitySelected,
    this.todayDotExperimentOverride,
    this.onManualRecord,
    this.onCreateReport,
    this.onStartChat,
    this.initialIndex = const int.fromEnvironment('START_TAB', defaultValue: 0),
    this.showStartupOverlays = true,
  }) : assert(deviceStatus == null || deviceStatusAdapter == null);

  final List<ThemeV2PageScaffold>? pages;
  final DeviceStatusSummary? deviceStatus;

  /// Test seam for exercising live changes without native hardware plugins.
  /// Production leaves this null and listens to the shared controllers.
  @visibleForTesting
  final ThemeV2DeviceStatusAdapter? deviceStatusAdapter;
  final ValueChanged<ThemeV2DeviceTarget>? onDeviceSelected;
  final VoidCallback? onNotificationsPressed;
  final RekaInboxController? inboxController;

  /// Retains the old Nudge/Offer inbox only for legacy-backed test or rollout
  /// hosts. The isolated Theme V2 service uses persistent notifications.
  final bool enableLegacyInbox;
  bool get usesLegacyInbox => enableLegacyInbox || inboxController != null;
  final CalendarController? calendarController;
  final LibraryNavigationController? libraryNavigation;
  final ThemeV2HomeRepository? homeRepository;
  final RekaSignalRepository? rekaSignalRepository;
  final CaptureActivityCoordinator? captureActivityCoordinator;
  final ValueChanged<CaptureActivityItem>? onCaptureActivitySelected;
  final bool? todayDotExperimentOverride;
  final VoidCallback? onManualRecord;
  final VoidCallback? onCreateReport;
  final VoidCallback? onStartChat;
  final int initialIndex;

  bool get usesTodayDotExperiment =>
      todayDotExperimentOverride ?? AppConfig.todayDotExperiment;

  /// Test seam only. Production keeps START_OVERLAY and morning briefing on.
  final bool showStartupOverlays;

  @override
  State<ThemeV2AppShell> createState() => _ThemeV2AppShellState();
}

class _ThemeV2AppShellState extends State<ThemeV2AppShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex.clamp(0, 2);
  late final RekaInboxController _inboxController =
      widget.inboxController ?? RekaInboxController();
  late final bool _ownsInboxController = widget.inboxController == null;
  late final CalendarController _calendarController =
      widget.calendarController ?? CalendarController();
  late final bool _ownsCalendarController = widget.calendarController == null;
  late final LibraryNavigationController _libraryNavigation =
      widget.libraryNavigation ?? LibraryNavigationController();
  late final bool _ownsLibraryNavigation = widget.libraryNavigation == null;
  ThemeV2DeviceStatusAdapter? _deviceStatusAdapter;
  bool _ownsDeviceStatusAdapter = false;
  late CaptureActivityCoordinator _captureActivityCoordinator;

  @override
  void initState() {
    super.initState();
    assert(widget.pages == null || widget.pages!.length == 3);
    WidgetsBinding.instance.addObserver(this);
    if (widget.usesLegacyInbox) {
      _inboxController.addListener(_onInboxChanged);
    } else {
      RekaNotifications.instance.addListener(_onInboxChanged);
    }
    _calendarController.surfaceListenable.addListener(_onCalendarChanged);
    _libraryNavigation.addListener(_onLibraryChanged);
    _attachCaptureActivityCoordinator();
    _attachDeviceStatusAdapter();
    if (widget.enableLegacyInbox &&
        _inboxController.status == RekaInboxStatus.idle) {
      unawaited(_inboxController.load(includeOffers: false));
    }
    if (widget.showStartupOverlays) {
      scheduleShellStartupSurface(context, enableMorningBriefing: false);
    }
  }

  @override
  void dispose() {
    _detachDeviceStatusAdapter();
    if (widget.usesLegacyInbox) {
      _inboxController.removeListener(_onInboxChanged);
    } else {
      RekaNotifications.instance.removeListener(_onInboxChanged);
    }
    if (_ownsInboxController) _inboxController.dispose();
    _calendarController.surfaceListenable.removeListener(_onCalendarChanged);
    if (_ownsCalendarController) _calendarController.dispose();
    _libraryNavigation.removeListener(_onLibraryChanged);
    if (_ownsLibraryNavigation) _libraryNavigation.dispose();
    _captureActivityCoordinator.removeListener(_onCaptureActivityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ThemeV2AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceStatus != widget.deviceStatus ||
        oldWidget.deviceStatusAdapter != widget.deviceStatusAdapter) {
      _detachDeviceStatusAdapter();
      _attachDeviceStatusAdapter();
    }
    if (oldWidget.captureActivityCoordinator !=
        widget.captureActivityCoordinator) {
      _captureActivityCoordinator.removeListener(_onCaptureActivityChanged);
      _attachCaptureActivityCoordinator();
    }
  }

  void _attachCaptureActivityCoordinator() {
    _captureActivityCoordinator =
        widget.captureActivityCoordinator ??
        CaptureActivityCoordinator.instance;
    _captureActivityCoordinator.addListener(_onCaptureActivityChanged);
  }

  void _onCaptureActivityChanged() {
    if (mounted) setState(() {});
  }

  void _attachDeviceStatusAdapter() {
    if (widget.deviceStatus != null) return;
    _deviceStatusAdapter =
        widget.deviceStatusAdapter ?? ThemeV2DeviceStatusAdapter();
    _ownsDeviceStatusAdapter = widget.deviceStatusAdapter == null;
    _deviceStatusAdapter!.addListener(_onDeviceStatusChanged);
  }

  void _detachDeviceStatusAdapter() {
    final adapter = _deviceStatusAdapter;
    if (adapter == null) return;
    adapter.removeListener(_onDeviceStatusChanged);
    if (_ownsDeviceStatusAdapter) adapter.dispose();
    _deviceStatusAdapter = null;
    _ownsDeviceStatusAdapter = false;
  }

  void _onDeviceStatusChanged() {
    if (mounted) setState(() {});
  }

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) bumpData();
  }

  void _selectDestination(int index) {
    if (index == 1 && _index == 1) calendarHome.value++;
    if (index == 2 && _index == 2) _libraryNavigation.home();
    if (_index != index) setState(() => _index = index);
  }

  void _openDevice(BuildContext context, ThemeV2DeviceTarget target) {
    final callback = widget.onDeviceSelected;
    if (callback != null) {
      callback(target);
      return;
    }
    final route = switch (target) {
      ThemeV2DeviceTarget.pairing => themeV2Route<void>(
        context: context,
        builder: (_) => const DevicePairingPage(),
      ),
      ThemeV2DeviceTarget.card => themeV2DeviceRoute(
        context: context,
        target: ThemeV2DeviceTarget.card,
      ),
      ThemeV2DeviceTarget.ring => themeV2DeviceRoute(
        context: context,
        target: ThemeV2DeviceTarget.ring,
      ),
    };
    Navigator.of(context).push(route);
  }

  void _openNotifications(BuildContext context) {
    final callback = widget.onNotificationsPressed;
    if (callback != null) {
      callback();
      return;
    }
    if (!widget.usesLegacyInbox) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
      );
      return;
    }
    final originLegacyTheme = Theme.of(context).extension<EurekaTheme>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) {
          final ambientTheme = Theme.of(routeContext);
          var routeTheme = buildThemeV2Theme(ambientTheme.brightness);
          final legacyTheme =
              ambientTheme.extension<EurekaTheme>() ?? originLegacyTheme;
          if (legacyTheme != null) {
            routeTheme = routeTheme.copyWith(
              extensions: [...routeTheme.extensions.values, legacyTheme],
            );
          }
          return Theme(
            data: routeTheme,
            child: RekaInboxPage(controller: _inboxController),
          );
        },
      ),
    );
  }

  void _openProfile(BuildContext context) {
    final tokens = context.themeV2;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.accent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Icon(
                      Icons.person_outline,
                      color: tokens.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AuthController.instance.email ?? '已登录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Eureka 账号',
                          style: TextStyle(color: tokens.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  AuthController.instance.logout(); // gate rebuilds to login
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 19, color: tokens.critical),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '退出登录',
                          style: TextStyle(
                            color: tokens.critical,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: tokens.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReports(BuildContext context, {bool startCreate = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportContainerPage(autoStartCreate: startCreate),
      ),
    );
  }

  void _openManualRecord(BuildContext context) {
    final callback = widget.onManualRecord;
    if (callback != null) {
      callback();
      return;
    }
    unawaited(openCalendarManualRecordFlow(context));
  }

  void _createReport(BuildContext context) {
    final callback = widget.onCreateReport;
    if (callback != null) {
      callback();
      return;
    }
    _openReports(context, startCreate: true);
  }

  void _startBlankChat(BuildContext context) {
    final callback = widget.onStartChat;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ChatPage(startBlank: true, themeV2Override: true),
      ),
    );
  }

  void _openRekaSignals(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => RekaSignalsPage(
          repository: widget.rekaSignalRepository,
          onOpenReports: () => _openReports(routeContext),
          onCreateReport: () => _openReports(routeContext, startCreate: true),
        ),
      ),
    );
  }

  void _openCaptureActivity(
    BuildContext context,
    CaptureActivityItem activity,
  ) {
    final callback = widget.onCaptureActivitySelected;
    if (callback != null) {
      callback(activity);
      return;
    }
    final recordingId = activity.recordingId;
    if (!activity.canOpenSession || recordingId == null) return;
    Navigator.of(context).push(
      themeV2Route<void>(
        context: context,
        builder: (_) => CaptureSessionPage(
          recordingId: recordingId,
          focusedInputTurnId: activity.inputTurnId,
        ),
      ),
    );
  }

  List<ThemeV2PageScaffold> _pages({required bool immersiveToday}) {
    return widget.pages ??
        [
          ThemeV2PageScaffold(
            extendBodyBehindChrome: immersiveToday,
            body: widget.usesTodayDotExperiment
                ? TodayDotExperimentPage(
                    active: _index == 0,
                    extendUnderChrome: immersiveToday,
                    repository: widget.homeRepository,
                    captureActivityCoordinator: _captureActivityCoordinator,
                    onManualRecord: () => _openManualRecord(context),
                    onCreateReport: () => _createReport(context),
                    onStartChat: () => _startBlankChat(context),
                    onOpenReka: () => _openRekaSignals(context),
                    onOpenAssetLibrary: () => _selectDestination(2),
                  )
                : ThemeV2HomePage(
                    active: _index == 0,
                    repository: widget.homeRepository,
                    rekaSignals: widget.rekaSignalRepository,
                    onOpenReka: () => _openRekaSignals(context),
                    onOpenReports: () => _openReports(context),
                    onCreateReport: () => _createReport(context),
                  ),
          ),
          ThemeV2PageScaffold(
            body: ThemeV2CalendarPage(
              active: _index == 1,
              controller: _calendarController,
            ),
            showDock: _calendarController.surface == CalendarSurface.overview,
          ),
          ThemeV2PageScaffold(
            body: ThemeV2LibraryPage(
              active: _index == 2,
              navigation: _libraryNavigation,
            ),
            showTopNav: _libraryNavigation.chrome.topNav,
            showDock: _libraryNavigation.chrome.dock,
          ),
        ];
  }

  @override
  Widget build(BuildContext context) {
    final ambientTheme = Theme.of(context);
    var themeV2 = buildThemeV2Theme(ambientTheme.brightness);

    // Transitional compatibility for the mature pages hosted above. Theme V2
    // remains the active Material theme; the legacy extension only supports
    // existing `context.eu` reads until those pages migrate.
    final legacyExtension = ambientTheme.extension<EurekaTheme>();
    if (legacyExtension != null) {
      themeV2 = themeV2.copyWith(
        extensions: [...themeV2.extensions.values, legacyExtension],
      );
    }

    final immersiveToday =
        widget.pages == null && widget.usesTodayDotExperiment;
    final pages = _pages(immersiveToday: immersiveToday);
    final activePage = pages[_index];
    final rootFloatingDock = widget.pages == null;
    final standardTopNav = ThemeV2GlobalTopNav(
      transparentSurface: rootFloatingDock,
      floatingDock: rootFloatingDock,
      deviceStatus:
          widget.deviceStatus ??
          _deviceStatusAdapter?.value ??
          const DeviceStatusSummary.disconnected(),
      unreadNotificationCount: widget.usesLegacyInbox
          ? _inboxController.unreadCount
          : RekaNotifications.instance.unread,
      onDeviceSelected: (target) => _openDevice(context, target),
      onNotificationsPressed: () => _openNotifications(context),
      onProfilePressed: () => _openProfile(context),
    );
    final captureSnapshot = _captureActivityCoordinator.snapshot;
    final topNav = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: captureSnapshot.active == null
          ? KeyedSubtree(
              key: const ValueKey<String>('theme-v2-standard-top-nav'),
              child: standardTopNav,
            )
          : CaptureActivityTopBar(
              key: const ValueKey<String>('theme-v2-capture-top-nav'),
              item: captureSnapshot.active!,
              queuedCount: captureSnapshot.queuedCount,
              onTap: () =>
                  _openCaptureActivity(context, captureSnapshot.active!),
            ),
    );
    final dock = ThemeV2FloatingDock(
      selectedIndex: _index,
      onDestinationSelected: _selectDestination,
    );

    return Theme(
      data: themeV2,
      child: activePage.withShellChrome(
        topNav: topNav,
        dock: dock,
        body: IndexedStack(
          index: _index,
          children: [
            for (final page in pages)
              KeyedSubtree(key: page.key, child: page.body),
          ],
        ),
      ),
    );
  }
}
