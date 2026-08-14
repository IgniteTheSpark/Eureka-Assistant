import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

class TodayRegionWatermark extends StatelessWidget {
  const TodayRegionWatermark({
    super.key,
    required this.count,
    required this.label,
    required this.alignment,
    this.padding = const EdgeInsets.fromLTRB(18, 12, 18, 12),
  });

  final int count;
  final String label;
  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final tokens = context.themeV2;
    final leftAligned = alignment.x < 0;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: leftAligned
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    color: tokens.accent.withValues(alpha: .07),
                    fontFamily: 'Geist',
                    fontSize: 112,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -6,
                    height: .9,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.accent.withValues(alpha: .44),
                    fontFamily: 'Geist Mono',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    height: 1.15,
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
