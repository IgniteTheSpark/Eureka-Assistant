import 'package:flutter/material.dart';

import '../../asset/asset_card.dart';
import '../../asset/asset_card_display.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../../render/render_spec.dart';

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
  });

  final AssetEditorDraft draft;
  final Future<void> Function(Map<String, dynamic> payload) onSave;
  final ScrollController? scrollController;
  final bool showActions;
  final String previewLabel;

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
                    _EditorField(draft: draft, field: field),
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
  const _EditorField({required this.draft, required this.field});

  final AssetEditorDraft draft;
  final String field;

  @override
  Widget build(BuildContext context) {
    final required = draft.spec.requiredFields.contains(field);
    final label = '${draft.labelFor(field)}${required ? ' *' : ''}';
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
    return TextField(
      key: ValueKey('asset-editor-$field'),
      controller: draft.controllerFor(field),
      minLines: long ? 5 : 1,
      maxLines: long ? null : 1,
      keyboardType: switch (draft.typeFor(field)) {
        'number' ||
        'numeric' => const TextInputType.numberWithOptions(decimal: true),
        'datetime' || 'date' => TextInputType.datetime,
        _ => long ? TextInputType.multiline : TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: long,
        errorText: draft.errors[field],
      ),
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
