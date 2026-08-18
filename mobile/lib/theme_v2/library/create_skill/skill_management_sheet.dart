import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/theme_v2_theme.dart';
import 'skill_management_controller.dart';

class ThemeV2SkillManagementSheet extends StatefulWidget {
  const ThemeV2SkillManagementSheet({
    super.key,
    required this.controller,
    this.onClose,
    this.onSaved,
    this.onDeleted,
  });

  final SkillManagementController controller;
  final VoidCallback? onClose;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;

  @override
  State<ThemeV2SkillManagementSheet> createState() =>
      _ThemeV2SkillManagementSheetState();
}

class _ThemeV2SkillManagementSheetState
    extends State<ThemeV2SkillManagementSheet> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Material(
        color: context.themeV2.background,
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(child: _body()),
              if (widget.controller.state == SkillManagementState.ready ||
                  widget.controller.state == SkillManagementState.saving)
                _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '管理 Skill',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close),
        ),
      ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(controller.errorMessage ?? 'Skill 加载失败'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: controller.load, child: const Text('重试')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        TextFormField(
          key: ValueKey('skill-name-${controller.skill!.updatedAt}'),
          initialValue: controller.displayName,
          onChanged: controller.setDisplayName,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('skill-description-${controller.skill!.updatedAt}'),
          initialValue: controller.description,
          minLines: 2,
          maxLines: 4,
          onChanged: controller.setDescription,
          decoration: const InputDecoration(labelText: '说明'),
        ),
        const SizedBox(height: 24),
        Text(
          '记录字段',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '已有字段的键和类型保持不变；不想继续使用时可以隐藏。新字段默认选填。',
          style: TextStyle(color: context.themeV2.muted),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < controller.fields.length; index++)
          _fieldCard(index, controller.fields[index]),
        OutlinedButton.icon(
          key: const ValueKey('custom-skill-add-field'),
          onPressed: _addField,
          icon: const Icon(Icons.add),
          label: const Text('添加选填字段'),
        ),
        const SizedBox(height: 32),
        Divider(color: context.themeV2.border),
        const SizedBox(height: 12),
        Text(
          '危险操作',
          style: TextStyle(
            color: context.themeV2.critical,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('custom-skill-delete'),
          onPressed: controller.busy ? null : _confirmDelete,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.themeV2.critical,
          ),
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除 Skill 与全部记录'),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.errorMessage!,
            style: TextStyle(color: context.themeV2.critical),
          ),
        ],
      ],
    );
  }

  Widget _fieldCard(int index, SkillManagementField field) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    color: context.themeV2.surface,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${field.key} · ${field.type}',
                  style: TextStyle(color: context.themeV2.muted, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: '上移',
                onPressed: index == 0
                    ? null
                    : () => widget.controller.reorderField(index, index - 1),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: '下移',
                onPressed: index == widget.controller.fields.length - 1
                    ? null
                    : () => widget.controller.reorderField(index, index + 2),
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              Switch.adaptive(
                value: !field.hidden,
                onChanged: (visible) =>
                    widget.controller.setFieldHidden(field.key, !visible),
              ),
            ],
          ),
          TextFormField(
            key: ValueKey('skill-field-label-${field.key}'),
            initialValue: field.label,
            onChanged: (value) =>
                widget.controller.updateFieldLabel(field.key, value),
            decoration: const InputDecoration(labelText: '展示名称'),
          ),
          TextFormField(
            key: ValueKey('skill-field-meaning-${field.key}'),
            initialValue: field.meaning,
            onChanged: (value) =>
                widget.controller.updateFieldMeaning(field.key, value),
            decoration: const InputDecoration(labelText: '字段含义（选填）'),
          ),
        ],
      ),
    ),
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: BoxDecoration(
      color: context.themeV2.surface,
      border: Border(top: BorderSide(color: context.themeV2.border)),
    ),
    child: FilledButton(
      onPressed: widget.controller.busy
          ? null
          : () async {
              if (await widget.controller.save() && mounted) {
                widget.onSaved?.call();
              }
            },
      child: Text(widget.controller.busy ? '保存中…' : '保存修改'),
    ),
  );

  Future<void> _addField() async {
    final key = TextEditingController();
    final label = TextEditingController();
    var type = 'string';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加选填字段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              TextField(
                controller: key,
                decoration: const InputDecoration(labelText: '字段键（英文）'),
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

  Future<void> _confirmDelete() async {
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
            style: FilledButton.styleFrom(
              backgroundColor: context.themeV2.critical,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await widget.controller.deleteSkill() != null && mounted) {
      widget.onDeleted?.call();
    }
  }
}
