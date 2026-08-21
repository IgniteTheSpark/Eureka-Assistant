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
    this.rekaCockpit,
  }) : assert(selectedIndex >= 0 && selectedIndex < 3);

  static const safeAreaPaddingKey = Key('theme-v2-dock-safe-area');
  static const compositionKey = Key('theme-v2-dock-composition');
  static const dockKey = Key('theme-v2-floating-dock');
  static const cockpitKey = Key('theme-v2-reka-cockpit');
  static const double elevation = 8;
  static const double lightRadius = 18;
  static Color get lightShadowColor => Colors.black.withValues(alpha: 0.12);
  static const Size shellSize = Size(248, 64);
  static const double cockpitExtent = 76;
  static const double cockpitTargetExtent = 72;
  static const double cockpitRise = 34;
  static const double compositionHeight = 98;
  static const double contentGap = 12;
  static const double companionContentClearance =
      compositionHeight + contentGap;
  static const double contentClearance = companionContentClearance;
  static const double cockpitTopAboveDockBottom = compositionHeight;
  static const double miniRekaGap = 6;
  static const double viewportBottomPadding = 35;
  static const double dockHeight = 64;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? rekaCockpit;

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
          key: compositionKey,
          width: shellSize.width,
          height: compositionHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: shellSize.height,
                child: ThemeV2GlassChrome(
                  materialKey: dockKey,
                  elevation: elevation,
                  shadowColor: dark
                      ? Colors.black.withValues(alpha: 0.22)
                      : lightShadowColor,
                  borderRadius: BorderRadius.circular(dark ? 20 : lightRadius),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Row(
                          children: [
                            Expanded(child: _destination(0)),
                            Expanded(child: _destination(1)),
                          ],
                        ),
                      ),
                      const SizedBox(width: cockpitExtent),
                      SizedBox(width: 84, child: _destination(2)),
                    ],
                  ),
                ),
              ),
              Positioned(
                key: cockpitKey,
                left: (shellSize.width - cockpitExtent) / 2,
                top: 0,
                width: cockpitExtent,
                height: cockpitTargetExtent,
                child: _DockCockpit(child: rekaCockpit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destination(int index) => _DockDestination(
    icon: selectedIndex == index
        ? _destinations[index].selectedIcon
        : _destinations[index].icon,
    label: _destinations[index].label,
    selected: selectedIndex == index,
    onPressed: () => onDestinationSelected(index),
  );
}

class _DockCockpit extends StatelessWidget {
  const _DockCockpit({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(30),
          bottom: Radius.circular(22),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.surface.withValues(alpha: dark ? .96 : .92),
            tokens.background.withValues(alpha: dark ? .9 : .84),
          ],
        ),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .26 : .12),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: tokens.accent.withValues(alpha: dark ? .09 : .07),
            blurRadius: 16,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Center(child: child),
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
