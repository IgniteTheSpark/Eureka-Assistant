import 'package:flutter/material.dart';

import 'flash/flash_sheet.dart';
import 'pages/calendar_page.dart';
import 'pages/chat_page.dart';
import 'pages/library_page.dart';
import 'widgets/floating_dock.dart';

/// Root shell: an IndexedStack of the primary surfaces with the floating dock
/// overlaid at the bottom. Mirrors the web AppShell + FloatingDock. 快创 / 闪念
/// are stubbed actions for E1; they become CreateAssetMenu + the flash sheet in
/// later milestones (闪念 → native BLE capture in E3).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // 0 = Calendar, 1 = Library, 2 = Chat

  void _go(int i) => setState(() => _index = i);

  void _stub(String name) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$name · 即将上线')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [CalendarPage(), LibraryPage(), ChatPage()],
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
                  DockItem(icon: Icons.add, label: '快创', onTap: () => _stub('快创')),
                  DockItem(
                    icon: Icons.bolt_outlined,
                    label: '闪念',
                    onTap: () => showFlashSheet(context),
                  ),
                  DockItem(
                    icon: Icons.auto_awesome,
                    label: 'Agent',
                    primary: true,
                    active: _index == 2,
                    onTap: () => _go(2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
