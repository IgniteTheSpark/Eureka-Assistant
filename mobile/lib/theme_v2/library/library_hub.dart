import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'create_skill_action.dart';
import 'library_components.dart';
import 'library_controller.dart';

class LibraryHub extends StatelessWidget {
  const LibraryHub({
    super.key,
    required this.controller,
    required this.onOpenContainer,
    required this.onOpenContainerIndex,
    required this.onOpenAllContainers,
    required this.onConfigurePinned,
    required this.onCreateSkill,
    this.onOpenRecent,
  });

  final LibraryController controller;
  final LibraryContainerCallback onOpenContainer;
  final VoidCallback onOpenContainerIndex;
  final VoidCallback onOpenAllContainers;
  final VoidCallback onConfigurePinned;
  final VoidCallback onCreateSkill;
  final ValueChanged<LibraryRecentItem>? onOpenRecent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return ListView(
          key: const PageStorageKey('theme-v2-library-hub'),
          padding: const EdgeInsets.fromLTRB(
            ThemeV2Spacing.lg,
            ThemeV2Spacing.md,
            ThemeV2Spacing.lg,
            ThemeV2Spacing.xl,
          ),
          children: [
            LibraryScreenHeader(
              kicker: 'LIBRARY / ${snapshot?.containerCount ?? 0} CONTAINERS',
              title: '资产库',
              subtitle: snapshot == null
                  ? '你的记录，按使用方式组织。'
                  : '${snapshot.containerCount} 个容器 · '
                        '${snapshot.activeSignalCount} 个活跃信号',
              onKickerTap: onOpenContainerIndex,
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            _LibraryStatsEntry(
              assetCount: snapshot?.assetTotal ?? 0,
              containerCount: snapshot?.containerCount ?? 0,
              onTap: onOpenAllContainers,
            ),
            if (controller.statusMessage case final status?) ...[
              const SizedBox(height: ThemeV2Spacing.sm),
              _StatusBanner(message: status, onRetry: controller.retry),
            ],
            const SizedBox(height: ThemeV2Spacing.lg),
            LibrarySectionLabel(
              label:
                  'PINNED / ${controller.pinnedContainers.length.toString().padLeft(2, '0')}',
              trailing: ThemeV2IconButton(
                key: const ValueKey('library-configure-pinned'),
                semanticLabel: '配置常驻容器',
                icon: Icons.tune,
                iconSize: 17,
                color: context.themeV2.muted,
                onPressed: onConfigurePinned,
              ),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
            if (controller.pinnedContainers.isEmpty)
              _EmptyPinned(onConfigure: onConfigurePinned)
            else
              LibraryPinnedMosaic(
                containers: controller.pinnedContainers,
                onTap: onOpenContainer,
                onLongPress: onConfigurePinned,
              ),
            const SizedBox(height: ThemeV2Spacing.lg),
            CreateSkillAction(onPressed: onCreateSkill),
            const SizedBox(height: ThemeV2Spacing.xl),
            LibrarySectionLabel(
              label: '最近生成',
              trailing: Text(
                '${snapshot?.recentItems.length ?? 0}',
                style: ThemeV2Typography.mono(
                  fontSize: 9,
                  color: context.themeV2.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
            _RecentItems(
              items: snapshot?.recentItems ?? const [],
              onOpen: onOpenRecent,
            ),
          ],
        );
      },
    );
  }
}

class _LibraryStatsEntry extends StatelessWidget {
  const _LibraryStatsEntry({
    required this.assetCount,
    required this.containerCount,
    required this.onTap,
  });

  final int assetCount;
  final int containerCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '打开全部容器',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: const ValueKey('library-stats-entry'),
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            side: BorderSide(color: tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
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
                    _Stat(value: '$assetCount', label: '资产'),
                    const SizedBox(width: ThemeV2Spacing.lg),
                    _Stat(value: '$containerCount', label: '容器'),
                    const Spacer(),
                    Container(width: 1, height: 30, color: tokens.border),
                    const SizedBox(width: ThemeV2Spacing.lg),
                    Icon(
                      Icons.grid_view_outlined,
                      color: tokens.accent,
                      size: 18,
                    ),
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Text(
                      '全部容器',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: ThemeV2Spacing.xs),
                    Icon(Icons.chevron_right, color: tokens.muted, size: 18),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: tokens.muted),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.accentSoft,
      borderRadius: BorderRadius.circular(ThemeV2Radii.md),
      child: Padding(
        padding: const EdgeInsets.only(left: ThemeV2Spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _EmptyPinned extends StatelessWidget {
  const _EmptyPinned({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
      child: InkWell(
        onTap: onConfigure,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        child: const SizedBox(
          height: 96,
          child: Center(child: Text('还没有常驻容器，点击配置')),
        ),
      ),
    );
  }
}

class _RecentItems extends StatelessWidget {
  const _RecentItems({required this.items, this.onOpen});

  final List<LibraryRecentItem> items;
  final ValueChanged<LibraryRecentItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    if (items.isEmpty) {
      return Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          '还没有最近生成的资产',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
      );
    }
    return SizedBox(
      key: const ValueKey('library-recent-items'),
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.take(12).length,
        separatorBuilder: (_, _) => const SizedBox(width: ThemeV2Spacing.sm),
        itemBuilder: (context, index) {
          final item = items[index];
          return Semantics(
            label: '打开最近资产 ${item.title}',
            button: true,
            onTap: onOpen == null ? null : () => onOpen!(item),
            child: ExcludeSemantics(
              child: Material(
                key: ValueKey('library-recent-${item.containerId}-${item.id}'),
                color: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                  side: BorderSide(color: tokens.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpen == null ? null : () => onOpen!(item),
                  child: SizedBox(
                    width: 58,
                    height: 62,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _recentIcon(item.containerId),
                          color: tokens.accent,
                          size: 18,
                        ),
                        const SizedBox(height: ThemeV2Spacing.xs),
                        Text(
                          _time(item.effectiveAt),
                          style: ThemeV2Typography.mono(
                            fontSize: 7.5,
                            color: tokens.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _recentIcon(String id) => switch (id) {
    'event' => Icons.calendar_today_outlined,
    'contact' => Icons.person_outline,
    'report' => Icons.insights_outlined,
    'todo' => Icons.checklist_outlined,
    'notes' => Icons.notes_outlined,
    _ => Icons.auto_awesome_mosaic_outlined,
  };

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
