import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

class CreateSkillAction extends StatelessWidget {
  const CreateSkillAction({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '创建新技能，AI 自动生成容器结构',
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: Material(
            key: const ValueKey('library-create-skill'),
            color: tokens.accentSoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
              side: BorderSide(color: tokens.accent),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(ThemeV2Spacing.md),
                child: Row(
                  children: [
                    Container(
                      width: ThemeV2Sizes.minTouchTarget,
                      height: ThemeV2Sizes.minTouchTarget,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: tokens.background,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: ThemeV2Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '创建新技能',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: ThemeV2Spacing.xs),
                          Text(
                            '描述一个习惯，AI 自动生成容器结构',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_outward, color: tokens.accent, size: 20),
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

Future<void> showThemeV2CreateSkillLaunch(
  BuildContext context, {
  required VoidCallback onContinue,
}) {
  final tokens = context.themeV2;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: tokens.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ThemeV2Radii.lg),
      ),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ThemeV2Spacing.xl,
          ThemeV2Spacing.md,
          ThemeV2Spacing.xl,
          ThemeV2Spacing.xl + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome, color: tokens.accent, size: 28),
            const SizedBox(height: ThemeV2Spacing.md),
            Text(
              '让 AI 设计一个新技能',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
            Text(
              '你只要描述想记录的内容，接下来会复用现有创建能力生成并确认容器结构。',
              style: Theme.of(
                sheetContext,
              ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
            ),
            const SizedBox(height: ThemeV2Spacing.xl),
            SizedBox(
              width: double.infinity,
              height: ThemeV2Sizes.minTouchTarget,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onContinue();
                  });
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('开始描述'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
