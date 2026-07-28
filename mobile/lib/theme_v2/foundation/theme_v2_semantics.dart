import 'package:flutter/material.dart';

import 'theme_v2_tokens.dart';

/// Ensures a visual control participates in layout with at least a 44px hitbox.
class ThemeV2HitTarget extends StatelessWidget {
  const ThemeV2HitTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: ThemeV2Sizes.minTouchTarget,
        minHeight: ThemeV2Sizes.minTouchTarget,
      ),
      child: child,
    );
  }
}

/// Standard icon action with a single, explicit accessible label.
class ThemeV2IconButton extends StatelessWidget {
  const ThemeV2IconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    this.color,
    this.iconSize = 20,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: SizedBox.square(
            dimension: ThemeV2Sizes.minTouchTarget,
            child: IconButton(
              tooltip: semanticLabel,
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.expand(),
              icon: Icon(icon, color: color, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
