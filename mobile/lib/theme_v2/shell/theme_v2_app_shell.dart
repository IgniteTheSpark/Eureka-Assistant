import 'package:flutter/material.dart';

import '../../app_shell.dart' show scheduleShellStartupSurface;
import '../../data_revision.dart';
import '../../pages/calendar_page.dart' show calendarHome;
import '../../pages/device_pairing_page.dart';
import '../../pages/library_page.dart';
import '../../pages/notifications_page.dart';
import '../../pages/today_page.dart';
import '../../theme/app_theme.dart';
import '../calendar/theme_v2_calendar_page.dart';
import '../foundation/theme_v2_theme.dart';
import 'device_status_summary.dart';
import 'theme_v2_floating_dock.dart';
import 'theme_v2_global_top_nav.dart';
import 'theme_v2_page_scaffold.dart';

/// Theme V2's real app-shell boundary.
///
/// Page bodies are injectable so shell behavior can be tested without mounting
/// network- or device-heavy production pages. The production defaults keep the
/// mature Today and Library implementations alive during migration.
class ThemeV2AppShell extends StatefulWidget {
  const ThemeV2AppShell({
    super.key,
    this.pages,
    this.deviceStatus = const DeviceStatusSummary.disconnected(),
    this.onDevicePressed,
    this.onNotificationsPressed,
    this.initialIndex = const int.fromEnvironment('START_TAB', defaultValue: 0),
    this.showStartupOverlays = true,
  });

  final List<ThemeV2PageScaffold>? pages;
  final DeviceStatusSummary deviceStatus;
  final VoidCallback? onDevicePressed;
  final VoidCallback? onNotificationsPressed;
  final int initialIndex;

  /// Test seam only. Production keeps START_OVERLAY and morning briefing on.
  final bool showStartupOverlays;

  @override
  State<ThemeV2AppShell> createState() => _ThemeV2AppShellState();
}

class _ThemeV2AppShellState extends State<ThemeV2AppShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex.clamp(0, 2);

  @override
  void initState() {
    super.initState();
    assert(widget.pages == null || widget.pages!.length == 3);
    WidgetsBinding.instance.addObserver(this);
    if (widget.showStartupOverlays) scheduleShellStartupSurface(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) bumpData();
  }

  void _selectDestination(int index) {
    if (index == 1 && _index == 1) calendarHome.value++;
    if (_index != index) setState(() => _index = index);
  }

  void _openDevice(BuildContext context) {
    final callback = widget.onDevicePressed;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DevicePairingPage()));
  }

  void _openNotifications(BuildContext context) {
    final callback = widget.onNotificationsPressed;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }

  List<ThemeV2PageScaffold> _pages() {
    return widget.pages ??
        [
          ThemeV2PageScaffold(body: TodayPage(active: _index == 0)),
          const ThemeV2PageScaffold(body: ThemeV2CalendarPage()),
          const ThemeV2PageScaffold(body: LibraryPage()),
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

    final pages = _pages();
    final activePage = pages[_index];
    final topNav = ThemeV2GlobalTopNav(
      deviceStatus: widget.deviceStatus,
      onDevicePressed: () => _openDevice(context),
      onNotificationsPressed: () => _openNotifications(context),
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
