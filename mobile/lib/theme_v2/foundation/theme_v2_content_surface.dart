import 'package:flutter/material.dart';

import 'theme_v2_theme.dart';

enum ThemeV2ContentOpacity { dense, card }

class ThemeV2ContentSurface extends StatelessWidget {
  const ThemeV2ContentSurface({
    super.key,
    required this.child,
    this.opacity = ThemeV2ContentOpacity.dense,
  });

  final Widget child;
  final ThemeV2ContentOpacity opacity;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.themeV2.surface.withValues(
      alpha: opacity == ThemeV2ContentOpacity.dense ? .96 : .90,
    ),
    child: child,
  );
}
