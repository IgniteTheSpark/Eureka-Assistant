import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';

class AssetLongText extends StatelessWidget {
  const AssetLongText({
    super.key,
    required this.text,
    required this.expanded,
    required this.onExpand,
  });

  final String text;
  final bool expanded;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(height: 1.55);
    if (expanded) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 480.0;
          final height = math.min(480.0, available);
          return SizedBox(
            key: const ValueKey('asset-long-text-full'),
            height: height,
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.only(right: ThemeV2Spacing.xs),
              child: SelectableText(text, style: style),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 6,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return SizedBox(
          key: const ValueKey('asset-long-text-half'),
          height: 120,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Text(
                text,
                maxLines: 6,
                overflow: TextOverflow.clip,
                style: style,
              ),
              if (overflows) ...[
                Positioned(
                  key: const ValueKey('asset-long-text-fade'),
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 42,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            context.themeV2.surface.withValues(alpha: 0),
                            context.themeV2.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: TextButton(
                    onPressed: onExpand,
                    child: const Text('查看全部'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
