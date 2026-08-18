import 'dart:ui';

import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

class ThemeV2GlassChrome extends StatelessWidget {
  const ThemeV2GlassChrome({
    super.key,
    required this.borderRadius,
    required this.child,
    this.materialKey,
    this.elevation = 8,
    this.shadowColor,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final Key? materialKey;
  final double elevation;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          key: materialKey,
          elevation: elevation,
          shadowColor: shadowColor,
          color: tokens.surface.withValues(alpha: dark ? .88 : .82),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}
