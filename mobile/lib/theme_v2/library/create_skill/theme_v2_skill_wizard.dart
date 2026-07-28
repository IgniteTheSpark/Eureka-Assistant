import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'skill_wizard_controller.dart';

const themeV2SkillSuggestions = ['跑步训练记录', '读书笔记', '每天喝水量', '面试复盘'];

class ThemeV2SkillWizardSheet extends StatefulWidget {
  const ThemeV2SkillWizardSheet({
    super.key,
    required this.controller,
    this.onClose,
    this.onComplete,
  });

  final SkillWizardController controller;
  final VoidCallback? onClose;
  final VoidCallback? onComplete;

  @override
  State<ThemeV2SkillWizardSheet> createState() =>
      _ThemeV2SkillWizardSheetState();
}

class _ThemeV2SkillWizardSheetState extends State<ThemeV2SkillWizardSheet> {
  late final TextEditingController _description = TextEditingController(
    text: widget.controller.description,
  );

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _close() {
    final callback = widget.onClose;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirm() async {
    if (!await widget.controller.confirm() || !mounted) return;
    final callback = widget.onComplete;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final media = MediaQuery.of(context);
        final maxHeight = media.size.height * 0.85;
        return AnimatedPadding(
          duration: media.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Material(
            key: const ValueKey('skill-wizard-sheet'),
            color: context.themeV2.surface,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(ThemeV2Radii.lg),
              ),
            ),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: ThemeV2Spacing.sm),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.themeV2.border,
                        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                      ),
                    ),
                    _WizardHeader(stage: controller.stage, onClose: _close),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          ThemeV2Spacing.xl,
                          0,
                          ThemeV2Spacing.xl,
                          ThemeV2Spacing.xl,
                        ),
                        child: switch (controller.stage) {
                          SkillWizardStage.describe => _buildDescribe(
                            controller,
                          ),
                          SkillWizardStage.questions => _buildQuestions(
                            controller,
                          ),
                          SkillWizardStage.preview => _buildPreview(controller),
                          SkillWizardStage.complete => const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDescribe(SkillWizardController controller) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('skill-wizard-description'),
          controller: _description,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          onChanged: controller.setDescription,
          style: TextStyle(color: tokens.foreground, fontSize: 13, height: 1.4),
          decoration: _inputDecoration('用一句话描述你想记录的内容，例如「记录每次跑步的距离、配速和感受」'),
        ),
        const SizedBox(height: ThemeV2Spacing.md),
        Wrap(
          spacing: ThemeV2Spacing.sm,
          runSpacing: ThemeV2Spacing.sm,
          children: [
            for (final suggestion in themeV2SkillSuggestions)
              _SuggestionChip(
                label: suggestion,
                onPressed: () {
                  _description.text = suggestion;
                  _description.selection = TextSelection.collapsed(
                    offset: suggestion.length,
                  );
                  controller.setDescription(suggestion);
                },
              ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.lg),
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 15, color: tokens.accent),
            const SizedBox(width: ThemeV2Spacing.sm),
            Expanded(
              child: Text(
                'AI 会自动设计字段、图标和卡片结构',
                style: TextStyle(color: tokens.muted, fontSize: 11),
              ),
            ),
          ],
        ),
        _error(controller.errorMessage),
        const SizedBox(height: ThemeV2Spacing.xl),
        _FooterActions(
          secondaryLabel: '取消',
          onSecondary: controller.busy ? null : _close,
          primaryLabel: controller.busy ? '设计中…' : 'AI 生成',
          primarySemanticLabel: 'AI 生成技能',
          busy: controller.busy,
          onPrimary: controller.busy
              ? null
              : () => unawaited(controller.generate()),
        ),
      ],
    );
  }

  Widget _buildQuestions(SkillWizardController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final question in controller.questions) ...[
          Text(
            question.prompt,
            style: TextStyle(
              color: context.themeV2.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          if (question.options.isNotEmpty)
            Wrap(
              spacing: ThemeV2Spacing.sm,
              runSpacing: ThemeV2Spacing.sm,
              children: [
                for (final option in question.options)
                  _SuggestionChip(
                    label: option,
                    selected: controller.answerFor(question.key) == option,
                    onPressed: () => controller.answer(question.key, option),
                  ),
              ],
            )
          else
            TextFormField(
              key: ValueKey('skill-question-${question.key}'),
              initialValue: controller.answerFor(question.key),
              onChanged: (value) => controller.answer(question.key, value),
              style: TextStyle(color: context.themeV2.foreground),
              decoration: _inputDecoration(question.placeholder),
            ),
          const SizedBox(height: ThemeV2Spacing.lg),
        ],
        _error(controller.errorMessage),
        _FooterActions(
          secondaryLabel: '重新描述',
          onSecondary: controller.busy ? null : controller.backToDescribe,
          primaryLabel: controller.busy ? '设计中…' : '生成预览',
          primarySemanticLabel: '生成技能预览',
          busy: controller.busy,
          onPrimary: controller.busy
              ? null
              : () => unawaited(controller.generate()),
        ),
      ],
    );
  }

  Widget _buildPreview(SkillWizardController controller) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '预览',
          style: ThemeV2Typography.mono(
            color: tokens.muted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        _GeneratedSkillCard(controller: controller),
        const SizedBox(height: ThemeV2Spacing.lg),
        Row(
          children: [
            SizedBox(
              width: 68,
              child: TextFormField(
                key: const ValueKey('skill-icon'),
                initialValue: controller.icon,
                maxLength: 2,
                textAlign: TextAlign.center,
                onChanged: controller.setIcon,
                decoration: _inputDecoration('✨').copyWith(counterText: ''),
              ),
            ),
            const SizedBox(width: ThemeV2Spacing.sm),
            Expanded(
              child: TextFormField(
                key: const ValueKey('skill-name'),
                initialValue: controller.displayName,
                onChanged: controller.setDisplayName,
                style: TextStyle(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
                decoration: _inputDecoration('技能名称'),
              ),
            ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.lg),
        Text(
          '字段',
          style: ThemeV2Typography.mono(
            color: tokens.muted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        for (final field in controller.fields)
          _PreviewFieldRow(
            field: field,
            slot: controller.slotOf(field.key),
            onSlot: (slot) => controller.assignSlot(field.key, slot),
          ),
        _error(controller.errorMessage),
        const SizedBox(height: ThemeV2Spacing.lg),
        _FooterActions(
          secondaryLabel: '重新描述',
          onSecondary: controller.busy ? null : controller.backToDescribe,
          primaryLabel: controller.busy ? '创建中…' : '创建技能',
          primarySemanticLabel: '创建技能',
          busy: controller.busy,
          onPrimary: controller.busy ? null : () => unawaited(_confirm()),
        ),
      ],
    );
  }

  Widget _error(String? message) {
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: ThemeV2Spacing.md),
      child: Text(
        message,
        style: TextStyle(
          color: context.themeV2.critical,
          fontSize: 11,
          height: 1.35,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    final tokens = context.themeV2;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: tokens.muted, fontSize: 12),
      filled: true,
      fillColor: tokens.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ThemeV2Spacing.md,
        vertical: ThemeV2Spacing.md,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        borderSide: BorderSide(color: tokens.accent, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
      ),
    );
  }
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({required this.stage, required this.onClose});

  final SkillWizardStage stage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final title = switch (stage) {
      SkillWizardStage.describe => '想记录点什么？',
      SkillWizardStage.questions => '再补充几点',
      SkillWizardStage.preview => '确认技能',
      SkillWizardStage.complete => '创建完成',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.sm,
        ThemeV2Spacing.lg,
      ),
      child: Row(
        children: [
          Container(
            width: ThemeV2Sizes.minTouchTarget,
            height: ThemeV2Sizes.minTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              border: Border.all(color: tokens.accent),
            ),
            child: Icon(Icons.auto_awesome, size: 19, color: tokens.accent),
          ),
          const SizedBox(width: ThemeV2Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '新技能 · AI 设计',
                  style: ThemeV2Typography.mono(
                    color: tokens.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ThemeV2IconButton(
            semanticLabel: '关闭新技能',
            icon: Icons.close,
            color: tokens.muted,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ThemeV2Sizes.minTouchTarget,
          ),
          child: ActionChip(
            label: Text(label),
            onPressed: onPressed,
            backgroundColor: selected ? tokens.accentSoft : tokens.background,
            side: BorderSide(color: selected ? tokens.accent : tokens.border),
            labelStyle: TextStyle(
              color: selected ? tokens.accent : tokens.muted,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratedSkillCard extends StatelessWidget {
  const _GeneratedSkillCard({required this.controller});

  final SkillWizardController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final primary = controller.fields
        .where(
          (field) => controller.slotOf(field.key) == SkillFieldSlot.primary,
        )
        .map((field) => field.label)
        .firstOrNull;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeV2Spacing.md),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: ThemeV2Sizes.minTouchTarget,
            height: ThemeV2Sizes.minTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            ),
            child: Text(controller.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: ThemeV2Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.displayName,
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: ThemeV2Spacing.xs),
                Text(
                  primary ?? 'AI 生成字段结构',
                  style: TextStyle(color: tokens.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_outward, color: tokens.accent, size: 18),
        ],
      ),
    );
  }
}

class _PreviewFieldRow extends StatelessWidget {
  const _PreviewFieldRow({
    required this.field,
    required this.slot,
    required this.onSlot,
  });

  final SkillPreviewField field;
  final SkillFieldSlot slot;
  final ValueChanged<SkillFieldSlot> onSlot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: TextStyle(
                        color: tokens.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      field.key,
                      style: ThemeV2Typography.mono(
                        color: tokens.muted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _slotLabel(slot),
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          Wrap(
            spacing: ThemeV2Spacing.xs,
            runSpacing: ThemeV2Spacing.xs,
            children: [
              for (final option in SkillFieldSlot.values)
                _SlotChip(
                  label: _slotLabel(option),
                  selected: slot == option,
                  onPressed: () => onSlot(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _slotLabel(SkillFieldSlot slot) => switch (slot) {
    SkillFieldSlot.primary => '主',
    SkillFieldSlot.secondary => '副',
    SkillFieldSlot.info => '信息',
    SkillFieldSlot.hidden => '隐藏',
  };
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      selected: selected,
      label: '字段位置 $label',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: ThemeV2Sizes.minTouchTarget,
              minHeight: ThemeV2Sizes.minTouchTarget,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.sm),
            decoration: BoxDecoration(
              color: selected ? tokens.accentSoft : tokens.background,
              borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
              border: Border.all(
                color: selected ? tokens.accent : tokens.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? tokens.accent : tokens.muted,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterActions extends StatelessWidget {
  const _FooterActions({
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryLabel,
    required this.primarySemanticLabel,
    required this.busy,
    required this.onPrimary,
  });

  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final String primaryLabel;
  final String primarySemanticLabel;
  final bool busy;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: ThemeV2Sizes.minTouchTarget,
          child: TextButton(
            onPressed: onSecondary,
            child: Text(secondaryLabel),
          ),
        ),
        const SizedBox(width: ThemeV2Spacing.sm),
        Semantics(
          label: primarySemanticLabel,
          button: true,
          enabled: onPrimary != null,
          onTap: onPrimary,
          child: ExcludeSemantics(
            child: SizedBox(
              height: ThemeV2Sizes.minTouchTarget,
              child: FilledButton.icon(
                onPressed: onPrimary,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 17),
                label: Text(primaryLabel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
