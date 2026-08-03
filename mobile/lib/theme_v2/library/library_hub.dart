import 'package:flutter/material.dart';

import '../asset/asset_card.dart';
import '../asset/asset_card_display.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../shell/theme_v2_page_title.dart';
import 'create_skill_action.dart';
import 'library_components.dart';
import 'library_controller.dart';
import 'library_models.dart';
import 'library_states.dart';

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
  final ValueChanged<LibraryRecentAsset>? onOpenRecent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final overview = controller.overview;
        return ListView(
          key: const PageStorageKey('theme-v2-library-hub'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          children: [
            const ThemeV2PageTitle(
              key: ValueKey('theme-v2-page-title-library'),
              title: '资产库',
            ),
            const SizedBox(height: 18),
            LibraryStatsBar(
              assetCount: overview?.totalAssetCount ?? 0,
              containerCount: overview?.containerCount ?? 0,
              onOpenContainerIndex: onOpenContainerIndex,
              onOpenAllContainers: onOpenAllContainers,
            ),
            if (controller.statusMessage case final message?) ...[
              const SizedBox(height: ThemeV2Spacing.sm),
              LibraryPartialBanner(message: message, onRetry: controller.retry),
            ],
            const SizedBox(height: ThemeV2Spacing.xl),
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
            const SizedBox(height: 10),
            if (controller.pinnedContainers.isEmpty)
              _EmptyPinned(onConfigure: onConfigurePinned)
            else
              LibraryPinnedMosaic(
                containers: controller.pinnedContainers,
                onTap: onOpenContainer,
                onLongPress: onConfigurePinned,
              ),
            const SizedBox(height: ThemeV2Spacing.lg),
            CreateSkillAction.primary(onPressed: onCreateSkill),
            const SizedBox(height: ThemeV2Spacing.xl),
            const LibrarySectionLabel(label: '最近生成'),
            const SizedBox(height: ThemeV2Spacing.sm),
            _RecentAssets(
              items: overview?.recentAssets ?? const [],
              onOpen: onOpenRecent,
            ),
          ],
        );
      },
    );
  }
}

class _EmptyPinned extends StatelessWidget {
  const _EmptyPinned({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '还没有常驻容器，点击配置',
      button: true,
      onTap: onConfigure,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            side: BorderSide(color: tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onConfigure,
            child: const SizedBox(
              height: 96,
              child: Center(child: Text('还没有常驻容器，点击配置')),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentAssets extends StatelessWidget {
  const _RecentAssets({required this.items, this.onOpen});

  final List<LibraryRecentAsset> items;
  final ValueChanged<LibraryRecentAsset>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const LibraryStateView.empty(
        title: '还没有最近生成的资产',
        message: '新资产会出现在这里',
      );
    }
    final visibleItems = items.take(50).toList(growable: false);
    return SizedBox(
      key: const ValueKey('library-recent-items'),
      height: 54,
      child: ListView.separated(
        key: const PageStorageKey('theme-v2-library-recent-assets'),
        scrollDirection: Axis.horizontal,
        itemCount: visibleItems.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final asset = visibleItems[index];
          final time = MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(asset.createdAt),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
          return SizedBox(
            key: ValueKey('library-recent-${asset.id}'),
            width: 55,
            child: ThemeV2AssetCard(
              variant: AssetCardVariant.iconTime,
              data: AssetCardViewData(
                mark: asset.mark,
                skillLabel: asset.skillLabel,
                primaryValue: asset.primaryValue,
                timeLabel: time,
              ),
              onOpen: onOpen == null ? null : () => onOpen!(asset),
            ),
          );
        },
      ),
    );
  }
}
