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
    final tokens = context.themeV2;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        key: safeAreaPaddingKey,
        padding: EdgeInsets.only(bottom: bottom + ThemeV2Spacing.md),
        child: SizedBox(
          width: 169,
          child: Material(
            key: dockKey,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.22),
            color: const Color(0xFF101319).withValues(alpha: 0.98),
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
            child: Center(child: Icon(icon, size: 20, color: color)),
          ),
        ),
      ),
    );
  }
}
