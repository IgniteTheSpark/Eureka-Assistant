import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One entry in the floating dock.
class DockItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  /// The Agent entry renders as a brand→purple gradient pill (per the web dock).
  final bool primary;

  const DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.primary = false,
  });
}

/// Global floating capsule dock (mirrors the web FloatingDock): a rounded,
/// raised bar of quick actions + the Agent pill. Shared across surfaces.
class FloatingDock extends StatelessWidget {
  final List<DockItem> items;
  const FloatingDock({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: eu.surfaceRaised.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: eu.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (final it in items) _button(context, it)],
      ),
    );
  }

  Widget _button(BuildContext context, DockItem it) {
    final eu = context.eu;
    if (it.primary) {
      return GestureDetector(
        onTap: it.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [eu.brand, eu.accentPurple]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(it.icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(it.label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    return IconButton(
      onPressed: it.onTap,
      tooltip: it.label,
      icon: Icon(it.icon, color: it.active ? eu.brand : eu.textMid),
    );
  }
}
