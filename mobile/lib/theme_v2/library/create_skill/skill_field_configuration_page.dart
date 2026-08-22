import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import 'skill_management_controller.dart';

class ThemeV2SkillFieldConfigurationPage extends StatefulWidget {
  const ThemeV2SkillFieldConfigurationPage({
    super.key,
    required this.controller,
    this.onSaved,
    this.onDeleted,
  });

  final SkillManagementController controller;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;

  @override
  State<ThemeV2SkillFieldConfigurationPage> createState() =>
      _ThemeV2SkillFieldConfigurationPageState();
}

class _ThemeV2SkillFieldConfigurationPageState
    extends State<ThemeV2SkillFieldConfigurationPage> {
  var _deleteFlowInFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      backgroundColor: context.themeV2.background,
      appBar: AppBar(
        backgroundColor: context.themeV2.background,
        title: const Text('字段配置'),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('custom-skill-more'),
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'delete') unawaited(_confirmDeleteSkill());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('删除这个 Skill')),
            ],
          ),
          TextButton(
            key: const ValueKey('skill-fields-save'),
            onPressed: widget.controller.busy || _deleteFlowInFlight
                ? null
                : _save,
            child: Text(
              widget.controller.state == SkillManagementState.saving
                  ? '保存中…'
                  : '保存',
            ),
          ),
          const SizedBox(width: ThemeV2Spacing.sm),
        ],
      ),
      body: SafeArea(child: _body()),
    ),
  );

  Widget _body() {
    final controller = widget.controller;
    if (controller.state == SkillManagementState.idle ||
        controller.state == SkillManagementState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.skill == null) {
      return Center(
        child: FilledButton.tonal(
          onPressed: controller.load,
          child: const Text('重新加载'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.lg,
        ThemeV2Spacing.md,
        ThemeV2Spacing.lg,
        ThemeV2Spacing.xl,
      ),
      children: [
        Text(
          '字段只影响今后新归类的内容，不会改动已有资产。',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.themeV2.muted),
        ),
        const SizedBox(height: ThemeV2Spacing.lg),
        for (final field in controller.fields) _fieldCard(field),
        FilledButton.tonalIcon(
          key: const ValueKey('custom-skill-add-field'),
          onPressed: _addField,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加字段'),
        ),
        if (controller.errorMessage case final message?) ...[
          const SizedBox(height: ThemeV2Spacing.md),
          Text(message, style: TextStyle(color: context.themeV2.critical)),
        ],
      ],
    );
  }

  Widget _fieldCard(SkillManagementField field) => Container(
    key: ValueKey('skill-field-row-${field.key}'),
    margin: const EdgeInsets.only(bottom: ThemeV2Spacing.md),
    padding: const EdgeInsets.all(ThemeV2Spacing.md),
    decoration: BoxDecoration(
      color: context.themeV2.surface,
      borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
      border: Border.all(color: context.themeV2.border),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${field.key}  ·  ${_typeLabel(field.type)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
              ),
            ),
            IconButton(
              key: ValueKey('skill-field-delete-${field.key}'),
              tooltip: '删除字段',
              onPressed: () => widget.controller.removeField(field.key),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        TextFormField(
          key: ValueKey('skill-field-label-${field.key}'),
          initialValue: field.label,
          onChanged: (value) =>
              widget.controller.updateFieldLabel(field.key, value),
          decoration: const InputDecoration(labelText: '字段名称'),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        TextFormField(
          key: ValueKey('skill-field-meaning-${field.key}'),
          initialValue: field.meaning,
          onChanged: (value) =>
              widget.controller.updateFieldMeaning(field.key, value),
          decoration: const InputDecoration(labelText: '字段说明'),
        ),
      ],
    ),
  );

  String _typeLabel(String type) => switch (type) {
    'number' => '数字',
    'integer' => '整数',
    'boolean' => '是 / 否',
    'array' => '多个值',
    _ => '文本',
  };

  Future<void> _save() async {
    if (await widget.controller.saveFieldsOnly() && mounted) {
      widget.onSaved?.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  Future<void> _addField() async {
    final key = TextEditingController();
    final label = TextEditingController();
    var type = 'string';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加字段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: '字段名称'),
              ),
              TextField(
                controller: key,
                decoration: const InputDecoration(labelText: '字段 ID（英文）'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: '类型'),
                items: const [
                  DropdownMenuItem(value: 'string', child: Text('文本')),
                  DropdownMenuItem(value: 'number', child: Text('数字')),
                  DropdownMenuItem(value: 'boolean', child: Text('是 / 否')),
                  DropdownMenuItem(value: 'array', child: Text('多个值')),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      widget.controller.addField(key: key.text, label: label.text, type: type);
    }
    key.dispose();
    label.dispose();
  }

  Future<void> _confirmDeleteSkill() async {
    if (_deleteFlowInFlight || widget.controller.busy) return;
    setState(() => _deleteFlowInFlight = true);
    try {
      final count = await widget.controller.loadDeletionImpact();
      if (count == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('永久删除这个 Skill？'),
          content: Text('将同时永久删除 $count 条记录，此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('custom-skill-delete-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (await widget.controller.deleteSkill() != null && mounted) {
        widget.onDeleted?.call();
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _deleteFlowInFlight = false);
    }
  }
}
