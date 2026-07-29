import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'create_skill_action.dart';
import 'library_components.dart';
import 'library_controller.dart';
import 'library_models.dart';
import 'library_states.dart';

class ContainerIndex extends StatelessWidget {
  const ContainerIndex({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onOpenContainer,
    required this.onOpenAllContainers,
    required this.onCreateSkill,
  });

  final LibraryController controller;
  final VoidCallback onBack;
  final LibraryContainerCallback onOpenContainer;
  final VoidCallback onOpenAllContainers;
  final VoidCallback onCreateSkill;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final system = controller.indexSystemContainers;
        final custom = controller.indexCustomContainers;
        return ListView(
          key: const PageStorageKey('theme-v2-library-container-index'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
          children: [
            _DirectoryTitle(title: '资产容器', onBack: onBack),
            const SizedBox(height: 16),
            LibrarySearchField(
              fieldKey: const ValueKey('library-index-search'),
              value: controller.indexQuery,
              onChanged: controller.setIndexQuery,
            ),
            const SizedBox(height: 20),
            if (system.isEmpty && custom.isEmpty)
              _DirectoryEmptyState(
                hasQuery: controller.indexQuery.trim().isNotEmpty,
                onClear: controller.clearIndexQuery,
              )
            else
              _IndexGroups(
                system: system,
                custom: custom,
                onOpenContainer: onOpenContainer,
              ),
            const SizedBox(height: 24),
            CreateSkillAction.compact(onPressed: onCreateSkill),
          ],
        );
      },
    );
  }
}

class AllContainers extends StatelessWidget {
  const AllContainers({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onOpenContainer,
    required this.onCreateSkill,
  });

  final LibraryController controller;
  final VoidCallback onBack;
  final LibraryContainerCallback onOpenContainer;
  final VoidCallback onCreateSkill;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final overview = controller.overview;
        return ListView(
          key: const PageStorageKey('theme-v2-library-all-containers'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _DirectoryTitle(title: '全部容器', onBack: onBack),
            const SizedBox(height: 16),
            LibraryMetricStrip(
              containerCount: overview?.containerCount ?? 0,
              assetCount: overview?.totalAssetCount ?? 0,
              customCount: overview?.customContainerCount ?? 0,
            ),
            const SizedBox(height: 18),
            LibrarySearchField(
              fieldKey: const ValueKey('library-all-search'),
              height: 42,
              value: controller.allQuery,
              onChanged: controller.setAllQuery,
            ),
            const SizedBox(height: 20),
            if (controller.allSystemContainers.isEmpty &&
                controller.allCustomContainers.isEmpty)
              _DirectoryEmptyState(
                hasQuery: controller.allQuery.trim().isNotEmpty,
                onClear: controller.clearAllQuery,
              )
            else
              _AllGroups(
                system: controller.allSystemContainers,
                custom: controller.allCustomContainers,
                onOpenContainer: onOpenContainer,
              ),
            const SizedBox(height: 24),
            CreateSkillAction.compact(onPressed: onCreateSkill),
          ],
        );
      },
    );
  }
}

class _DirectoryTitle extends StatelessWidget {
  const _DirectoryTitle({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ThemeV2Sizes.minTouchTarget,
      child: Row(
        children: [
          ThemeV2IconButton(
            semanticLabel: '返回',
            icon: Icons.arrow_back,
            color: context.themeV2.foreground,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: context.themeV2.foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexGroups extends StatelessWidget {
  const _IndexGroups({
    required this.system,
    required this.custom,
    required this.onOpenContainer,
  });

  final List<LibraryContainerSummary> system;
  final List<LibraryContainerSummary> custom;
  final LibraryContainerCallback onOpenContainer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (system.isNotEmpty) ...[
          const LibrarySectionLabel(label: '系统容器'),
          const SizedBox(height: 8),
          for (final item in system) ...[
            LibrarySystemContainerCard(
              container: item,
              onTap: () => onOpenContainer(item),
            ),
            const SizedBox(height: 6),
          ],
        ],
        if (custom.isNotEmpty) ...[
          if (system.isNotEmpty) const SizedBox(height: 16),
          const LibrarySectionLabel(label: '自定义技能'),
          const SizedBox(height: 8),
          for (final item in custom)
            LibraryCustomContainerRow(
              container: item,
              onTap: () => onOpenContainer(item),
            ),
        ],
      ],
    );
  }
}

class _AllGroups extends StatelessWidget {
  const _AllGroups({
    required this.system,
    required this.custom,
    required this.onOpenContainer,
  });

  final List<LibraryContainerSummary> system;
  final List<LibraryContainerSummary> custom;
  final LibraryContainerCallback onOpenContainer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (system.isNotEmpty) ...[
          const LibrarySectionLabel(label: '系统容器'),
          const SizedBox(height: 8),
          for (final item in system)
            LibraryDirectoryRow(
              container: item,
              onTap: () => onOpenContainer(item),
            ),
        ],
        if (custom.isNotEmpty) ...[
          if (system.isNotEmpty) const SizedBox(height: 18),
          const LibrarySectionLabel(label: '自定义技能'),
          const SizedBox(height: 8),
          for (final item in custom)
            LibraryDirectoryRow(
              container: item,
              onTap: () => onOpenContainer(item),
            ),
        ],
      ],
    );
  }
}

class _DirectoryEmptyState extends StatelessWidget {
  const _DirectoryEmptyState({required this.hasQuery, required this.onClear});

  final bool hasQuery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => hasQuery
      ? LibraryStateView.emptySearch(onClear: onClear)
      : const LibraryStateView.empty(title: '还没有容器', message: '创建技能后，容器会出现在这里');
}
