import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

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
    final tokens = context.themeV2;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final leftAligned = alignment.x < 0;
    final countChild = ExcludeSemantics(
      child: Text(
        '${count < 0 ? 0 : count}',
        style: TextStyle(
          color: tokens.accent.withValues(alpha: dark ? .18 : .10),
          fontFamily: 'Geist',
          fontSize: 96,
          fontWeight: FontWeight.w700,
          letterSpacing: -6,
          height: .9,
        ),
      ),
    );
    final labelChild = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: Align(
        alignment: Alignment(leftAligned ? -1 : 1, labelFirst ? -1 : 1),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              color: tokens.accent.withValues(alpha: dark ? .76 : .60),
              fontFamily: 'Geist Mono',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
    final visualChildren = labelFirst
        ? <Widget>[labelChild, const SizedBox(height: 7), countChild]
        : <Widget>[countChild, const SizedBox(height: 7), labelChild];
    final watermark = Semantics(
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
    );
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: onPressed == null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onPressed,
          child: Padding(
            padding: padding,
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.hasBoundedHeight
                  ? OverflowBox(
                      alignment: alignment,
                      minWidth: 0,
                      maxWidth: constraints.hasBoundedWidth
                          ? double.infinity
                          : null,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      fit: OverflowBoxFit.deferToChild,
                      child: watermark,
                    )
                  : watermark,
            ),
          ),
        ),
      ),
    );
  }
}
