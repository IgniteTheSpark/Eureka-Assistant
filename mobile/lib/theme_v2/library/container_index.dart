import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'create_skill_action.dart';
import 'library_components.dart';
import 'library_controller.dart';

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
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.lg,
          ThemeV2Spacing.xl,
        ),
        children: [
          LibraryScreenHeader(
            kicker: 'LIBRARY / CONTAINERS',
            title: '资产容器',
            subtitle: '你正在使用的容器',
            onBack: onBack,
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          LibrarySearchField(
            value: controller.query,
            onChanged: controller.setQuery,
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          _ContainerGroups(
            controller: controller,
            onOpenContainer: onOpenContainer,
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          Semantics(
            label: '打开全部容器',
            button: true,
            onTap: onOpenAllContainers,
            child: ExcludeSemantics(
              child: ThemeV2HitTarget(
                child: OutlinedButton.icon(
                  onPressed: onOpenAllContainers,
                  icon: const Icon(Icons.grid_view_outlined),
                  label: const Text('查看全部容器'),
                ),
              ),
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.md),
          CreateSkillAction(onPressed: onCreateSkill),
        ],
      ),
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
        final snapshot = controller.snapshot;
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            ThemeV2Spacing.lg,
            ThemeV2Spacing.sm,
            ThemeV2Spacing.lg,
            ThemeV2Spacing.xl,
          ),
          children: [
            LibraryScreenHeader(
              kicker: 'LIBRARY / DIRECTORY',
              title: '全部容器',
              subtitle: '查找并管理所有记录入口',
              onBack: onBack,
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            _AllContainerStats(
              containers: snapshot?.containerCount ?? 0,
              assets: snapshot?.assetTotal ?? 0,
              custom: snapshot?.customContainerCount ?? 0,
            ),
            const SizedBox(height: ThemeV2Spacing.md),
            LibrarySearchField(
              value: controller.query,
              onChanged: controller.setQuery,
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            _ContainerGroups(
              controller: controller,
              onOpenContainer: onOpenContainer,
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            CreateSkillAction(onPressed: onCreateSkill),
          ],
        );
      },
    );
  }
}

class _AllContainerStats extends StatelessWidget {
  const _AllContainerStats({
    required this.containers,
    required this.assets,
    required this.custom,
  });

  final int containers;
  final int assets;
  final int custom;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      key: const ValueKey('library-all-stats'),
      children: [
        Expanded(
          child: _DirectoryStat(
            value: '$containers',
            label: '容器',
            tokens: tokens,
          ),
        ),
        const SizedBox(width: ThemeV2Spacing.sm),
        Expanded(
          child: _DirectoryStat(value: '$assets', label: '资产', tokens: tokens),
        ),
        const SizedBox(width: ThemeV2Spacing.sm),
        Expanded(
          child: _DirectoryStat(
            value: '$custom',
            label: '自定义',
            tokens: tokens,
            emphasized: true,
          ),
        ),
      ],
    );
  }
}

class _DirectoryStat extends StatelessWidget {
  const _DirectoryStat({
    required this.value,
    required this.label,
    required this.tokens,
    this.emphasized = false,
  });

  final String value;
  final String label;
  final ThemeV2Tokens tokens;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.all(ThemeV2Spacing.md),
      decoration: BoxDecoration(
        color: emphasized ? tokens.accentSoft : tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        border: Border.all(color: emphasized ? tokens.accent : tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: ThemeV2Typography.mono(
              fontSize: 8,
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContainerGroups extends StatelessWidget {
  const _ContainerGroups({
    required this.controller,
    required this.onOpenContainer,
  });

  final LibraryController controller;
  final LibraryContainerCallback onOpenContainer;

  @override
  Widget build(BuildContext context) {
    final system = controller.systemContainers;
    final custom = controller.customContainers;
    if (system.isEmpty && custom.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text(
          controller.query.isEmpty ? '还没有容器' : '没有匹配的容器',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.themeV2.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (system.isNotEmpty) ...[
          const LibrarySectionLabel(label: '系统容器'),
          const SizedBox(height: ThemeV2Spacing.sm),
          for (final item in system) ...[
            LibraryContainerRow(
              container: item,
              onTap: () => onOpenContainer(item),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
          ],
        ],
        if (custom.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.md),
          const LibrarySectionLabel(label: '自定义技能'),
          const SizedBox(height: ThemeV2Spacing.sm),
          for (final item in custom) ...[
            LibraryContainerRow(
              container: item,
              onTap: () => onOpenContainer(item),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
          ],
        ],
      ],
    );
  }
}
