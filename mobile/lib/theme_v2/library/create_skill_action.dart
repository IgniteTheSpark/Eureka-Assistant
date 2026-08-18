import 'package:flutter/material.dart';

import '../../data_revision.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'create_skill/skill_configuration_repository.dart';
import 'create_skill/skill_management_controller.dart';
import 'create_skill/skill_management_sheet.dart';
import 'create_skill/skill_wizard_controller.dart';
import 'create_skill/theme_v2_skill_wizard.dart';

enum _CreateSkillVariant { primary, compact, configuration }

class CreateSkillAction extends StatelessWidget {
  const CreateSkillAction({super.key, required this.onPressed})
    : _variant = _CreateSkillVariant.primary;

  const CreateSkillAction.primary({super.key, required this.onPressed})
    : _variant = _CreateSkillVariant.primary;

  const CreateSkillAction.compact({super.key, required this.onPressed})
    : _variant = _CreateSkillVariant.compact;

  const CreateSkillAction.configuration({super.key, required this.onPressed})
    : _variant = _CreateSkillVariant.configuration;

  final VoidCallback onPressed;
  final _CreateSkillVariant _variant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final primary = _variant == _CreateSkillVariant.primary;
    final title = _variant == _CreateSkillVariant.configuration
        ? '新建技能容器'
        : '创建新技能';
    final semanticLabel = primary ? '$title，描述你想长期记录的内容' : title;
    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          key: ValueKey('library-create-skill-${_variant.name}'),
          color: primary ? tokens.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              primary ? ThemeV2Radii.lg : ThemeV2Radii.md,
            ),
            side: BorderSide(color: primary ? tokens.accent : tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: _variant == _CreateSkillVariant.primary
                ? const ValueKey('library-create-skill')
                : null,
            onTap: onPressed,
            child: SizedBox(
              height: primary ? 76 : 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: primary ? 44 : 34,
                      height: primary ? 44 : 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primary ? tokens.accent : tokens.accentSoft,
                        borderRadius: BorderRadius.circular(
                          primary ? ThemeV2Radii.lg : ThemeV2Radii.md,
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: primary ? tokens.background : tokens.accent,
                        size: primary ? 20 : 17,
                      ),
                    ),
                    const SizedBox(width: ThemeV2Spacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (primary) ...[
                            const SizedBox(height: 2),
                            Text(
                              '描述你想长期记录的内容',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      primary ? Icons.arrow_outward : Icons.add,
                      color: tokens.accent,
                      size: 19,
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
    enableDrag: false,
    isDismissible: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .32),
    builder: (sheetContext) => ThemeV2SkillWizardSheet(
      controller: controller,
      onClose: () => Navigator.of(sheetContext).pop(),
      onComplete: () => Navigator.of(sheetContext).pop(),
    ),
  );
  controller.dispose();
}

Future<void> showThemeV2SkillConfigurationLaunch(
  BuildContext context, {
  required String userSkillId,
  SkillConfigurationRepository? repository,
  VoidCallback? onSaved,
}) async {
  final usesProductionRepository = repository == null;
  final controller = SkillCardConfigurationController(
    repository: repository ?? ApiSkillConfigurationRepository(),
    userSkillId: userSkillId,
    disposeRepository: usesProductionRepository,
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    isDismissible: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .32),
    builder: (sheetContext) => ThemeV2SkillWizardSheet.configuration(
      controller: controller,
      onClose: () => Navigator.of(sheetContext).pop(),
      onComplete: () {
        bumpData();
        onSaved?.call();
        Navigator.of(sheetContext).pop();
      },
    ),
  );
  controller.dispose();
}

Future<void> showThemeV2SkillManagementLaunch(
  BuildContext context, {
  required String userSkillId,
  SkillManagementRepository? repository,
  VoidCallback? onSaved,
  VoidCallback? onDeleted,
}) async {
  final usesProductionRepository = repository == null;
  final controller = SkillManagementController(
    repository: repository ?? ApiSkillManagementRepository(),
    userSkillId: userSkillId,
    disposeRepository: usesProductionRepository,
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    isDismissible: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .32),
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height,
      child: ThemeV2SkillManagementSheet(
        controller: controller,
        onClose: () => Navigator.of(sheetContext).pop(),
        onSaved: () {
          bumpData();
          onSaved?.call();
        },
        onDeleted: () {
          bumpData();
          Navigator.of(sheetContext).pop();
          onDeleted?.call();
        },
      ),
    ),
  );
  controller.dispose();
}
