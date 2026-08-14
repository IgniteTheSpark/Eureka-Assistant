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
    this.labelFirst = false,
  });

  final int count;
  final String label;
  final Alignment alignment;
  final EdgeInsets padding;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool labelFirst;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final tokens = context.themeV2;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final leftAligned = alignment.x < 0;
    final countChild = GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      excludeFromSemantics: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Text(
          '$count',
          style: TextStyle(
            color: tokens.accent.withValues(alpha: dark ? .14 : .07),
            fontFamily: 'Geist',
            fontSize: 88,
            fontWeight: FontWeight.w700,
            letterSpacing: -6,
            height: .9,
          ),
        ),
      ),
    );
    final labelChild = GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      excludeFromSemantics: true,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Align(
          alignment: Alignment(leftAligned ? -1 : 1, labelFirst ? -1 : 1),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                color: tokens.accent.withValues(alpha: dark ? .68 : .44),
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
    );
    final visualChildren = labelFirst
        ? <Widget>[labelChild, const SizedBox(height: 7), countChild]
        : <Widget>[countChild, const SizedBox(height: 7), labelChild];
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: Semantics(
          button: onPressed != null,
          label: onPressed == null ? null : semanticLabel,
          onTap: onPressed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: leftAligned
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: visualChildren,
          ),
        ),
      ),
    );
  }
}
