import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../markdown/theme_v2_markdown_text.dart';

class AssetTextValue extends StatefulWidget {
  const AssetTextValue({
    super.key,
    required this.text,
    required this.markdown,
    required this.full,
    required this.onExpand,
  });

  final String text;
  final bool markdown;
  final bool full;
  final VoidCallback onExpand;

  @override
  State<AssetTextValue> createState() => _AssetTextValueState();
}

class _AssetTextValueState extends State<AssetTextValue> {
  static const _collapsedLines = 6;
  static const _readingMaxHeight = 480.0;

  double? _contentHeight;

  @override
  void didUpdateWidget(AssetTextValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.markdown != widget.markdown) {
      _contentHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(height: 1.55);
    final lineHeight =
        (style?.fontSize ?? 14) *
        (style?.height ?? 1.55) *
        MediaQuery.textScalerOf(context).scale(1);
    final collapsedHeight = lineHeight * _collapsedLines;

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget measuredContent() => _MeasureSize(
          onChange: (size) {
            if (!mounted ||
                (_contentHeight != null &&
                    (_contentHeight! - size.height).abs() < 0.5)) {
              return;
            }
            setState(() => _contentHeight = size.height);
          },
          child: SizedBox(width: constraints.maxWidth, child: _content(style)),
        );

        final measured = _contentHeight;
        if (measured == null) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _readingMaxHeight),
            child: SingleChildScrollView(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              child: measuredContent(),
            ),
          );
        }

        if (widget.full) {
          if (measured <= _readingMaxHeight) {
            return KeyedSubtree(
              key: const ValueKey('asset-text-natural'),
              child: measuredContent(),
            );
          }
          return SizedBox(
            key: const ValueKey('asset-text-full-scroll'),
            height: _readingMaxHeight,
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.only(right: ThemeV2Spacing.xs),
              child: measuredContent(),
            ),
          );
        }

        if (measured <= collapsedHeight + 0.5) {
          return KeyedSubtree(
            key: const ValueKey('asset-text-natural'),
            child: measuredContent(),
          );
        }

        return SizedBox(
          key: const ValueKey('asset-text-collapsed'),
          height: collapsedHeight + 38,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: collapsedHeight,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: math.max(measured, collapsedHeight),
                    child: measuredContent(),
                  ),
                ),
              ),
              Positioned(
                key: const ValueKey('asset-text-fade'),
                left: 0,
                right: 0,
                bottom: 30,
                height: 44,
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
                  onPressed: widget.onExpand,
                  child: const Text('展开全文'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _content(TextStyle? style) {
    if (!widget.markdown) {
      return SelectableText(widget.text, style: style);
    }
    return SelectionArea(
      child: ThemeV2MarkdownText(widget.text, baseStyle: style),
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reportedSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_reportedSize == child?.size) return;
    _reportedSize = child?.size;
    final measured = _reportedSize;
    if (measured == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(measured));
  }
}
