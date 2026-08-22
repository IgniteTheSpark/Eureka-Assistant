import 'package:flutter/material.dart';

import '../../asset/asset_card.dart';
import '../../asset/asset_card_display.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_time_formatter.dart';
import '../../../render/render_spec.dart';
import '../../../voice_input/voice_input_field.dart';
import '../../asset_detail/markdown_field_editor.dart';

class AssetEditorDraft extends ChangeNotifier {
  AssetEditorDraft({required Map<String, dynamic> payload, required this.spec})
    : _values = Map<String, dynamic>.from(payload) {
    for (final field in fields) {
      final value = _values[field];
      if (_isTextField(field)) {
        final controller = TextEditingController(
          text: value is List ? value.join(', ') : value?.toString() ?? '',
        );
        controller.addListener(() => _onTextChanged(field, controller.text));
        _controllers[field] = controller;
      }
    }
    _initial = Map<String, dynamic>.from(this.payload);
  }

  final RenderSpec spec;
  late Map<String, dynamic> _initial;
  final Map<String, dynamic> _values;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> errors = {};

  List<String> get fields => [
    ...spec.schemaFields,
    for (final key in _values.keys)
      if (!spec.schemaFields.contains(key)) key,
  ];

  bool get isDirty => !_deepEquals(_initial, payload);

  Map<String, dynamic> get payload {
    final result = Map<String, dynamic>.from(_values);
    for (final entry in _controllers.entries) {
      result[entry.key] = _parse(entry.key, entry.value.text);
    }
    return result;
  }

  TextEditingController controllerFor(String field) => _controllers[field]!;

  bool boolValue(String field) => _values[field] == true;

  Object? valueFor(String field) => payload[field];

  void setValue(String field, Object? value) {
    _values[field] = value;
    final controller = _controllers[field];
    if (controller != null && controller.text != (value?.toString() ?? '')) {
      controller.text = value?.toString() ?? '';
      return;
    }
    errors.remove(field);
    notifyListeners();
  }

  void setBool(String field, bool value) {
    _values[field] = value;
    errors.remove(field);
    notifyListeners();
  }

  bool validate() {
    errors.clear();
    final current = payload;
    for (final field in spec.requiredFields) {
      final value = current[field];
      final missing =
          value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is Iterable && value.isEmpty);
      if (missing) {
        errors[field] = '请填写${labelFor(field)}';
      }
    }
    notifyListeners();
    return errors.isEmpty;
  }

  void acceptSaved() {
    _initial = Map<String, dynamic>.from(payload);
    errors.clear();
    notifyListeners();
  }

  String labelFor(String field) => spec.fieldLabels[field] ?? field;

  bool isLong(String field) => spec.longFields.contains(field);

  String typeFor(String field) => spec.fieldTypes[field] ?? 'string';

  bool _isTextField(String field) => typeFor(field) != 'boolean';

  dynamic _parse(String field, String raw) {
    switch (typeFor(field)) {
      case 'number':
      case 'numeric':
        return num.tryParse(raw.trim()) ?? raw.trim();
      case 'array':
        return raw
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
      default:
        return raw;
    }
  }

  void _onTextChanged(String field, String value) {
    _values[field] = _parse(field, value);
    errors.remove(field);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class ThemeV2AssetEditor extends StatelessWidget {
  const ThemeV2AssetEditor({
    super.key,
    required this.draft,
    required this.onSave,
    this.scrollController,
    this.showActions = true,
    this.previewLabel = '资产',
    this.now,
  });

  final AssetEditorDraft draft;
  final Future<void> Function(Map<String, dynamic> payload) onSave;
  final ScrollController? scrollController;
  final bool showActions;
  final String previewLabel;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedBuilder(
      animation: draft,
      builder: (context, _) => AnimatedPadding(
        key: const ValueKey('asset-editor-keyboard-padding'),
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.only(bottom: inset + ThemeV2Spacing.lg),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeV2Spacing.xl,
                ThemeV2Spacing.sm,
                ThemeV2Spacing.xl,
                ThemeV2Spacing.md,
              ),
              child: KeyedSubtree(
                key: const ValueKey('asset-editor-preview'),
                child: ThemeV2AssetCard(
                  variant: AssetCardVariant.richCard,
                  data: _previewData(),
                  height: 86,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  ThemeV2Spacing.xl,
                  0,
                  ThemeV2Spacing.xl,
                  ThemeV2Spacing.lg,
                ),
                children: [
                  for (final field in draft.fields) ...[
                    _EditorField(draft: draft, field: field, now: now),
                    const SizedBox(height: ThemeV2Spacing.lg),
                  ],
                ],
              ),
            ),
            if (showActions)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.xl,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('asset-editor-save'),
                    onPressed: () async {
                      if (!draft.validate()) return;
                      await onSave(draft.payload);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  AssetCardViewData _previewData() {
    final fields = draft.fields;
    final primary =
        draft.spec.primaryField ??
        fields.firstOrNull ??
        draft.payload.keys.firstOrNull ??
        'title';
    final secondary = <String>[
      if (draft.spec.secondaryField case final field?)
        if (field.trim().isNotEmpty) field,
      for (final meta in draft.spec.metaFields)
        if (meta.field.trim().isNotEmpty) meta.field,
    ];
    return AssetCardViewData.fromPayload(
      payload: draft.payload,
      display: CardDisplayConfig(
        primaryFieldId: primary,
        secondaryFieldIds: secondary,
      ),
      spec: draft.spec,
      skillLabel: previewLabel,
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({required this.draft, required this.field, this.now});

  final AssetEditorDraft draft;
  final String field;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final required = draft.spec.requiredFields.contains(field);
    final label = '${draft.labelFor(field)}${required ? ' *' : ''}';
    if (field == 'due_date' && draft.typeFor(field) == 'datetime') {
      final value = parseThemeV2DateTime(draft.valueFor(field));
      return TodoDeadlineField(
        value: value ?? defaultTodoDeadline(now: now?.call()),
        now: now,
        onChanged: (next) => draft.setValue(field, themeV2ApiDateTime(next)),
      );
    }
    if (draft.typeFor(field) == 'boolean') {
      return SwitchListTile(
        key: ValueKey('asset-editor-$field'),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: draft.boolValue(field),
        onChanged: (value) => draft.setBool(field, value),
      );
    }
    final long = draft.isLong(field);
    if (long) {
      return MarkdownFieldEditor(
        key: ValueKey('asset-editor-$field'),
        label: label,
        controller: draft.controllerFor(field),
        errorText: draft.errors[field],
      );
    }
    if (draft.typeFor(field) == 'string') {
      return VoiceInputTextAdapter(
        key: ValueKey('asset-editor-voice-$field'),
        controller: draft.controllerFor(field),
        builder: (context, controller, voice) => _shortTextField(
          controller,
          label: label,
          readOnly: voice.isBusy,
          statusIcon: voice.statusIcon(color: ThemeV2Tokens.of(context).accent),
        ),
      );
    }
    return _shortTextField(
      draft.controllerFor(field),
      label: label,
      readOnly: false,
      statusIcon: null,
    );
  }

  Widget _shortTextField(
    TextEditingController controller, {
    required String label,
    required bool readOnly,
    required Widget? statusIcon,
  }) {
    return TextField(
      key: ValueKey('asset-editor-$field'),
      controller: controller,
      readOnly: readOnly,
      minLines: 1,
      maxLines: 1,
      keyboardType: switch (draft.typeFor(field)) {
        'number' ||
        'numeric' => const TextInputType.numberWithOptions(decimal: true),
        'datetime' || 'date' => TextInputType.datetime,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: label,
        errorText: draft.errors[field],
        suffixIcon: statusIcon,
      ),
    );
  }
}

class TodoDeadlineField extends StatelessWidget {
  const TodoDeadlineField({
    super.key,
    required this.value,
    required this.onChanged,
    this.now,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime Function()? now;

  Future<void> _pickCustom(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择截止日期',
    );
    if (date == null || !context.mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
      helpText: '选择截止时间',
    );
    if (clock == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, clock.hour, clock.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = (now?.call() ?? DateTime.now()).toLocal();
    return Column(
      key: const ValueKey('todo-deadline-field'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('截止时间', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: ThemeV2Spacing.xs),
        Text(
          formatFullLocalDateTime(themeV2ApiDateTime(value)),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        Wrap(
          spacing: ThemeV2Spacing.sm,
          runSpacing: ThemeV2Spacing.sm,
          children: [
            OutlinedButton(
              key: const ValueKey('todo-deadline-today'),
              onPressed: () =>
                  onChanged(defaultTodoDeadline(now: today, date: today)),
              child: const Text('今天'),
            ),
            OutlinedButton(
              key: const ValueKey('todo-deadline-tomorrow'),
              onPressed: () => onChanged(
                defaultTodoDeadline(
                  now: today,
                  date: today.add(const Duration(days: 1)),
                ),
              ),
              child: const Text('明天'),
            ),
            OutlinedButton(
              key: const ValueKey('todo-deadline-custom'),
              onPressed: () => _pickCustom(context),
              child: const Text('自定义'),
            ),
          ],
        ),
      ],
    );
  }
}

bool _deepEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (entry.value is List && other is List) {
      if (entry.value.length != other.length) return false;
      for (var i = 0; i < entry.value.length; i++) {
        if (entry.value[i] != other[i]) return false;
      }
    } else if (entry.value != other) {
      return false;
    }
  }
  return true;
}
