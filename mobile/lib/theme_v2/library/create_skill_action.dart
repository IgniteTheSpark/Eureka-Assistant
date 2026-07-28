import 'package:flutter/material.dart';

import '../../data_revision.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'create_skill/skill_wizard_controller.dart';
import 'create_skill/theme_v2_skill_wizard.dart';

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
  SkillWizardRepository? repository,
  VoidCallback? onCreated,
}) async {
  final usesProductionRepository = repository == null;
  final controller = SkillWizardController(
    repository: repository ?? ApiSkillWizardRepository(),
    disposeRepository: usesProductionRepository,
    onCreated: () {
      bumpData();
      onCreated?.call();
    },
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) => ThemeV2SkillWizardSheet(
      controller: controller,
      onClose: () => Navigator.of(sheetContext).pop(),
      onComplete: () => Navigator.of(sheetContext).pop(),
    ),
  );
  controller.dispose();
}
