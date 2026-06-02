import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Placeholder surface for E1 — a themed header + centered hint. Each real
/// surface (Chat / Calendar / Library / Notifications) replaces this in E2.
class StubSurface extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;

  const StubSurface({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Text(title,
                      style: TextStyle(
                          color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ...actions,
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 40, color: eu.textLo),
                    const SizedBox(height: 12),
                    Text(subtitle, style: TextStyle(color: eu.textMid, fontSize: 14)),
                  ],
                ),
              ),
            ),
            // Clearance for the floating dock.
            const SizedBox(height: 88),
          ],
        ),
      ),
    );
  }
}
