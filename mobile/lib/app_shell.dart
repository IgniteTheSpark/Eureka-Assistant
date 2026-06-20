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
import 'pages/pet_page.dart';
import 'pet/floating_mascot.dart' show RekaFly;
import 'theme/app_theme.dart';
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
final RouteObserver<PageRoute<dynamic>> shellRouteObserver = RouteObserver<PageRoute<dynamic>>();

class _AppShellState extends State<AppShell> with WidgetsBindingObserver, RouteAware {
  // §7.2 dock = 3 tabs: 0 = 日历, 1 = 资产库, 2 = 我的岛 (REKA's home). Chat /
  // 快创 / 闪念 are no longer tabs — they're folded into the floating 球球 (§9.2).
  // START_TAB lets a build boot into a surface for screenshots.
  int _index = const int.fromEnvironment('START_TAB', defaultValue: 0).clamp(0, 2);
  // §9.2 飞出相框: lets _go() measure the island hero's rect at tab-tap time so the
  // floating ball can fly home from it when the user leaves 我的岛.
  final GlobalKey<PetBoardState> _islandKey = GlobalKey<PetBoardState>();

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
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsPage()),
          ));
    } else if (overlay == 'flash') {
      WidgetsBinding.instance.addPostFrameCallback((_) => showFlashSheet(context));
    } else if (overlay == 'create') {
      WidgetsBinding.instance.addPostFrameCallback((_) => showCreateMenu(context));
    } else if (overlay == 'addskill') {
      WidgetsBinding.instance.addPostFrameCallback((_) => showAddSkill(context));
    } else if (overlay == 'device') {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DevicePairingPage()),
          ));
    } else {
      // §14.6 晨间简报 — 中午前的第一次打开进沉浸式「早安」页(每天一次、可滑走、
      // 失败静默)。放 else 里:截图验证用的 START_OVERLAY 启动不被它抢路由。
      WidgetsBinding.instance.addPostFrameCallback((_) => maybeShowMorningBriefing());
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
    // Re-tap 今天 while already on the calendar → reset to 流 · 今天; switching TO
    // the calendar from another tab keeps its last position (IndexedStack-kept).
    if (i == 0 && _index == 0) calendarHome.value++;
    // Leaving 我的岛 → fly the ball home from the hero frame (§9.2 飞出相框). Measure
    // now, while the board is still laid out; the ball outlives the tab swap.
    if (_index == 2 && i != 2) {
      final r = _islandKey.currentState?.measureHeroRect();
      if (r != null) RekaFly.instance.flyOut(r);
    }
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
          const GlobalHeaderBar(),
          Expanded(
            child: Stack(
              children: [
                IndexedStack(
                  index: _index,
                  children: [
                    const CalendarPage(),
                    const LibraryPage(),
                    // 我的岛 — REKA's home. Lazy: only build (mount its PetView
                    // WebView) while the tab is active; a SizedBox otherwise so
                    // the WebView isn't alive behind the other tabs (perf).
                    _index == 2
                        ? SafeArea(top: false, child: PetBoard(key: _islandKey, bottomInset: 130))
                        : const SizedBox.shrink(),
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
                      eu.brand.withValues(alpha: eu.brightness == Brightness.dark ? 0.30 : 0.16),
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
                    icon: Icons.calendar_today_outlined,
                    label: '今天',
                    active: _index == 0,
                    onTap: () => _go(0),
                  ),
                  DockItem(
                    icon: Icons.grid_view_outlined,
                    label: '资产库',
                    active: _index == 1,
                    onTap: () => _go(1),
                  ),
                  DockItem(
                    icon: Icons.landscape_outlined,
                    label: '我的岛',
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
