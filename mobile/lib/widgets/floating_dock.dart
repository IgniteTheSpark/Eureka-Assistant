import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// One entry in the floating dock.
class DockItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  /// The Agent entry renders as a brand→purple gradient pill (per the web dock).
  final bool primary;

  /// Render a thin vertical divider before this item — groups the dock the way
  /// the web FloatingDock does (today/library │ create/flash │ Agent).
  final bool leadingDivider;

  const DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.primary = false,
    this.leadingDivider = false,
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          // layered: a soft wide ambient lift + a tighter contact shadow, so the
          // capsule reads as floating with depth rather than a flat plate.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              // top-lit → bottom-shaded glass fill (dimensionality, both themes).
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  eu.surfaceRaised.withValues(alpha: 0.90),
                  eu.surface.withValues(alpha: 0.70),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: eu.border),
            ),
            // Content-width capsule centered over the page (matches the web
            // dock), grouped by thin dividers.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final it in items) ...[
                  if (it.leadingDivider) _divider(eu),
                  _button(context, it),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(EurekaColors eu) => Container(
        width: 1,
        height: 22,
        color: eu.border,
        margin: const EdgeInsets.symmetric(horizontal: 5),
      );

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
            boxShadow: [
              BoxShadow(
                color: eu.brand.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
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
