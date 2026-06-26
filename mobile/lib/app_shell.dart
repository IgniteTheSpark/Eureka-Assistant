import 'package:flutter/material.dart';

import 'data_revision.dart';
import 'flash/flash_sheet.dart';
import 'pages/add_skill.dart';
import 'pages/calendar_page.dart';
import 'pages/create_asset.dart';
import 'pages/device_pairing_page.dart';
import 'pages/library_page.dart';
import 'pages/morning_briefing_page.dart' show maybeShowMorningBriefing;
import 'pages/notifications_page.dart';
import 'pages/today_page.dart';
import 'theme/app_theme.dart';
import 'today/today_palette.dart';
import 'widgets/floating_dock.dart';
import 'widgets/global_header.dart';

/// Root shell: an IndexedStack of the primary surfaces with the floating dock
/// overlaid at the bottom. Mirrors the web AppShell + FloatingDock. 快创 / 闪念
/// are stubbed actions for E1; they become CreateAssetMenu + the flash sheet in
/// later milestones (闪念 → native BLE capture in E3).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Observes pushes/pops over the shell so the calendar can reset to 流·今天 when
/// a pushed page (chat / detail / report) is popped back to it. Registered in
/// main.dart's navigatorObservers.
final RouteObserver<PageRoute<dynamic>> shellRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, RouteAware {
  // dock = 3 tabs: 0 = 今日 (TodayPage landing), 1 = 日历, 2 = 资产库. 我的岛 left the
  // dock → opens from the floating REKA ball's radial menu (reka_radial 'island' →
  // pushes PetPage). Chat / 快创 / 闪念 are folded into the floating 球球 too (§9.2).
  // START_TAB lets a build boot into a surface for screenshots.
  int _index = const int.fromEnvironment(
    'START_TAB',
    defaultValue: 0,
  ).clamp(0, 2);

  @override
  void initState() {
    super.initState();
    // Final refresh safety net: data may have changed while the app was
    // backgrounded (another device, a background flash capture, a push). Bump
    // on resume so every list re-fetches the moment the user comes back —
    // complements the per-pop DataRefreshObserver and the SSE bumps.
    WidgetsBinding.instance.addObserver(this);
    // START_OVERLAY lets a build boot straight into a tap-gated surface for
    // screenshot verification (notifications | flash).
    const overlay = String.fromEnvironment('START_OVERLAY');
    if (overlay == 'notifications') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsPage())),
      );
    } else if (overlay == 'flash') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showFlashSheet(context),
      );
    } else if (overlay == 'create') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showCreateMenu(context),
      );
    } else if (overlay == 'addskill') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showAddSkill(context),
      );
    } else if (overlay == 'device') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DevicePairingPage())),
      );
    } else {
      // §14.6 晨间简报 — 中午前的第一次打开进沉浸式「早安」页(每天一次、可滑走、
      // 失败静默)。放 else 里:截图验证用的 START_OVERLAY 启动不被它抢路由。
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => maybeShowMorningBriefing(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) shellRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // A pushed page (chat / detail / session) was popped back to the shell. Keep
    // the 流's last scroll position — the IndexedStack kept it alive underneath, so
    // returning lands where the user left off (回今天 button / re-tap 今天 recenter).
  }

  @override
  void dispose() {
    shellRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) bumpData();
  }

  void _go(int i) {
    // Re-tap 日历 while already on it → reset to 流 · 今天 (calendar is now tab 1;
    // its position is IndexedStack-kept when switching to it from another tab).
    if (i == 1 && _index == 1) calendarHome.value++;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      body: SafeArea(
        // One top inset for the whole shell: the global header sits below the
        // notch, and the pages (which also wrap in SafeArea) then see top=0 —
        // otherwise the inset is applied twice → a big gap under the header.
        bottom: false,
        child: Column(
          children: [
            // today tab gets the dark header only in dark mode; in light mode the
            // today page is itself light (warm), so the normal light header fits.
            GlobalHeaderBar(
              onDark: _index == 0 && eu.brightness == Brightness.dark,
              // today tab: paint the header with the page's atmosphereTop (and
              // drop the rule, handled inside) so it melts into the glow below —
              // killing the seam 色差. Non-today tabs → null = default bg + rule.
              bg: _index == 0 ? TodayPalette.of(context).atmosphereTop : null,
            ),
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _index,
                    children: [
                      // active gates the today page's bubble ticker + tilt sensor.
                      TodayPage(active: _index == 0),
                      const CalendarPage(),
                      const LibraryPage(),
                    ],
                  ),
                  // Ambient brand glow behind the dock — gives the glass capsule
                  // something to transmit on flat dark pages so it reads as 背透
                  // glass rather than a solid plate (mirrors the web dock's glow).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 200,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, 1.2),
                            radius: 1.1,
                            colors: [
                              eu.brand.withValues(
                                alpha: eu.brightness == Brightness.dark
                                    ? 0.30
                                    : 0.16,
                              ),
                              eu.brand.withValues(alpha: 0.10),
                              eu.brand.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.4, 0.75],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: FloatingDock(
                        items: [
                          DockItem(
                            icon: Icons.wb_sunny_outlined,
                            label: '今日',
                            active: _index == 0,
                            onTap: () => _go(0),
                          ),
                          DockItem(
                            icon: Icons.calendar_today_outlined,
                            label: '日历',
                            active: _index == 1,
                            onTap: () => _go(1),
                          ),
                          DockItem(
                            icon: Icons.grid_view_outlined,
                            label: '资产',
                            active: _index == 2,
                            onTap: () => _go(2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
