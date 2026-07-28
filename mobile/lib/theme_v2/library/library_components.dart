import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'library_controller.dart';

typedef LibraryContainerCallback = void Function(LibraryContainer container);

IconData libraryContainerIcon(LibraryContainer container) =>
    switch (container.kind) {
      LibraryContainerKind.event => Icons.calendar_today_outlined,
      LibraryContainerKind.contact => Icons.person_outline,
      LibraryContainerKind.report => Icons.insights_outlined,
      LibraryContainerKind.external => Icons.link_outlined,
      LibraryContainerKind.asset when container.id == 'todo' =>
        Icons.checklist_outlined,
      LibraryContainerKind.asset when container.id == 'notes' =>
        Icons.notes_outlined,
      LibraryContainerKind.asset => Icons.auto_awesome_mosaic_outlined,
    };

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
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: ThemeV2IconButton(
              semanticLabel: '返回',
              icon: Icons.arrow_back,
              color: tokens.muted,
              onPressed: onBack,
            ),
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: onKickerTap == null
                    ? 0
                    : ThemeV2Sizes.minTouchTarget,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  kicker,
                  style: ThemeV2Typography.mono(
                    fontSize: 9,
                    color: tokens.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: tokens.foreground,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.xs),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
      ],
    );
  }
}

class LibrarySectionLabel extends StatelessWidget {
  const LibrarySectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ThemeV2Typography.mono(
              fontSize: 9,
              color: tokens.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      key: const ValueKey('library-container-search'),
      height: ThemeV2Sizes.minTouchTarget,
      child: TextFormField(
        initialValue: value,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: '搜索容器',
          hintStyle: TextStyle(color: tokens.muted),
          prefixIcon: Icon(Icons.search, size: 18, color: tokens.muted),
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

class LibraryContainerRow extends StatelessWidget {
  const LibraryContainerRow({
    super.key,
    required this.container,
    required this.onTap,
  });

  final LibraryContainer container;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '打开 ${container.label}，${container.count} 条',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            side: BorderSide(color: tokens.border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ThemeV2Sizes.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.md,
                  vertical: ThemeV2Spacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      libraryContainerIcon(container),
                      size: 18,
                      color: tokens.accent,
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
                      '${container.count}',
                      style: ThemeV2Typography.mono(
                        fontSize: 9,
                        color: tokens.muted,
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

class LibraryPinnedMosaic extends StatelessWidget {
  const LibraryPinnedMosaic({
    super.key,
    required this.containers,
    required this.onTap,
    this.onLongPress,
    this.configure = false,
    this.onRemove,
    this.onMoveBackward,
    this.onDrop,
  });

  final List<LibraryContainer> containers;
  final LibraryContainerCallback onTap;
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
          final width = constraints.maxWidth;
          final gap = ThemeV2Spacing.xs;
          final firstWidth = (width * 0.66).floorToDouble();
          final secondWidth = width - firstWidth - gap;
          final lowerLeftWidth = (width * 0.50).floorToDouble();
          final lowerRightWidth = width - lowerLeftWidth - gap;
          final compactHeight = (178 - gap * 2) / 3;
          final slots = <Rect>[
            Rect.fromLTWH(0, 0, firstWidth, 156),
            Rect.fromLTWH(firstWidth + gap, 0, secondWidth, 156),
            Rect.fromLTWH(0, 156 + gap, lowerLeftWidth, 180),
            Rect.fromLTWH(
              lowerLeftWidth + gap,
              156 + gap,
              lowerRightWidth,
              compactHeight,
            ),
            Rect.fromLTWH(
              lowerLeftWidth + gap,
              156 + gap * 2 + compactHeight,
              lowerRightWidth,
              compactHeight,
            ),
            Rect.fromLTWH(
              lowerLeftWidth + gap,
              156 + gap * 3 + compactHeight * 2,
              lowerRightWidth,
              compactHeight,
            ),
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
                    child: _draggableTile(context, containers[index], index),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _draggableTile(
    BuildContext context,
    LibraryContainer container,
    int index,
  ) {
    final tile = _LibraryPinnedTile(
      container: container,
      index: index,
      onTap: () => onTap(container),
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
        scale: candidates.isEmpty ? 1 : 0.96,
        duration: const Duration(milliseconds: 160),
        child: child,
      ),
    );
  }
}

class _LibraryPinnedTile extends StatelessWidget {
  const _LibraryPinnedTile({
    required this.container,
    required this.index,
    required this.onTap,
    required this.configure,
    this.onLongPress,
    this.onRemove,
    this.onMoveBackward,
  });

  final LibraryContainer container;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool configure;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveBackward;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final featured = index == 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final featuredSurface = dark ? tokens.accentSoft : tokens.foreground;
    final featuredForeground = dark ? tokens.foreground : tokens.background;
    final featuredMuted = dark ? tokens.accent : tokens.background;
    final compact = index >= 3;
    return Semantics(
      label:
          '${container.label}，${container.count} 条${configure ? '，长按拖动排序' : ''}',
      button: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        excluding: !configure,
        child: Material(
          color: featured ? featuredSurface : tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              index < 3 ? ThemeV2Radii.lg : ThemeV2Radii.md,
            ),
            side: BorderSide(
              color: configure ? tokens.accent : tokens.border,
              width: configure ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('library-pinned-tile-${container.id}'),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              children: [
                Positioned(
                  left: ThemeV2Spacing.md,
                  top: ThemeV2Spacing.md,
                  child: Text(
                    '${(index + 1).toString().padLeft(2, '0')} / '
                    '${String.fromCharCode(65 + index)}',
                    style: ThemeV2Typography.mono(
                      fontSize: 8,
                      color: featured ? featuredMuted : tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  right: compact ? 0 : ThemeV2Spacing.md,
                  top: compact ? ThemeV2Spacing.xs : ThemeV2Spacing.md,
                  child: configure
                      ? Row(
                          children: [
                            _MosaicControl(
                              label: '向后移动 ${container.label}',
                              icon: Icons.arrow_forward,
                              color: tokens.accent,
                              onPressed: onMoveBackward,
                            ),
                            _MosaicControl(
                              label: '移除 ${container.label}',
                              icon: Icons.close,
                              color: tokens.accent,
                              onPressed: onRemove,
                            ),
                          ],
                        )
                      : Text(
                          '${container.count}',
                          style: ThemeV2Typography.mono(
                            fontSize: featured ? 12 : 9,
                            color: featured ? tokens.accent : tokens.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                Positioned(
                  left: compact ? 42 : ThemeV2Spacing.md,
                  right: configure && compact ? 90 : ThemeV2Spacing.sm,
                  bottom: compact ? ThemeV2Spacing.lg : ThemeV2Spacing.md,
                  child: Text(
                    container.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: featured ? featuredForeground : tokens.foreground,
                      fontSize: index == 0
                          ? 22
                          : index < 3
                          ? 17
                          : 13,
                      fontWeight: FontWeight.w600,
                    ),
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
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ThemeV2Sizes.minTouchTarget,
      height: ThemeV2Sizes.minTouchTarget,
      child: ThemeV2IconButton(
        semanticLabel: label,
        icon: icon,
        iconSize: 15,
        color: color,
        onPressed: onPressed,
      ),
    );
  }
}
