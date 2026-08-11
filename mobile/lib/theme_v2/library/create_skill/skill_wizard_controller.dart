import 'package:flutter/foundation.dart';

import '../../../api/api_client.dart';
import '../../asset/asset_card_display.dart';
import '../../asset/card_field_selection.dart';

enum SkillWizardStage { describe, fields, card }

enum SkillFieldSlot { primary, secondary, info, hidden }

@immutable
class SkillWizardQuestion {
  const SkillWizardQuestion({
    required this.key,
    required this.prompt,
    required this.type,
    required this.multiple,
    required this.options,
    required this.placeholder,
  });

  factory SkillWizardQuestion.fromJson(Map<String, dynamic> json) {
    return SkillWizardQuestion(
      key: json['key']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      multiple: json['multiple'] == true,
      options: List.unmodifiable(
        (json['options'] as List? ?? const []).map((item) => item.toString()),
      ),
      placeholder: json['placeholder']?.toString() ?? '可留空',
    );
  }

  final String key;
  final String prompt;
  final String type;
  final bool multiple;
  final List<String> options;
  final String placeholder;
}

@immutable
class SkillDraftField {
  const SkillDraftField({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    required this.meaning,
    required this.required,
    required this.long,
    this.metadata = const {},
  });

  final String id;
  final String key;
  final String label;
  final String type;
  final String meaning;
  final bool required;
  final bool long;
  final Map<String, dynamic> metadata;

  SkillDraftField copyWith({
    String? key,
    String? label,
    String? type,
    String? meaning,
    bool? required,
    bool? long,
  }) {
    return SkillDraftField(
      id: id,
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      meaning: meaning ?? this.meaning,
      required: required ?? this.required,
      long: long ?? this.long,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toSchemaJson() {
    final output = Map<String, dynamic>.from(metadata)
      ..['type'] = type
      ..['label'] = label
      ..['required'] = required
      ..['long'] = long;
    output.remove('meaning');
    if (meaning.trim().isEmpty) {
      output.remove('description');
    } else {
      output['description'] = meaning.trim();
    }
    return output;
  }
}

typedef SkillPreviewField = SkillDraftField;

abstract interface class SkillWizardRepository {
  Future<Map<String, dynamic>> draft(Map<String, dynamic> body);

  Future<void> confirm(Map<String, dynamic> body);
}

class ApiSkillWizardRepository implements SkillWizardRepository {
  ApiSkillWizardRepository([ApiClient? api])
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<Map<String, dynamic>> draft(Map<String, dynamic> body) async {
    final response = await _api.postJson('/api/user-skills/draft', body);
    if (response is! Map) {
      throw const FormatException('技能设计服务返回格式错误');
    }
    return response.cast<String, dynamic>();
  }

  @override
  Future<void> confirm(Map<String, dynamic> body) async {
    final payloadSchema =
        (body['payload_schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    final routingProfile =
        (body['routing_profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    await _api.postJson('/api/user-skills', {
      'machine_name': body['name'],
      'display_name': body['display_name'],
      'description': body['description'],
      'schema': _themeV2SkillSchema(payloadSchema, routingProfile),
      'render_spec': body['render_spec'] ?? const <String, dynamic>{},
      'chat_starters': body['chat_starters'] ?? const <dynamic>[],
    });
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

Map<String, dynamic> _themeV2SkillSchema(
  Map<String, dynamic> payloadSchema,
  Map<String, dynamic> routingProfile,
) {
  final properties = <String, dynamic>{};
  for (final entry in payloadSchema.entries) {
    final metadata = (entry.value as Map?)?.cast<String, dynamic>() ?? const {};
    final sourceType = metadata['type']?.toString() ?? 'string';
    final property = <String, dynamic>{
      'type': switch (sourceType) {
        'date' || 'datetime' || 'uuid' => 'string',
        _ => sourceType,
      },
      if (sourceType == 'date') 'format': 'date',
      if (sourceType == 'datetime') 'format': 'date-time',
      if (sourceType == 'uuid') 'format': 'uuid',
      'title': metadata['label']?.toString() ?? entry.key,
      'description': metadata['description']?.toString() ?? '',
      'x-long': metadata['long'] == true,
    };
    properties[entry.key] = property;
  }
  return {
    'type': 'object',
    'properties': properties,
    // Custom capture fields are always optional. `primary_field` and field
    // ordering remain presentation hints, never Agent-write invariants.
    'required': const <String>[],
    'additionalProperties': false,
    'x-capture-enabled': true,
    if (routingProfile.isNotEmpty)
      'x-routing': Map<String, dynamic>.from(routingProfile),
  };
}

class SkillWizardController extends ChangeNotifier {
  SkillWizardController({
    required this.repository,
    this.onCreated,
    this.disposeRepository = false,
  });

  final SkillWizardRepository repository;
  final VoidCallback? onCreated;
  final bool disposeRepository;

  SkillWizardStage _stage = SkillWizardStage.describe;
  bool _busy = false;
  bool _completed = false;
  String _description = '';
  String? _errorMessage;
  List<SkillWizardQuestion> _questions = const [];
  final Map<String, String> _answers = {};
  final Map<String, Set<String>> _selectedQuestionOptions = {};
  final Set<String> _questionOtherSelected = {};
  final Map<String, String> _questionOtherText = {};
  Map<String, dynamic>? _draft;
  final List<SkillDraftField> _fields = [];
  final Map<String, dynamic> _hiddenSchema = {};
  Map<String, dynamic> _originalRenderSpec = {};
  Map<String, dynamic> _samplePayload = {};
  final Set<String> _generatedSampleKeys = {};
  List<dynamic> _chatStarters = const [];
  String _skillDescription = '';
  Map<String, dynamic> _routingProfile = {};
  String _displayName = '';
  String _icon = '•';
  CardFieldSelectionController? _cardSelection;
  int _generationRevision = 0;
  int _newFieldRevision = 0;
  bool _disposed = false;

  SkillWizardStage get stage => _stage;
  bool get busy => _busy;
  bool get completed => _completed;
  String get description => _description;
  String? get errorMessage => _errorMessage;
  List<SkillWizardQuestion> get questions => _questions;
  Map<String, String> get answers => Map.unmodifiable(_answers);
  List<SkillDraftField> get fields => List.unmodifiable(_fields);
  String get displayName => _displayName;
  String get icon => _icon;
  Map<String, dynamic>? get draft =>
      _draft == null ? null : Map.unmodifiable(_draft!);
  Map<String, dynamic> get samplePayload => Map.unmodifiable(_samplePayload);
  CardFieldSelectionController? get cardSelection => _cardSelection;

  Map<String, dynamic> get payloadSchema {
    return {
      ..._hiddenSchema,
      for (final field in _fields) field.key: field.toSchemaJson(),
    };
  }

  void setDescription(String value) {
    if (_description == value) return;
    _description = value;
    _errorMessage = null;
    _notify();
  }

  void answer(String key, String value) {
    _answers[key] = value;
    final question = _questionFor(key);
    if (question != null) {
      final parts = value
          .split(RegExp(r'[、,，]'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final selected = <String>{
        for (final option in question.options)
          if (parts.contains(option)) option,
      };
      _selectedQuestionOptions[key] = selected;
      final custom = parts
          .where((part) => !question.options.contains(part))
          .join('、');
      if (custom.isEmpty) {
        _questionOtherSelected.remove(key);
        _questionOtherText.remove(key);
      } else {
        _questionOtherSelected.add(key);
        _questionOtherText[key] = custom;
      }
    }
    _errorMessage = null;
    _notify();
  }

  String answerFor(String key) => _answers[key] ?? '';

  Set<String> selectedOptionsFor(String key) =>
      Set.unmodifiable(_selectedQuestionOptions[key] ?? const <String>{});

  bool isOtherSelected(String key) => _questionOtherSelected.contains(key);

  String otherTextFor(String key) => _questionOtherText[key] ?? '';

  void toggleQuestionOption(String key, String option) {
    final question = _questionFor(key);
    if (question == null || !question.options.contains(option)) return;
    final selected = _selectedQuestionOptions.putIfAbsent(
      key,
      () => <String>{},
    );
    if (question.multiple) {
      if (!selected.remove(option)) selected.add(option);
    } else {
      selected
        ..clear()
        ..add(option);
      _questionOtherSelected.remove(key);
      _questionOtherText.remove(key);
    }
    _syncQuestionAnswer(question);
  }

  void toggleQuestionOther(String key) {
    final question = _questionFor(key);
    if (question == null) return;
    if (!_questionOtherSelected.remove(key)) {
      _questionOtherSelected.add(key);
      if (!question.multiple) {
        _selectedQuestionOptions[key]?.clear();
      }
    } else {
      _questionOtherText.remove(key);
    }
    _syncQuestionAnswer(question);
  }

  void setQuestionOtherText(String key, String value) {
    final question = _questionFor(key);
    if (question == null || !_questionOtherSelected.contains(key)) return;
    _questionOtherText[key] = value;
    _syncQuestionAnswer(question);
  }

  void setDisplayName(String value) {
    if (_displayName == value) return;
    _displayName = value;
    _errorMessage = null;
    _notify();
  }

  void setIcon(String value) {
    if (_icon == value) return;
    _icon = value;
    _notify();
  }

  Future<bool> generate() async {
    final description = _description.trim();
    if (description.isEmpty) {
      _errorMessage = '先描述一下你想记录什么';
      _notify();
      return false;
    }
    for (final question in _questions) {
      if (_isQuestionComplete(question)) continue;
      if (_questionOtherSelected.contains(question.key) &&
          otherTextFor(question.key).trim().isEmpty) {
        _errorMessage = '请填写“其他”内容';
      } else {
        _errorMessage = question.multiple ? '请至少选择一项想记录的内容' : '请先选择记录范围';
      }
      _notify();
      return false;
    }
    final revision = ++_generationRevision;
    _busy = true;
    _errorMessage = null;
    _notify();
    final body = <String, dynamic>{'description': description};
    if (_questions.isNotEmpty) {
      body['answers'] = [
        for (final question in _questions)
          {'key': question.key, 'value': answerFor(question.key).trim()},
      ];
    }
    try {
      final response = await repository.draft(body);
      if (!_isCurrent(revision)) return false;
      final rawDraft = response['draft'];
      if (rawDraft is Map) {
        _initializeDraft(rawDraft.cast<String, dynamic>());
        _stage = SkillWizardStage.fields;
        _busy = false;
        _notify();
        return true;
      }
      final rawQuestions = response['questions'];
      if (rawQuestions is List && rawQuestions.whereType<Map>().isNotEmpty) {
        _questions = List.unmodifiable(
          rawQuestions.whereType<Map>().map(
            (question) =>
                SkillWizardQuestion.fromJson(question.cast<String, dynamic>()),
          ),
        );
        _answers.removeWhere(
          (key, _) => !_questions.any((question) => question.key == key),
        );
        _selectedQuestionOptions.removeWhere(
          (key, _) => !_questions.any((question) => question.key == key),
        );
        _questionOtherSelected.removeWhere(
          (key) => !_questions.any((question) => question.key == key),
        );
        _questionOtherText.removeWhere(
          (key, _) => !_questions.any((question) => question.key == key),
        );
        _stage = SkillWizardStage.describe;
        _busy = false;
        _notify();
        return true;
      }
      _busy = false;
      _errorMessage = '设计失败，换个描述再试';
      _notify();
      return false;
    } catch (error) {
      if (!_isCurrent(revision)) return false;
      _busy = false;
      _errorMessage = '请求失败：$error';
      _notify();
      return false;
    }
  }

  void backToDescribe() {
    _generationRevision++;
    _busy = false;
    _stage = SkillWizardStage.describe;
    _errorMessage = null;
    _notify();
  }

  void goBack() {
    switch (_stage) {
      case SkillWizardStage.describe:
        return;
      case SkillWizardStage.fields:
        backToDescribe();
      case SkillWizardStage.card:
        _stage = SkillWizardStage.fields;
        _errorMessage = null;
        _notify();
    }
  }

  void updateField(
    String id, {
    String? key,
    String? label,
    String? type,
    String? meaning,
    bool? required,
    bool? long,
  }) {
    final index = _fieldIndex(id);
    if (index < 0) return;
    final previous = _fields[index];
    final next = previous.copyWith(
      key: key?.trim(),
      label: label,
      type: type,
      meaning: meaning,
      required: required,
      long: long ?? (type != null && type != 'string' ? false : null),
    );
    _fields[index] = next;
    final generatedSample = _generatedSampleKeys.remove(previous.key);
    if (next.key != previous.key) {
      if (_samplePayload.containsKey(previous.key)) {
        final value = _samplePayload.remove(previous.key);
        _samplePayload[next.key] = value;
      }
    }
    if (generatedSample) {
      _generatedSampleKeys.add(next.key);
      _samplePayload[next.key] = _previewValue(next);
    }
    if (next.key != previous.key ||
        next.label != previous.label ||
        next.type != previous.type) {
      _rebuildSelection(
        rename: next.key == previous.key ? const {} : {previous.key: next.key},
      );
    }
    _errorMessage = null;
    _notify();
  }

  SkillDraftField addField({
    String? key,
    String label = '新字段',
    String type = 'string',
    String meaning = '',
    bool required = false,
    bool long = false,
  }) {
    final revision = ++_newFieldRevision;
    final normalizedKey = key?.trim().isNotEmpty == true
        ? key!.trim()
        : 'field_$revision';
    final field = SkillDraftField(
      id: 'new-$revision',
      key: normalizedKey,
      label: label,
      type: type,
      meaning: meaning,
      required: required,
      long: long,
    );
    _fields.add(field);
    _samplePayload[field.key] = _previewValue(field);
    _generatedSampleKeys.add(field.key);
    _rebuildSelection(fillSecondary: true);
    _errorMessage = null;
    _notify();
    return field;
  }

  void removeField(String id) {
    final index = _fieldIndex(id);
    if (index < 0) return;
    final removed = _fields.removeAt(index);
    _samplePayload.remove(removed.key);
    _generatedSampleKeys.remove(removed.key);
    _rebuildSelection(fillSecondary: true);
    _errorMessage = null;
    _notify();
  }

  void moveField(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _fields.length ||
        newIndex < 0 ||
        newIndex >= _fields.length ||
        oldIndex == newIndex) {
      return;
    }
    final field = _fields.removeAt(oldIndex);
    _fields.insert(newIndex, field);
    _notify();
  }

  bool goToCard() {
    if (_stage != SkillWizardStage.fields || !_validateFields()) return false;
    _stage = SkillWizardStage.card;
    _errorMessage = null;
    _notify();
    return true;
  }

  SkillFieldSlot slotOf(String key) {
    final selection = _cardSelection;
    if (selection == null) return SkillFieldSlot.hidden;
    if (selection.config.primaryFieldId == key) return SkillFieldSlot.primary;
    final index = selection.config.secondaryFieldIds.indexOf(key);
    if (index == 0) return SkillFieldSlot.secondary;
    if (index > 0) return SkillFieldSlot.info;
    return SkillFieldSlot.hidden;
  }

  void assignSlot(String key, SkillFieldSlot slot) {
    final selection = _cardSelection;
    if (selection == null) return;
    final selected = selection.config.secondaryFieldIds.contains(key);
    switch (slot) {
      case SkillFieldSlot.primary:
        selection.selectPrimary(key);
      case SkillFieldSlot.secondary:
      case SkillFieldSlot.info:
        if (!selected) selection.toggleSecondary(key);
      case SkillFieldSlot.hidden:
        if (selected) selection.toggleSecondary(key);
    }
  }

  Map<String, dynamic> composeRenderSpec() {
    final source = <String, dynamic>{
      ..._originalRenderSpec,
      'icon': _icon.trim().isEmpty ? '•' : _icon.trim(),
    };
    return _cardSelection?.config.applyToRenderSpec(source) ?? source;
  }

  Future<bool> confirm() async {
    final currentDraft = _draft;
    if (_stage != SkillWizardStage.card ||
        currentDraft == null ||
        _busy ||
        _completed ||
        !_validateFields()) {
      return false;
    }
    _busy = true;
    _errorMessage = null;
    _notify();
    try {
      await repository.confirm({
        'name': currentDraft['name'],
        'display_name': _displayName.trim().isEmpty
            ? currentDraft['display_name']
            : _displayName.trim(),
        'description': _skillDescription,
        'payload_schema': payloadSchema,
        if (_routingProfile.isNotEmpty) 'routing_profile': _routingProfile,
        'render_spec': composeRenderSpec(),
        if (_chatStarters.isNotEmpty) 'chat_starters': _chatStarters,
      });
      if (_disposed) return false;
      _busy = false;
      _completed = true;
      _notify();
      onCreated?.call();
      return true;
    } catch (error) {
      if (_disposed) return false;
      _busy = false;
      _errorMessage = '创建失败：$error';
      _notify();
      return false;
    }
  }

  bool _validateFields() {
    if (_fields.isEmpty) {
      _errorMessage = '至少需要一个字段';
      _notify();
      return false;
    }
    final keys = <String>{};
    for (final field in _fields) {
      if (field.key.trim().isEmpty || field.label.trim().isEmpty) {
        _errorMessage = '字段名称和 key 不能为空';
        _notify();
        return false;
      }
      if (!keys.add(field.key.trim())) {
        _errorMessage = '字段 key 不能重复';
        _notify();
        return false;
      }
      if (field.type.trim().isEmpty) {
        _errorMessage = '字段类型不能为空';
        _notify();
        return false;
      }
    }
    return true;
  }

  int _fieldIndex(String id) =>
      _fields.indexWhere((field) => field.id == id || field.key == id);

  void _initializeDraft(Map<String, dynamic> draft) {
    _draft = Map<String, dynamic>.from(draft);
    final schema =
        (draft['payload_schema'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    _originalRenderSpec =
        (draft['render_spec'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    _samplePayload = {};
    _generatedSampleKeys.clear();
    _chatStarters = List<dynamic>.from(
      draft['chat_starters'] as List? ?? const [],
    );
    _skillDescription =
        draft['description']?.toString().trim() ?? _description.trim();
    _routingProfile = Map<String, dynamic>.from(
      (draft['routing_profile'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    _displayName =
        draft['display_name']?.toString() ?? draft['name']?.toString() ?? '新技能';
    _icon = _originalRenderSpec['icon']?.toString() ?? '•';
    _hiddenSchema.clear();
    _fields.clear();
    for (final entry in schema.entries) {
      final metadata = entry.value is Map
          ? (entry.value as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      if (metadata['type']?.toString() == 'uuid') {
        _hiddenSchema[entry.key] = Map<String, dynamic>.from(metadata);
        continue;
      }
      final label = metadata['label']?.toString().trim() ?? '';
      _fields.add(
        SkillDraftField(
          id: entry.key,
          key: entry.key,
          label: label.isEmpty ? entry.key : label,
          type: metadata['type']?.toString() ?? 'string',
          meaning:
              metadata['description']?.toString() ??
              metadata['meaning']?.toString() ??
              '',
          required: metadata['required'] == true,
          long: metadata['long'] == true,
          metadata: Map.unmodifiable(metadata),
        ),
      );
    }
    for (final field in _fields) {
      _samplePayload[field.key] = _previewValue(field);
      _generatedSampleKeys.add(field.key);
    }
    _replaceSelection(_initialDisplayConfig());
    _questions = const [];
    _answers.clear();
    _selectedQuestionOptions.clear();
    _questionOtherSelected.clear();
    _questionOtherText.clear();
    _completed = false;
  }

  CardDisplayConfig _initialDisplayConfig() {
    if (_fields.isEmpty) {
      return CardDisplayConfig(primaryFieldId: 'title');
    }
    try {
      return _fillSecondaryFields(
        CardDisplayConfig.fromRenderSpec(_originalRenderSpec),
      );
    } on FormatException {
      return _fillSecondaryFields(
        CardDisplayConfig(primaryFieldId: _fields.first.key),
      );
    }
  }

  CardDisplayConfig _fillSecondaryFields(CardDisplayConfig source) {
    if (_fields.isEmpty) return source;
    final available = _fields.map((field) => field.key).toSet();
    final primary = available.contains(source.primaryFieldId)
        ? source.primaryFieldId
        : _fields.first.key;
    final secondary = <String>[
      for (final key in source.secondaryFieldIds)
        if (available.contains(key) && key != primary) key,
    ];
    for (final field in _fields) {
      if (secondary.length == 3) break;
      if (field.key != primary && !secondary.contains(field.key)) {
        secondary.add(field.key);
      }
    }
    return CardDisplayConfig(
      primaryFieldId: primary,
      secondaryFieldIds: secondary,
    );
  }

  void _rebuildSelection({
    Map<String, String> rename = const {},
    bool fillSecondary = false,
  }) {
    if (_fields.isEmpty) {
      _cardSelection?.removeListener(_selectionChanged);
      _cardSelection?.dispose();
      _cardSelection = null;
      return;
    }
    final previous = _cardSelection?.config ?? _initialDisplayConfig();
    final available = _fields.map((field) => field.key).toSet();
    String mapped(String value) => rename[value] ?? value;
    final mappedPrimary = mapped(previous.primaryFieldId);
    final primary = available.contains(mappedPrimary)
        ? mappedPrimary
        : _fields.first.key;
    final rebuilt = CardDisplayConfig(
      primaryFieldId: primary,
      secondaryFieldIds: previous.secondaryFieldIds
          .map(mapped)
          .where(available.contains),
    );
    _replaceSelection(fillSecondary ? _fillSecondaryFields(rebuilt) : rebuilt);
  }

  dynamic _previewValue(SkillDraftField field) {
    final label = field.label.trim();
    return label.isEmpty ? '字段' : label;
  }

  SkillWizardQuestion? _questionFor(String key) {
    for (final question in _questions) {
      if (question.key == key) return question;
    }
    return null;
  }

  void _syncQuestionAnswer(SkillWizardQuestion question) {
    final selected = _selectedQuestionOptions[question.key] ?? const <String>{};
    final values = <String>[
      for (final option in question.options)
        if (selected.contains(option)) option,
    ];
    if (_questionOtherSelected.contains(question.key)) {
      final custom = otherTextFor(question.key).trim();
      if (custom.isNotEmpty) values.add(custom);
    }
    _answers[question.key] = values.join('、');
    _errorMessage = null;
    _notify();
  }

  bool _isQuestionComplete(SkillWizardQuestion question) {
    final hasSelection =
        (_selectedQuestionOptions[question.key] ?? const <String>{}).isNotEmpty;
    final hasOther = _questionOtherSelected.contains(question.key);
    if (hasOther && otherTextFor(question.key).trim().isEmpty) return false;
    if (hasSelection || hasOther) return true;
    return answerFor(question.key).trim().isNotEmpty;
  }

  void _replaceSelection(CardDisplayConfig config) {
    _cardSelection?.removeListener(_selectionChanged);
    _cardSelection?.dispose();
    if (_fields.isEmpty) {
      _cardSelection = null;
      return;
    }
    _cardSelection = CardFieldSelectionController(
      fields: [
        for (final field in _fields)
          CardSelectableField(
            id: field.key,
            label: field.label,
            type: field.type,
          ),
      ],
      config: config,
    )..addListener(_selectionChanged);
  }

  void _selectionChanged() {
    if (_disposed) return;
    _errorMessage = _cardSelection?.errorMessage;
    _notify();
  }

  bool _isCurrent(int revision) =>
      !_disposed && revision == _generationRevision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generationRevision++;
    _cardSelection?.removeListener(_selectionChanged);
    _cardSelection?.dispose();
    if (disposeRepository && repository is ApiSkillWizardRepository) {
      (repository as ApiSkillWizardRepository).dispose();
    }
    super.dispose();
  }
}
