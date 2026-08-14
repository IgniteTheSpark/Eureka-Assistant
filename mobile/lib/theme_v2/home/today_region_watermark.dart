import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

class TodayRegionWatermark extends StatelessWidget {
  const TodayRegionWatermark({
    super.key,
    required this.count,
    required this.label,
    required this.alignment,
    this.padding = const EdgeInsets.fromLTRB(18, 12, 18, 12),
    this.onPressed,
    this.semanticLabel,
  });

  final int count;
  final String label;
  final Alignment alignment;
  final EdgeInsets padding;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final tokens = context.themeV2;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final leftAligned = alignment.x < 0;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: leftAligned
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            ExcludeSemantics(
              child: IgnorePointer(
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: tokens.accent.withValues(alpha: dark ? .14 : .07),
                    fontFamily: 'Geist',
                    fontSize: 112,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -6,
                    height: .9,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Semantics(
              button: onPressed != null,
              label: onPressed == null ? null : semanticLabel,
              onTap: onPressed,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Align(
                    alignment: leftAligned
                        ? Alignment.topLeft
                        : Alignment.topRight,
                    child: ExcludeSemantics(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: tokens.accent.withValues(
                            alpha: dark ? .68 : .44,
                          ),
                          fontFamily: 'Geist Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
