import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'asset_card_display.dart';

enum AssetCardVariant { minimalRow, minimalLine, richCard, iconTime }

class ThemeV2AssetCard extends StatefulWidget {
  const ThemeV2AssetCard({
    super.key,
    required this.variant,
    required this.data,
    this.onOpen,
    this.disabled = false,
    this.height,
  });

  final AssetCardVariant variant;
  final AssetCardViewData data;
  final VoidCallback? onOpen;
  final bool disabled;
  final double? height;

  @override
  State<ThemeV2AssetCard> createState() => _ThemeV2AssetCardState();
}

class _ThemeV2AssetCardState extends State<ThemeV2AssetCard> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (widget.variant) {
      AssetCardVariant.richCard => _RichCard(
        data: widget.data,
        height: widget.height ?? 96,
      ),
      AssetCardVariant.minimalRow => _MinimalRow(
        data: widget.data,
        height: widget.height ?? 52,
      ),
      AssetCardVariant.minimalLine => _MinimalLine(
        data: widget.data,
        height: widget.height ?? 24,
      ),
      AssetCardVariant.iconTime => _IconTime(
        data: widget.data,
        height: widget.height ?? 54,
      ),
    };
    final enabled = !widget.disabled && widget.onOpen != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '打开${widget.data.skillLabel}：${widget.data.primaryValue}',
      onTap: enabled ? widget.onOpen : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onOpen : null,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          child: AnimatedScale(
            key: const ValueKey('asset-card-press-transform'),
            scale: !reduceMotion && _pressed ? 0.98 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _IconTime extends StatelessWidget {
  const _IconTime({required this.data, required this.height});

  final AssetCardViewData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: ThemeV2Sizes.minTouchTarget,
        minHeight: ThemeV2Sizes.minTouchTarget,
      ),
      child: SizedBox(
        height: height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('asset-card-mark'),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                data.mark,
                maxLines: 1,
                style: TextStyle(color: tokens.accent, fontSize: 17, height: 1),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              key: const ValueKey('asset-card-time'),
              data.timeLabel ?? '',
              maxLines: 1,
              style: TextStyle(
                color: tokens.muted,
                fontFamily: 'Geist Mono',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinimalLine extends StatelessWidget {
  const _MinimalLine({required this.data, required this.height});

  final AssetCardViewData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Text(
            key: const ValueKey('asset-card-skill'),
            data.skillLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '·',
              style: TextStyle(color: tokens.muted, fontSize: 10, height: 1),
            ),
          ),
          Expanded(
            child: Text(
              key: const ValueKey('asset-card-primary'),
              data.primaryValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimalRow extends StatelessWidget {
  const _MinimalRow({required this.data, required this.height});

  final AssetCardViewData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (data.timeLabel case final time?)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    key: const ValueKey('asset-card-time'),
                    time,
                    style: TextStyle(
                      color: tokens.muted,
                      fontFamily: 'Geist Mono',
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                ),
              Container(
                key: const ValueKey('asset-card-mark'),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  data.mark,
                  maxLines: 1,
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 15,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                key: const ValueKey('asset-card-skill'),
                data.skillLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.muted, fontSize: 11, height: 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '·',
                  style: TextStyle(
                    color: tokens.muted,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  key: const ValueKey('asset-card-primary'),
                  data.primaryValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RichCard extends StatelessWidget {
  const _RichCard({required this.data, required this.height});

  final AssetCardViewData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final compact = height <= 86;
    final markSize = compact ? 40.0 : 44.0;
    final values = data.secondaryValues
        .where((value) => value.trim().isNotEmpty)
        .take(3)
        .toList(growable: false);

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          border: Border.all(color: tokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                key: const ValueKey('asset-card-mark'),
                width: markSize,
                height: markSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(compact ? 13 : 14),
                ),
                child: Text(
                  data.mark,
                  maxLines: 1,
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: compact ? 18 : 20,
                    height: 1,
                  ),
                ),
              ),
              SizedBox(width: compact ? 16 : 18),
              Expanded(
                child: values.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: _PrimaryText(value: data.primaryValue),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PrimaryText(value: data.primaryValue),
                          const SizedBox(height: 6),
                          Container(
                            key: const ValueKey('asset-card-divider'),
                            width: double.infinity,
                            height: 1,
                            color: tokens.border,
                          ),
                          const SizedBox(height: 6),
                          _SecondaryRow(values: values),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryText extends StatelessWidget {
  const _PrimaryText({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.themeV2.foreground,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('asset-card-secondary-row'),
      children: [
        for (var index = 0; index < values.length; index++) ...[
          if (index > 0)
            Text(
              ' · ',
              style: TextStyle(
                color: context.themeV2.muted,
                fontSize: 12,
                height: 1.1,
              ),
            ),
          Flexible(
            child: Text(
              key: ValueKey('asset-card-secondary-$index'),
              values[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.themeV2.muted,
                fontSize: 12,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
