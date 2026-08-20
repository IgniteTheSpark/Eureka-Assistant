import 'dart:async';

import 'package:flutter/material.dart';

import '../../../render/render_spec.dart';
import '../../../voice_input/voice_input_controller.dart';
import '../../../voice_input/voice_input_field.dart';
import '../../../voice_input/voice_input_scope.dart';
import '../../asset/asset_card.dart';
import '../../asset/asset_card_display.dart';
import '../../asset/card_field_selection.dart';
import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'skill_configuration_repository.dart';
import 'skill_wizard_controller.dart';

const themeV2SkillSuggestions = ['跑步训练记录', '读书笔记', '每天喝水量', '面试复盘'];

class ThemeV2SkillWizardSheet extends StatefulWidget {
  const ThemeV2SkillWizardSheet({
    super.key,
    required SkillWizardController this.controller,
    this.onClose,
    this.onComplete,
  }) : configurationController = null;

  const ThemeV2SkillWizardSheet.configuration({
    super.key,
    required SkillCardConfigurationController controller,
    this.onClose,
    this.onComplete,
  }) : controller = null,
       configurationController = controller;

  final SkillWizardController? controller;
  final SkillCardConfigurationController? configurationController;
  final VoidCallback? onClose;
  final VoidCallback? onComplete;

  bool get isConfiguration => configurationController != null;

  @override
  State<ThemeV2SkillWizardSheet> createState() =>
      _ThemeV2SkillWizardSheetState();
}

class _ThemeV2SkillWizardSheetState extends State<ThemeV2SkillWizardSheet> {
  late final VoiceInputTextController _description = VoiceInputTextController(
    text: widget.controller?.description ?? '',
  );
  late final VoiceInputController _descriptionVoice;
  final Set<String> _activeQuestionVoice = {};

  Listenable get _listenable =>
      widget.configurationController ?? widget.controller!;

  @override
  void initState() {
    super.initState();
    _descriptionVoice = VoiceInputController(
      textController: _description,
      service: VoiceInputScope.sharedService,
    )..addListener(_voiceChanged);
    _description.addListener(_syncDescription);
    if (widget.configurationController != null) {
      unawaited(widget.configurationController!.load());
    }
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  void _syncDescription() {
    widget.controller?.setDescription(_description.text);
  }

  void _questionVoiceChanged(String key, bool busy) {
    if (busy) {
      _activeQuestionVoice.add(key);
    } else {
      _activeQuestionVoice.remove(key);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _description.removeListener(_syncDescription);
    _descriptionVoice.removeListener(_voiceChanged);
    unawaited(_descriptionVoice.close());
    _descriptionVoice.dispose();
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

  Future<void> _confirmCreation() async {
    if (!await widget.controller!.confirm() || !mounted) return;
    _complete();
  }

  Future<void> _saveConfiguration() async {
    if (!await widget.configurationController!.save() || !mounted) return;
    _complete();
  }

  void _complete() {
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
      animation: _listenable,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final stage = widget.isConfiguration
            ? SkillWizardStage.card
            : widget.controller!.stage;
        return AnimatedPadding(
          duration: media.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            width: double.infinity,
            height: media.size.height,
            child: Material(
              key: const ValueKey('skill-wizard-sheet'),
              color: context.themeV2.background,
              child: SafeArea(
                child: Column(
                  children: [
                    _WizardHeader(
                      title: widget.isConfiguration ? '卡片展示设置' : '创建新 Skill',
                      stage: stage,
                      canGoBack:
                          !widget.isConfiguration &&
                          stage != SkillWizardStage.describe,
                      onBack: widget.controller?.goBack,
                      onClose: _close,
                    ),
                    if (!widget.isConfiguration) ...[
                      _WizardProgress(stage: stage),
                      const SizedBox(height: ThemeV2Spacing.md),
                    ],
                    Expanded(child: _buildBody(stage)),
                    _buildFooter(stage),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(SkillWizardStage stage) {
    if (widget.isConfiguration) return _buildConfigurationCard();
    final controller = widget.controller!;
    return switch (stage) {
      SkillWizardStage.describe => _buildDescribe(controller),
      SkillWizardStage.fields => _buildFields(controller),
      SkillWizardStage.card => _buildCreationCard(controller),
    };
  }

  Widget _buildDescribe(SkillWizardController controller) {
    final tokens = context.themeV2;
    return SingleChildScrollView(
      key: const ValueKey('skill-describe-step'),
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        0,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '描述你想长期记录的内容',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Text(
            'AI 会先确认记录目标，再生成可编辑字段和后台识别规则。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          VoiceInputField(
            key: const ValueKey('skill-description-voice'),
            controller: _descriptionVoice,
            enabled: !controller.busy,
            builder: (context, voiceBusy) => TextField(
              key: const ValueKey('skill-wizard-description'),
              controller: _description,
              readOnly: voiceBusy,
              autofocus: true,
              minLines: 4,
              maxLines: 7,
              decoration: _inputDecoration('例如：记录每次跑步的距离、配速、地点和感受'),
            ),
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
          if (controller.questions.isNotEmpty) ...[
            const SizedBox(height: ThemeV2Spacing.xl),
            Text(
              '确认记录目标',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ThemeV2Spacing.xs),
            Text(
              '确认记录范围与每次想保留的信息，路由规则会在后台自动生成。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
            const SizedBox(height: ThemeV2Spacing.md),
            for (final question in controller.questions)
              _ClarificationQuestion(
                key: ValueKey('skill-question-${question.key}'),
                question: question,
                controller: controller,
                onVoiceBusyChanged: (busy) =>
                    _questionVoiceChanged(question.key, busy),
              ),
          ],
          const SizedBox(height: ThemeV2Spacing.xl),
          Container(
            padding: const EdgeInsets.all(ThemeV2Spacing.md),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 18, color: tokens.accent),
                const SizedBox(width: ThemeV2Spacing.sm),
                Expanded(
                  child: Text(
                    '描述使用场景与希望回看的信息，比只写一个名词更容易得到好字段。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ),
              ],
            ),
          ),
          _error(controller.errorMessage),
        ],
      ),
    );
  }

  Widget _buildFields(SkillWizardController controller) {
    return SingleChildScrollView(
      key: const ValueKey('skill-fields-step'),
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        0,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '定义字段',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Text(
            '名称、类型、含义与顺序会直接成为 Skill 的数据结构。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.themeV2.muted),
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          Row(
            children: [
              SizedBox(
                width: 66,
                child: TextFormField(
                  key: const ValueKey('skill-icon'),
                  initialValue: controller.icon,
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  onChanged: controller.setIcon,
                  decoration: _inputDecoration('✦').copyWith(counterText: ''),
                ),
              ),
              const SizedBox(width: ThemeV2Spacing.sm),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('skill-name'),
                  initialValue: controller.displayName,
                  onChanged: controller.setDisplayName,
                  decoration: _inputDecoration('Skill 名称'),
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: controller.fields.length,
            onReorderItem: controller.moveField,
            itemBuilder: (context, index) {
              final field = controller.fields[index];
              return _SkillFieldEditor(
                key: ValueKey('skill-field-${field.id}'),
                field: field,
                index: index,
                onChanged:
                    ({
                      String? key,
                      String? label,
                      String? type,
                      String? meaning,
                      bool? required,
                      bool? long,
                    }) => controller.updateField(
                      field.id,
                      key: key,
                      label: label,
                      type: type,
                      meaning: meaning,
                      required: required,
                      long: long,
                    ),
                onRemove: () => controller.removeField(field.id),
              );
            },
          ),
          OutlinedButton.icon(
            key: const ValueKey('skill-add-field'),
            onPressed: controller.addField,
            icon: const Icon(Icons.add),
            label: const Text('添加字段'),
          ),
          _error(controller.errorMessage),
        ],
      ),
    );
  }

  Widget _buildCreationCard(SkillWizardController controller) {
    final selection = controller.cardSelection!;
    final renderSpec = controller.composeRenderSpec();
    return _cardStep(
      preview: _preview(
        displayName: controller.displayName,
        schema: controller.payloadSchema,
        renderSpec: renderSpec,
        samplePayload: controller.samplePayload,
        config: selection.config,
      ),
      selector: selection,
      errorMessage: controller.errorMessage,
    );
  }

  Widget _buildConfigurationCard() {
    final controller = widget.configurationController!;
    if (controller.state == SkillConfigurationState.loading ||
        controller.state == SkillConfigurationState.idle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.state == SkillConfigurationState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ThemeV2Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.errorMessage ?? '展示设置加载失败'),
              const SizedBox(height: ThemeV2Spacing.md),
              OutlinedButton(
                onPressed: controller.load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final skill = controller.skill!;
    final selection = controller.selection!;
    return _cardStep(
      preview: _preview(
        displayName: skill.displayName,
        schema: skill.payloadSchema,
        renderSpec: skill.renderSpec,
        samplePayload: skill.samplePayload,
        config: selection.config,
      ),
      selector: selection,
      errorMessage: controller.errorMessage,
    );
  }

  Widget _cardStep({
    required AssetCardViewData preview,
    required CardFieldSelectionController selector,
    required String? errorMessage,
  }) {
    return SingleChildScrollView(
      key: const ValueKey('skill-card-step'),
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        0,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '卡片展示',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Text(
            '选择一个主字段，再按开启顺序加入最多三个次字段。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.themeV2.muted),
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          KeyedSubtree(
            key: const ValueKey('skill-card-preview'),
            child: ThemeV2AssetCard(
              variant: AssetCardVariant.richCard,
              data: preview,
              height: 98,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.xl),
          CardFieldSelector(controller: selector),
          _error(errorMessage),
        ],
      ),
    );
  }

  AssetCardViewData _preview({
    required String displayName,
    required Map<String, dynamic> schema,
    required Map<String, dynamic> renderSpec,
    required Map<String, dynamic> samplePayload,
    required CardDisplayConfig config,
  }) {
    final spec = RenderSpec.fromJson(
      config.applyToRenderSpec(renderSpec),
    ).withSchema(schema);
    return AssetCardViewData.fromPayload(
      payload: samplePayload,
      display: config,
      spec: spec,
      skillLabel: displayName,
    );
  }

  Widget _buildFooter(SkillWizardStage stage) {
    final tokens = context.themeV2;
    Widget actions;
    if (widget.isConfiguration) {
      final controller = widget.configurationController!;
      actions = SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey('skill-card-save'),
          onPressed: controller.busy ? null : _saveConfiguration,
          child: Text(controller.busy ? '保存中…' : '保存展示设置'),
        ),
      );
    } else {
      final controller = widget.controller!;
      actions = switch (stage) {
        SkillWizardStage.describe => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('skill-describe-generate'),
            onPressed:
                controller.busy ||
                    _descriptionVoice.isBusy ||
                    _activeQuestionVoice.isNotEmpty
                ? null
                : () => unawaited(controller.generate()),
            icon: controller.busy
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              controller.busy
                  ? '生成中…'
                  : controller.questions.isNotEmpty
                  ? '确认目标并生成字段'
                  : '下一步：确认并生成',
            ),
          ),
        ),
        SkillWizardStage.fields => Row(
          children: [
            TextButton(onPressed: controller.goBack, child: const Text('上一步')),
            const SizedBox(width: ThemeV2Spacing.sm),
            Expanded(
              child: FilledButton(
                key: const ValueKey('skill-fields-next'),
                onPressed: controller.goToCard,
                child: const Text('下一步：卡片展示'),
              ),
            ),
          ],
        ),
        SkillWizardStage.card => Row(
          children: [
            TextButton(onPressed: controller.goBack, child: const Text('上一步')),
            const SizedBox(width: ThemeV2Spacing.sm),
            Expanded(
              child: FilledButton(
                key: const ValueKey('skill-card-confirm'),
                onPressed: controller.busy ? null : _confirmCreation,
                child: Text(controller.busy ? '创建中…' : '创建 Skill'),
              ),
            ),
          ],
        ),
      };
    }
    return Material(
      color: tokens.background,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          ThemeV2Spacing.xl,
          ThemeV2Spacing.md,
          ThemeV2Spacing.xl,
          ThemeV2Spacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: actions,
      ),
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
      fillColor: tokens.surface,
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
  const _WizardHeader({
    required this.title,
    required this.stage,
    required this.canGoBack,
    required this.onBack,
    required this.onClose,
  });

  final String title;
  final SkillWizardStage stage;
  final bool canGoBack;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.md),
        child: Row(
          children: [
            if (canGoBack)
              ThemeV2IconButton(
                semanticLabel: '上一步',
                icon: Icons.arrow_back,
                onPressed: onBack,
              )
            else
              const SizedBox(width: ThemeV2Sizes.minTouchTarget),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ThemeV2IconButton(
              semanticLabel: '关闭 Skill Builder',
              icon: Icons.close,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.stage});

  final SkillWizardStage stage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final active = stage.index;
    const labels = ['Describe', 'Fields', 'Card'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.xl),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: ThemeV2Spacing.sm),
            Expanded(
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    decoration: BoxDecoration(
                      color: index <= active ? tokens.accent : tokens.border,
                      borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    style: ThemeV2Typography.mono(
                      fontSize: 8,
                      color: index == active ? tokens.accent : tokens.muted,
                      fontWeight: index == active
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClarificationQuestion extends StatefulWidget {
  const _ClarificationQuestion({
    super.key,
    required this.question,
    required this.controller,
    required this.onVoiceBusyChanged,
  });

  final SkillWizardQuestion question;
  final SkillWizardController controller;
  final ValueChanged<bool> onVoiceBusyChanged;

  @override
  State<_ClarificationQuestion> createState() => _ClarificationQuestionState();
}

class _ClarificationQuestionState extends State<_ClarificationQuestion> {
  late final TextEditingController _other = TextEditingController(
    text: widget.controller.otherTextFor(widget.question.key),
  )..addListener(_syncOther);

  void _syncOther() {
    widget.controller.setQuestionOtherText(widget.question.key, _other.text);
  }

  @override
  void dispose() {
    _other
      ..removeListener(_syncOther)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.prompt,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          Wrap(
            spacing: ThemeV2Spacing.sm,
            runSpacing: ThemeV2Spacing.sm,
            children: [
              for (final option in question.options)
                _SuggestionChip(
                  label: option,
                  selected: controller
                      .selectedOptionsFor(question.key)
                      .contains(option),
                  onPressed: () =>
                      controller.toggleQuestionOption(question.key, option),
                ),
              _SuggestionChip(
                key: ValueKey('skill-question-other-${question.key}'),
                label: '其他',
                selected: controller.isOtherSelected(question.key),
                onPressed: () => controller.toggleQuestionOther(question.key),
              ),
            ],
          ),
          if (controller.isOtherSelected(question.key)) ...[
            const SizedBox(height: ThemeV2Spacing.sm),
            VoiceInputTextAdapter(
              key: ValueKey('skill-question-other-voice-${question.key}'),
              controller: _other,
              enabled: !controller.busy,
              onBusyChanged: widget.onVoiceBusyChanged,
              builder: (context, textController, voiceBusy) => TextFormField(
                key: ValueKey('skill-question-other-input-${question.key}'),
                controller: textController,
                readOnly: voiceBusy,
                decoration: InputDecoration(hintText: question.placeholder),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

typedef _FieldChanged =
    void Function({
      String? key,
      String? label,
      String? type,
      String? meaning,
      bool? required,
      bool? long,
    });

class _SkillFieldEditor extends StatelessWidget {
  const _SkillFieldEditor({
    super.key,
    required this.field,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  static const _types = {
    'string': '短文本',
    'markdown': 'Markdown 长文本',
    'number': '数字',
    'date': '日期',
    'datetime': '日期时间',
    'boolean': '布尔值',
    'array': '列表',
  };

  final SkillDraftField field;
  final int index;
  final _FieldChanged onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final currentType = field.long
        ? 'markdown'
        : (_types.containsKey(field.type) ? field.type : 'string');
    return Container(
      margin: const EdgeInsets.only(bottom: ThemeV2Spacing.md),
      padding: const EdgeInsets.all(ThemeV2Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_indicator, color: tokens.muted),
              ),
              const SizedBox(width: ThemeV2Spacing.sm),
              Expanded(
                child: Text(
                  'FIELD ${index + 1}',
                  style: ThemeV2Typography.mono(
                    fontSize: 9,
                    color: tokens.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.close, color: tokens.muted),
                tooltip: '删除字段',
              ),
            ],
          ),
          TextFormField(
            key: ValueKey('skill-field-label-${field.id}'),
            initialValue: field.label,
            onChanged: (value) => onChanged(label: value),
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          DropdownButtonFormField<String>(
            key: ValueKey('skill-field-type-${field.id}'),
            initialValue: currentType,
            decoration: const InputDecoration(labelText: '类型'),
            items: [
              for (final entry in _types.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value == null) return;
              if (value == 'markdown') {
                onChanged(type: 'string', long: true);
              } else {
                onChanged(type: value, long: false);
              }
            },
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          TextFormField(
            key: ValueKey('skill-field-meaning-${field.id}'),
            initialValue: field.meaning,
            onChanged: (value) => onChanged(meaning: value),
            decoration: const InputDecoration(labelText: '含义'),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    super.key,
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
    return ActionChip(
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: selected ? tokens.accentSoft : tokens.surface,
      side: BorderSide(color: selected ? tokens.accent : tokens.border),
      labelStyle: TextStyle(
        color: selected ? tokens.accent : tokens.muted,
        fontSize: 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}
