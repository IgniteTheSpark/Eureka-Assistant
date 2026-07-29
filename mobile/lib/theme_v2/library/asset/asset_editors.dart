import 'package:flutter/material.dart';

import '../../../render/render_spec.dart';
import 'asset_editor.dart';

RenderSpec themeV2AssetEditorSpec(String cardType, RenderSpec base) {
  final definitions = switch (cardType) {
    'todo' => const [
      ('title', '标题', 'string', true, false),
      ('due_at', '截止时间', 'datetime', false, false),
      ('notes', '备注', 'string', false, true),
      ('reminder_at', '提醒', 'datetime', false, false),
      ('status', '状态', 'string', false, false),
    ],
    'notes' || 'note' => const [
      ('title', '标题', 'string', true, false),
      ('tags', '标签', 'array', false, false),
      ('body', '正文', 'string', false, true),
      ('domain', '领域', 'string', false, false),
    ],
    'event' => const [
      ('title', '标题', 'string', true, false),
      ('start_at', '开始', 'datetime', true, false),
      ('end_at', '结束', 'datetime', false, false),
      ('location', '地点', 'string', false, false),
      ('attendees', '参与人', 'array', false, false),
      ('notes', '备注', 'string', false, true),
    ],
    'contact' => const [
      ('name', '姓名', 'string', true, false),
      ('company', '公司', 'string', false, false),
      ('title', '职位', 'string', false, false),
      ('phone', '电话', 'string', false, false),
      ('email', '邮箱', 'string', false, false),
      ('social', '社交账号', 'string', false, false),
      ('notes', '备注', 'string', false, true),
    ],
    _ => const <(String, String, String, bool, bool)>[],
  };
  if (definitions.isEmpty) return base;

  final systemFields = definitions.map((field) => field.$1).toList();
  final fields = [
    ...systemFields,
    for (final field in base.schemaFields)
      if (!systemFields.contains(field)) field,
  ];
  final labels = Map<String, String>.from(base.fieldLabels);
  final types = Map<String, String>.from(base.fieldTypes);
  final required = Set<String>.from(base.requiredFields);
  final longs = Set<String>.from(base.longFields);
  for (final field in definitions) {
    labels[field.$1] = field.$2;
    types[field.$1] = field.$3;
    if (field.$4) required.add(field.$1);
    if (field.$5) longs.add(field.$1);
  }
  return base.copyWith(
    primaryField: switch (cardType) {
      'contact' => 'name',
      _ => 'title',
    },
    secondaryField: switch (cardType) {
      'todo' => 'due_at',
      'event' => 'start_at',
      'contact' => 'company',
      _ => base.secondaryField,
    },
    schemaFields: fields,
    fieldLabels: labels,
    fieldTypes: types,
    requiredFields: required,
    longFields: longs,
  );
}

class AssetEditorRouter extends StatelessWidget {
  const AssetEditorRouter({
    super.key,
    required this.cardType,
    required this.draft,
    required this.onSave,
    this.scrollController,
  });

  final String cardType;
  final AssetEditorDraft draft;
  final Future<void> Function(Map<String, dynamic> payload) onSave;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return ThemeV2AssetEditor(
      draft: draft,
      onSave: onSave,
      scrollController: scrollController,
      previewLabel: switch (cardType) {
        'todo' => '待办',
        'notes' || 'note' => '随记',
        'event' => '事件',
        'contact' => '联系人',
        _ => cardType,
      },
    );
  }
}
