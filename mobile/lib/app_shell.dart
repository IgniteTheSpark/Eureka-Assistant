import 'package:flutter/material.dart';

import 'data_revision.dart';
import 'flash/flash_sheet.dart';
import 'pages/add_skill.dart';
import 'pages/calendar_page.dart';
import 'pages/chat_page.dart';
import 'pages/create_asset.dart';
import 'pages/device_pairing_page.dart';
import 'pages/library_page.dart';
import 'pages/notifications_page.dart';
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  // 0 = Calendar, 1 = Library. Chat (Agent) is a pushed route, not a tab — so
  // it covers the floating dock (matching the web, which hides the dock on
  // /chat). START_TAB lets a build boot into a surface (2 → push chat).
  int _index = () {
    const t = int.fromEnvironment('START_TAB', defaultValue: 0);
    return t == 2 ? 0 : t;
  }();

  @override
  void initState() {
    super.initState();
    // Final refresh safety net: data may have changed while the app was
    // backgrounded (another device, a background flash capture, a push). Bump
    // on resume so every list re-fetches the moment the user comes back —
    // complements the per-pop DataRefreshObserver and the SSE bumps.
    WidgetsBinding.instance.addObserver(this);
    if (const int.fromEnvironment('START_TAB', defaultValue: 0) == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAgent());
    }
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
    }
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

  void _go(int i) => setState(() => _index = i);

  void _openAgent() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatPage()));
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
                  children: const [CalendarPage(), LibraryPage()],
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
                    icon: Icons.add,
                    label: '快创',
                    leadingDivider: true,
                    onTap: () => showCreateMenu(context),
                  ),
                  DockItem(
                    icon: Icons.mic_none_outlined,
                    label: '闪念',
                    onTap: () => showFlashSheet(context),
                  ),
                  DockItem(
                    icon: Icons.auto_awesome,
                    label: 'Agent',
                    primary: true,
                    leadingDivider: true,
                    onTap: _openAgent,
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
