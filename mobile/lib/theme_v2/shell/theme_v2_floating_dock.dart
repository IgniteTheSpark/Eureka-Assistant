import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

class ThemeV2FloatingDock extends StatelessWidget {
  const ThemeV2FloatingDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < 3);

  static const safeAreaPaddingKey = Key('theme-v2-dock-safe-area');
  static const dockKey = Key('theme-v2-floating-dock');
  static const double contentClearance = 80;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = <({IconData icon, String label})>[
    (icon: Icons.wb_sunny_outlined, label: '今日'),
    (icon: Icons.calendar_today_outlined, label: '日历'),
    (icon: Icons.grid_view_outlined, label: '资产'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final availableWidth =
        (MediaQuery.sizeOf(context).width - (ThemeV2Spacing.md * 2))
            .clamp(0, 420)
            .toDouble();
    final tokens = context.themeV2;
    return Padding(
      key: safeAreaPaddingKey,
      padding: EdgeInsets.fromLTRB(
        ThemeV2Spacing.md,
        0,
        ThemeV2Spacing.md,
        bottom + ThemeV2Spacing.md,
      ),
      child: SizedBox(
        width: availableWidth,
        child: Material(
          key: dockKey,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.22),
          color: tokens.surface.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
            side: BorderSide(color: tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (var index = 0; index < _destinations.length; index++)
                  Expanded(
                    child: _DockDestination(
                      icon: _destinations[index].icon,
                      label: _destinations[index].label,
                      selected: selectedIndex == index,
                      onPressed: () => onDestinationSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final color = selected ? tokens.accent : tokens.muted;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.xs,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
