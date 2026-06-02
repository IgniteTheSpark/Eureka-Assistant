import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Notifications surface (pushed from the bell). E1 stub — real list in E2.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        title: const Text('通知'),
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
      ),
      body: Center(
        child: Text('通知中心（E2 接入 /api/notifications）',
            style: TextStyle(color: eu.textMid, fontSize: 14)),
      ),
    );
  }
}

/// Bell button used in the Calendar / Library headers.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '通知',
      icon: Icon(Icons.notifications_none, color: context.eu.textMid),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      ),
    );
  }
}
