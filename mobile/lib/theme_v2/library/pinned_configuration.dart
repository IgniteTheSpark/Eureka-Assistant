import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'create_skill_action.dart';
import 'library_components.dart';
import 'library_controller.dart';
import 'library_states.dart';

class PinnedConfiguration extends StatelessWidget {
  const PinnedConfiguration({
    super.key,
    required this.controller,
    required this.onDone,
    this.onCreateSkill,
  });

  final LibraryController controller;
  final VoidCallback onDone;
  final VoidCallback? onCreateSkill;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final saving = controller.isSavingPins;
        return ListView(
          key: const PageStorageKey('theme-v2-library-pinned-configuration'),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 112),
          children: [
            _ConfigurationHeader(
              saving: saving,
              onDone: saving ? null : onDone,
            ),
            const SizedBox(height: 16),
            _ConfigurationSummary(
              count: controller.pinnedContainers.length,
              saving: saving,
            ),
            const SizedBox(height: 22),
            LibrarySectionLabel(
              label:
                  'CONFIGURE / '
                  '${controller.pinnedContainers.length.toString().padLeft(2, '0')}'
                  ' · 长按拖动',
            ),
            const SizedBox(height: 10),
            if (controller.pinnedContainers.isEmpty)
              const LibraryStateView.empty(
                title: '还没有常驻容器',
                message: '从下方选择要固定在资产库首页的容器',
              )
            else
              LibraryPinnedMosaic(
                containers: controller.pinnedContainers,
                configure: true,
                onRemove: saving
                    ? null
                    : (container) => controller.removePinned(container.id),
                onMoveBackward: saving
                    ? null
                    : (container) => _moveBackward(controller, container.id),
                onDrop: saving ? null : controller.movePinned,
              ),
            if (saving) ...[
              const SizedBox(height: ThemeV2Spacing.sm),
              const _PersistenceFeedback.saving(),
            ] else if (controller.pinSaveError case final error?) ...[
              const SizedBox(height: ThemeV2Spacing.sm),
              _PersistenceFeedback.error(error),
            ],
            const SizedBox(height: 22),
            CreateSkillAction.configuration(
              onPressed:
                  onCreateSkill ?? () => showThemeV2CreateSkillLaunch(context),
            ),
            const SizedBox(height: 24),
            LibrarySectionLabel(
              label: '可用容器',
              trailing: Text(
                controller.canPinMore ? '最多 6 个' : '已达上限',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: context.themeV2.muted),
              ),
            ),
            const SizedBox(height: 10),
            if (controller.availableToPin.isEmpty)
              _AllPinned(canPinMore: controller.canPinMore)
            else
              for (final container in controller.availableToPin) ...[
                LibraryAvailableContainerTile(
                  container: container,
                  enabled: controller.canPinMore && !saving,
                  disabledLabel: saving
                      ? '加入 ${container.label}，正在保存当前配置'
                      : '加入 ${container.label}，已达到六个常驻容器上限',
                  onTap: () {
                    if (!controller.isSavingPins) {
                      controller.addPinned(container.id);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }

  void _moveBackward(LibraryController controller, String id) {
    if (controller.isSavingPins) return;
    final index = controller.pinnedContainers.indexWhere(
      (container) => container.id == id,
    );
    if (index >= 0 && index < controller.pinnedContainers.length - 1) {
      controller.movePinned(index, index + 1);
    }
  }
}

class _ConfigurationHeader extends StatelessWidget {
  const _ConfigurationHeader({required this.saving, required this.onDone});

  final bool saving;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ThemeV2Sizes.minTouchTarget,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '资产库',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: context.themeV2.foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
              ),
            ),
          ),
          SizedBox(
            key: const ValueKey('library-pinned-done'),
            width: 72,
            height: ThemeV2Sizes.minTouchTarget,
            child: TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  saving ? '保存中' : '完成配置',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigurationSummary extends StatelessWidget {
  const _ConfigurationSummary({required this.count, required this.saving});

  final int count;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('library-pinned-summary'),
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
      ),
      child: Row(
        children: [
          Text(
            '$count',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            '个常驻容器',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
          const Spacer(),
          Icon(
            saving ? Icons.sync : Icons.check_circle_outline,
            size: 17,
            color: saving ? tokens.muted : tokens.accent,
          ),
          const SizedBox(width: 6),
          Text(
            saving ? '正在确认' : '自动保存',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}

enum _PersistenceKind { saving, error }

class _PersistenceFeedback extends StatelessWidget {
  const _PersistenceFeedback.saving()
    : kind = _PersistenceKind.saving,
      message = '正在保存配置…';

  const _PersistenceFeedback.error(this.message)
    : kind = _PersistenceKind.error;

  final _PersistenceKind kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final error = kind == _PersistenceKind.error;
    final tokens = context.themeV2;
    return Semantics(
      label: message,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('library-pinned-${kind.name}'),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: error
                ? tokens.critical.withValues(alpha: .08)
                : tokens.accentSoft,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          ),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: error ? tokens.critical : tokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AllPinned extends StatelessWidget {
  const _AllPinned({required this.canPinMore});

  final bool canPinMore;

  @override
  Widget build(BuildContext context) {
    return LibraryStateView.empty(
      title: canPinMore ? '所有可用容器都已加入' : '已固定 6 个容器',
      message: canPinMore ? null : '移除一个容器后可继续添加',
    );
  }
}
