import 'package:flutter/material.dart';

import 'notifications_page.dart';
import 'stub_surface.dart';

/// Calendar surface (流 / 月 / 年). E1 stub — wired to /api/timeline in E2,
/// including the ⚡ flash capture rows.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubSurface(
      title: '日历',
      subtitle: '流 / 月 / 年（E2 接入 /api/timeline）',
      icon: Icons.calendar_month_outlined,
      actions: [NotificationsBell()],
    );
  }
}
