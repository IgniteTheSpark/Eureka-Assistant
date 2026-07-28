import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'library_components.dart';
import 'library_controller.dart';

class PinnedConfiguration extends StatelessWidget {
  const PinnedConfiguration({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final LibraryController controller;
  final VoidCallback onDone;

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
            kicker: 'LIBRARY / PINNED',
            title: '资产库',
            subtitle: '长按拖动常驻容器，或使用箭头调整顺序',
            onBack: onDone,
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          LibrarySectionLabel(
            label:
                'CONFIGURE SIGNALS / ${controller.pinnedContainers.length.toString().padLeft(2, '0')}',
            trailing: Semantics(
              label: '完成配置',
              button: true,
              onTap: onDone,
              child: ExcludeSemantics(
                child: ThemeV2HitTarget(
                  child: TextButton.icon(
                    onPressed: onDone,
                    icon: const Icon(Icons.check, size: 17),
                    label: const Text('完成配置'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          if (controller.pinnedContainers.isEmpty)
            _NoPinned(controller: controller)
          else
            LibraryPinnedMosaic(
              containers: controller.pinnedContainers,
              configure: true,
              onRemove: (container) => controller.removePinned(container.id),
              onMoveBackward: (container) {
                final index = controller.pinnedContainers.indexWhere(
                  (item) => item.id == container.id,
                );
                if (index >= 0 &&
                    index < controller.pinnedContainers.length - 1) {
                  controller.movePinned(index, index + 1);
                }
              },
              onDrop: controller.movePinned,
            ),
          if (controller.pinSaveError case final error?) ...[
            const SizedBox(height: ThemeV2Spacing.sm),
            Text(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.themeV2.critical),
            ),
          ],
          const SizedBox(height: ThemeV2Spacing.xl),
          LibrarySectionLabel(
            label: '可用容器',
            trailing: Text(
              controller.canPinMore ? '点击加入' : '已达上限',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: context.themeV2.muted),
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          if (!controller.canPinMore)
            Padding(
              padding: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
              child: Text(
                '最多常驻 6 个容器，请先移除一个。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
              ),
            ),
          if (controller.availableToPin.isEmpty)
            _AllPinned(canPinMore: controller.canPinMore)
          else
            Wrap(
              spacing: ThemeV2Spacing.sm,
              runSpacing: ThemeV2Spacing.sm,
              children: [
                for (final container in controller.availableToPin)
                  _AvailableContainer(
                    container: container,
                    enabled: controller.canPinMore,
                    onAdd: () => controller.addPinned(container.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NoPinned extends StatelessWidget {
  const _NoPinned({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.themeV2.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        border: Border.all(color: context.themeV2.border),
      ),
      child: const Text('从下方选择常驻容器'),
    );
  }
}

class _AllPinned extends StatelessWidget {
  const _AllPinned({required this.canPinMore});

  final bool canPinMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      alignment: Alignment.center,
      child: Text(
        canPinMore ? '所有可用容器都已加入' : '移除一个容器后可继续添加',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
      ),
    );
  }
}

class _AvailableContainer extends StatelessWidget {
  const _AvailableContainer({
    required this.container,
    required this.enabled,
    required this.onAdd,
  });

  final LibraryContainer container;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '加入 ${container.label}',
      button: true,
      enabled: enabled,
      onTap: enabled ? onAdd : null,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: OutlinedButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: Icon(libraryContainerIcon(container), size: 17),
            label: Text(container.label),
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.foreground,
              side: BorderSide(color: tokens.border),
              minimumSize: const Size(
                ThemeV2Sizes.minTouchTarget,
                ThemeV2Sizes.minTouchTarget,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
