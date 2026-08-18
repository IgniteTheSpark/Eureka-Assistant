import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import 'theme_v2_glass_chrome.dart';

class ThemeV2FloatingDock extends StatelessWidget {
  const ThemeV2FloatingDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < 3);

  static const safeAreaPaddingKey = Key('theme-v2-dock-safe-area');
  static const dockKey = Key('theme-v2-floating-dock');
  static const double elevation = 8;
  static const double lightRadius = 18;
  static Color get lightShadowColor => Colors.black.withValues(alpha: 0.12);
  static const double contentClearance = 80;
  static const double viewportBottomPadding = 35;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations =
      <({IconData icon, IconData selectedIcon, String label})>[
        (
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: '今日',
        ),
        (
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month_outlined,
          label: '日历',
        ),
        (
          icon: Icons.local_library_outlined,
          selectedIcon: Icons.local_library_outlined,
          label: '资产',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        key: safeAreaPaddingKey,
        padding: EdgeInsets.only(
          bottom: math.max(bottom, viewportBottomPadding),
        ),
        child: SizedBox(
          width: 169,
          child: ThemeV2GlassChrome(
            materialKey: dockKey,
            elevation: elevation,
            shadowColor: dark
                ? Colors.black.withValues(alpha: 0.22)
                : lightShadowColor,
            borderRadius: BorderRadius.circular(dark ? 20 : lightRadius),
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  for (var index = 0; index < _destinations.length; index++)
                    Expanded(
                      child: _DockDestination(
                        icon: selectedIndex == index
                            ? _destinations[index].selectedIcon
                            : _destinations[index].icon,
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
