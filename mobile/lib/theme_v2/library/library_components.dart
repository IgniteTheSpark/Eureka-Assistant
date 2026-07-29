import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'library_models.dart';

typedef LibraryContainerCallback =
    void Function(LibraryContainerSummary container);

IconData libraryContainerIcon(LibraryContainerSummary container) =>
    switch (container.type) {
      LibraryContainerType.event => Icons.calendar_today_outlined,
      LibraryContainerType.contact => Icons.person_outline,
      LibraryContainerType.todo => Icons.checklist_outlined,
      LibraryContainerType.notes => Icons.notes_outlined,
      LibraryContainerType.custom => Icons.auto_awesome_mosaic_outlined,
    };

class LibrarySectionLabel extends StatelessWidget {
  const LibrarySectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: ThemeV2Typography.mono(
                fontSize: 9,
                color: context.themeV2.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class LibraryStatsBar extends StatelessWidget {
  const LibraryStatsBar({
    super.key,
    required this.assetCount,
    required this.containerCount,
    required this.onOpenContainerIndex,
    required this.onOpenAllContainers,
  });

  final int assetCount;
  final int containerCount;
  final VoidCallback onOpenContainerIndex;
  final VoidCallback onOpenAllContainers;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('library-stats-entry'),
      height: 54,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatsAction(
              semanticLabel: '打开资产容器索引',
              onTap: onOpenContainerIndex,
              child: Row(
                children: [
                  _Stat(value: assetCount, label: '资产'),
                  const SizedBox(width: ThemeV2Spacing.xl),
                  _Stat(value: containerCount, label: '容器'),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 30, color: tokens.border),
          _StatsAction(
            semanticLabel: '打开全部容器',
            onTap: onOpenAllContainers,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_view_outlined, color: tokens.accent, size: 17),
                const SizedBox(width: ThemeV2Spacing.sm),
                Text(
                  '全部容器',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: ThemeV2Spacing.xs),
                Icon(Icons.chevron_right, color: tokens.muted, size: 17),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsAction extends StatelessWidget {
  const _StatsAction({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.md),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: ThemeV2Spacing.xs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: context.themeV2.muted),
        ),
      ],
    );
  }
}

class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 44,
    this.hintText = '搜索容器',
    this.fieldKey,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final double height;
  final String hintText;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      key: fieldKey ?? const ValueKey('library-container-search'),
      height: height,
      child: TextFormField(
        key: ValueKey('library-container-search-input-$value'),
        initialValue: value,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: tokens.muted),
          prefixIcon: Icon(Icons.search, size: 17, color: tokens.muted),
          suffixIcon: value.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () => onChanged(''),
                  icon: Icon(Icons.close, size: 17, color: tokens.muted),
                ),
          filled: true,
          fillColor: tokens.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: ThemeV2Spacing.md,
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: tokens.border),
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: tokens.accent),
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          ),
        ),
      ),
    );
  }
}

class LibraryMetricStrip extends StatelessWidget {
  const LibraryMetricStrip({
    super.key,
    required this.containerCount,
    required this.assetCount,
    required this.customCount,
  });

  final int containerCount;
  final int assetCount;
  final int customCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('library-all-stats'),
      height: 76,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.themeV2.border),
          bottom: BorderSide(color: context.themeV2.border),
        ),
      ),
      child: Row(
        children: [
          _Metric(value: containerCount, label: '容器'),
          _Metric(value: assetCount, label: '资产'),
          _Metric(value: customCount, label: '自定义'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: ThemeV2Typography.mono(
              fontSize: 8,
              color: context.themeV2.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryPinnedMosaic extends StatelessWidget {
  const LibraryPinnedMosaic({
    super.key,
    required this.containers,
    this.onTap,
    this.onLongPress,
    this.configure = false,
    this.onRemove,
    this.onMoveBackward,
    this.onDrop,
  });

  final List<LibraryContainerSummary> containers;
  final LibraryContainerCallback? onTap;
  final VoidCallback? onLongPress;
  final bool configure;
  final LibraryContainerCallback? onRemove;
  final LibraryContainerCallback? onMoveBackward;
  final void Function(int oldIndex, int newIndex)? onDrop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('library-pinned-mosaic'),
      height: 340,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final usable = constraints.maxWidth - gap;
          final firstWidth = usable * 247 / 369;
          final secondWidth = constraints.maxWidth - gap - firstWidth;
          final lowerLeftWidth = usable * 186 / 369;
          final lowerRightWidth = constraints.maxWidth - gap - lowerLeftWidth;
          final slots = [
            Rect.fromLTWH(0, 0, firstWidth, 156),
            Rect.fromLTWH(firstWidth + gap, 0, secondWidth, 156),
            Rect.fromLTWH(0, 162, lowerLeftWidth, 178),
            Rect.fromLTWH(lowerLeftWidth + gap, 162, lowerRightWidth, 54),
            Rect.fromLTWH(lowerLeftWidth + gap, 222, lowerRightWidth, 54),
            Rect.fromLTWH(lowerLeftWidth + gap, 282, lowerRightWidth, 54),
          ];
          return Stack(
            children: [
              for (
                var index = 0;
                index < containers.length && index < slots.length;
                index++
              )
                Positioned.fromRect(
                  rect: slots[index],
                  child: _MosaicDropSlot(
                    index: index,
                    onDrop: onDrop,
                    child: _draggableTile(containers[index], index),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _draggableTile(LibraryContainerSummary container, int index) {
    final tile = _LibraryPinnedTile(
      container: container,
      index: index,
      onTap: onTap == null ? null : () => onTap!(container),
      onLongPress: configure ? null : onLongPress,
      configure: configure,
      onRemove: onRemove == null ? null : () => onRemove!(container),
      onMoveBackward: onMoveBackward == null
          ? null
          : () => onMoveBackward!(container),
    );
    if (!configure || onDrop == null) return tile;
    return LongPressDraggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 140, height: 70, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: tile),
      child: tile,
    );
  }
}

class _MosaicDropSlot extends StatelessWidget {
  const _MosaicDropSlot({
    required this.index,
    required this.child,
    this.onDrop,
  });

  final int index;
  final Widget child;
  final void Function(int oldIndex, int newIndex)? onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onDrop?.call(details.data, index),
      builder: (context, candidates, rejected) => AnimatedScale(
        scale: candidates.isEmpty ? 1 : .96,
        duration: const Duration(milliseconds: 160),
        child: child,
      ),
    );
  }
}

class _LibraryPinnedTile extends StatefulWidget {
  const _LibraryPinnedTile({
    required this.container,
    required this.index,
    required this.configure,
    this.onTap,
    this.onLongPress,
    this.onRemove,
    this.onMoveBackward,
  });

  final LibraryContainerSummary container;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool configure;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveBackward;

  @override
  State<_LibraryPinnedTile> createState() => _LibraryPinnedTileState();
}

class _LibraryPinnedTileState extends State<_LibraryPinnedTile> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final featured = widget.index == 0;
    final compact = widget.index >= 3;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final featuredSurface = dark ? tokens.accentSoft : tokens.foreground;
    final featuredForeground = dark ? tokens.foreground : tokens.background;
    return Semantics(
      label:
          '${widget.container.label}，${widget.container.totalCount} 条'
          '${widget.configure ? '，可拖动排序，也可使用移动和移除按钮' : ''}',
      button: widget.onTap != null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        key: ValueKey('library-pinned-press-transform-${widget.container.id}'),
        scale: _pressed && !reducedMotion ? .98 : 1,
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: Material(
          color: featured ? featuredSurface : tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              widget.index < 3 ? ThemeV2Radii.lg : ThemeV2Radii.md,
            ),
            side: BorderSide(
              color: widget.configure ? tokens.accent : tokens.border,
              width: widget.configure ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('library-pinned-tile-${widget.container.id}'),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onTapDown: (_) => _setPressed(true),
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  top: compact ? 19 : 14,
                  child: Text(
                    (widget.index + 1).toString().padLeft(2, '0'),
                    style: ThemeV2Typography.mono(
                      fontSize: compact ? 8 : 9,
                      color: featured ? tokens.accent : tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  right: widget.configure && compact ? 88 : 14,
                  top: compact ? 17 : 12,
                  child: Text(
                    '${widget.container.totalCount}',
                    style: ThemeV2Typography.mono(
                      fontSize: compact ? 14 : 18,
                      color: featured ? tokens.accent : tokens.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  left: compact ? 45 : 14,
                  right: widget.configure && compact ? 92 : 12,
                  bottom: compact ? 17 : 14,
                  child: Text(
                    widget.container.label,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: featured ? featuredForeground : tokens.foreground,
                      fontSize: widget.index == 0
                          ? 23
                          : widget.index < 3
                          ? 18
                          : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.configure)
                  Positioned(
                    right: compact ? 0 : 4,
                    bottom: compact ? 5 : 4,
                    child: Row(
                      children: [
                        _MosaicControl(
                          label: '向后移动 ${widget.container.label}',
                          icon: Icons.arrow_forward,
                          onPressed: widget.onMoveBackward,
                        ),
                        _MosaicControl(
                          label: '移除 ${widget.container.label}',
                          icon: Icons.close,
                          onPressed: widget.onRemove,
                        ),
                      ],
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

class _MosaicControl extends StatelessWidget {
  const _MosaicControl({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ThemeV2IconButton(
      semanticLabel: label,
      icon: icon,
      iconSize: 15,
      color: context.themeV2.accent,
      onPressed: onPressed,
    );
  }
}

class LibrarySystemContainerCard extends StatelessWidget {
  const LibrarySystemContainerCard({
    super.key,
    required this.container,
    required this.onTap,
  });

  final LibraryContainerSummary container;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ContainerRowBase(
    container: container,
    onTap: onTap,
    height: 56,
    surfaced: true,
    showMarkBox: false,
  );
}

class LibraryCustomContainerRow extends StatelessWidget {
  const LibraryCustomContainerRow({
    super.key,
    required this.container,
    required this.onTap,
  });

  final LibraryContainerSummary container;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ContainerRowBase(
    container: container,
    onTap: onTap,
    height: 50,
    surfaced: false,
    showMarkBox: false,
  );
}

class LibraryDirectoryRow extends StatelessWidget {
  const LibraryDirectoryRow({
    super.key,
    required this.container,
    required this.onTap,
  });

  final LibraryContainerSummary container;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ContainerRowBase(
    container: container,
    onTap: onTap,
    height: 54,
    surfaced: false,
    showMarkBox: true,
  );
}

class _ContainerRowBase extends StatelessWidget {
  const _ContainerRowBase({
    required this.container,
    required this.onTap,
    required this.height,
    required this.surfaced,
    required this.showMarkBox,
  });

  final LibraryContainerSummary container;
  final VoidCallback onTap;
  final double height;
  final bool surfaced;
  final bool showMarkBox;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '打开${container.label}，${container.totalCount} 条',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: surfaced ? tokens.surface : Colors.transparent,
          shape: surfaced
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
                  side: BorderSide(color: tokens.border),
                )
              : Border(bottom: BorderSide(color: tokens.border)),
          child: InkWell(
            onTap: onTap,
            borderRadius: surfaced
                ? BorderRadius.circular(ThemeV2Radii.lg)
                : null,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (showMarkBox)
                      Container(
                        key: ValueKey('library-directory-mark-${container.id}'),
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                        ),
                        child: Text(
                          container.mark,
                          style: TextStyle(color: tokens.accent, fontSize: 14),
                        ),
                      )
                    else
                      SizedBox(
                        width: 28,
                        child: Text(
                          container.mark,
                          style: TextStyle(color: tokens.accent, fontSize: 16),
                        ),
                      ),
                    const SizedBox(width: ThemeV2Spacing.md),
                    Expanded(
                      child: Text(
                        container.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${container.totalCount}',
                      style: ThemeV2Typography.mono(
                        fontSize: 12,
                        color: tokens.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Icon(Icons.chevron_right, size: 18, color: tokens.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryAvailableContainerTile extends StatelessWidget {
  const LibraryAvailableContainerTile({
    super.key,
    required this.container,
    required this.enabled,
    required this.onTap,
  });

  final LibraryContainerSummary container;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final label = enabled
        ? '加入${container.label}'
        : '无法加入${container.label}，常驻容器最多 6 个';
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            side: BorderSide(color: tokens.border),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      container.mark,
                      style: TextStyle(
                        color: enabled ? tokens.accent : tokens.muted,
                      ),
                    ),
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Expanded(
                      child: Text(
                        container.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.add,
                      size: 18,
                      color: enabled ? tokens.accent : tokens.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Transitional name retained until every directory surface is on its
/// canonical system/custom row variant.
class LibraryContainerRow extends StatelessWidget {
  const LibraryContainerRow({
    super.key,
    required this.container,
    required this.onTap,
  });

  final LibraryContainerSummary container;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => container.isSystem
      ? LibrarySystemContainerCard(container: container, onTap: onTap)
      : LibraryCustomContainerRow(container: container, onTap: onTap);
}

/// Transitional header retained for Asset screens. Library surfaces themselves
/// use native title/back composition and never render breadcrumbs.
class LibraryScreenHeader extends StatelessWidget {
  const LibraryScreenHeader({
    super.key,
    required this.kicker,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.onKickerTap,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onKickerTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null)
          ThemeV2IconButton(
            semanticLabel: '返回',
            icon: Icons.arrow_back,
            color: context.themeV2.muted,
            onPressed: onBack,
          ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: onKickerTap == null ? null : '打开资产容器索引',
          button: onKickerTap != null,
          onTap: onKickerTap,
          excludeSemantics: onKickerTap != null,
          child: InkWell(
            onTap: onKickerTap,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: context.themeV2.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.xs),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
          ),
        ],
      ],
    );
  }
}
