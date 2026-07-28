import 'package:flutter/foundation.dart';

import '../../../api/api_client.dart';

enum SkillWizardStage { describe, questions, preview, complete }

enum SkillFieldSlot { primary, secondary, info, hidden }

@immutable
class SkillWizardQuestion {
  const SkillWizardQuestion({
    required this.key,
    required this.prompt,
    required this.type,
    required this.options,
    required this.placeholder,
  });

  factory SkillWizardQuestion.fromJson(Map<String, dynamic> json) {
    return SkillWizardQuestion(
      key: json['key']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      options: List.unmodifiable(
        (json['options'] as List? ?? const []).map((item) => item.toString()),
      ),
      placeholder: json['placeholder']?.toString() ?? '可留空',
    );
  }

  final String key;
  final String prompt;
  final String type;
  final List<String> options;
  final String placeholder;
}

@immutable
class SkillPreviewField {
  const SkillPreviewField({
    required this.key,
    required this.label,
    required this.type,
  });

  final String key;
  final String label;
  final String type;
}

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
    final response = await _api.postJson('/api/skills', body);
    if (response is! Map) {
      throw const FormatException('技能设计服务返回格式错误');
    }
    return response.cast<String, dynamic>();
  }

  @override
  Future<void> confirm(Map<String, dynamic> body) async {
    await _api.postJson('/api/skills/confirm', body);
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
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
  String _description = '';
  String? _errorMessage;
  List<SkillWizardQuestion> _questions = const [];
  final Map<String, String> _answers = {};
  Map<String, dynamic>? _draft;
  List<SkillPreviewField> _fields = const [];
  String _displayName = '';
  String _icon = '•';
  String _layout = 'horizontal';
  String _accent = 'neutral';
  String? _primary;
  String? _secondary;
  final List<String> _info = [];
  final Map<String, String?> _formats = {};
  int _generationRevision = 0;
  bool _disposed = false;

  SkillWizardStage get stage => _stage;
  bool get busy => _busy;
  String get description => _description;
  String? get errorMessage => _errorMessage;
  List<SkillWizardQuestion> get questions => _questions;
  Map<String, String> get answers => Map.unmodifiable(_answers);
  List<SkillPreviewField> get fields => _fields;
  String get displayName => _displayName;
  String get icon => _icon;
  Map<String, dynamic>? get draft => _draft;

  void setDescription(String value) {
    if (_description == value) return;
    _description = value;
    _errorMessage = null;
    _notify();
  }

  void answer(String key, String value) {
    _answers[key] = value;
    _errorMessage = null;
    _notify();
  }

  String answerFor(String key) => _answers[key] ?? '';

  void setDisplayName(String value) {
    _displayName = value;
    _notify();
  }

  void setIcon(String value) {
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
    final revision = ++_generationRevision;
    _busy = true;
    _errorMessage = null;
    _notify();
    final body = <String, dynamic>{'description': description};
    if (_stage == SkillWizardStage.questions) {
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
        _initializePreview(rawDraft.cast<String, dynamic>());
        _stage = SkillWizardStage.preview;
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
        _stage = SkillWizardStage.questions;
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

  SkillFieldSlot slotOf(String key) {
    if (_primary == key) return SkillFieldSlot.primary;
    if (_secondary == key) return SkillFieldSlot.secondary;
    if (_info.contains(key)) return SkillFieldSlot.info;
    return SkillFieldSlot.hidden;
  }

  void assignSlot(String key, SkillFieldSlot slot) {
    if (!_fields.any((field) => field.key == key)) return;
    final current = slotOf(key);
    if (slot == SkillFieldSlot.info &&
        current != SkillFieldSlot.info &&
        _info.length >= 3) {
      _errorMessage = '信息字段最多选择 3 个';
      _notify();
      return;
    }
    if (_primary == key) _primary = null;
    if (_secondary == key) _secondary = null;
    _info.remove(key);
    switch (slot) {
      case SkillFieldSlot.primary:
        _primary = key;
      case SkillFieldSlot.secondary:
        _secondary = key;
      case SkillFieldSlot.info:
        _info.add(key);
      case SkillFieldSlot.hidden:
        break;
    }
    _errorMessage = null;
    _notify();
  }

  Map<String, dynamic> composeRenderSpec() {
    return {
      'card_layout': _layout,
      'icon': _icon.trim().isEmpty ? '•' : _icon.trim(),
      'accent_color': _accent,
      if (_primary != null) 'primary_field': _primary,
      if (_primary != null && _formats[_primary] != null)
        'primary_format': _formats[_primary],
      if (_secondary != null) 'secondary_field': _secondary,
      if (_secondary != null && _formats[_secondary] != null)
        'secondary_format': _formats[_secondary],
      'meta_fields': [
        for (final field in _info)
          {
            'field': field,
            if (_formats[field] != null) 'format': _formats[field],
          },
      ],
    };
  }

  Future<bool> confirm() async {
    final currentDraft = _draft;
    if (_stage != SkillWizardStage.preview || currentDraft == null || _busy) {
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
        'payload_schema': currentDraft['payload_schema'],
        'render_spec': composeRenderSpec(),
        if (currentDraft['chat_starters'] is List)
          'chat_starters': currentDraft['chat_starters'],
      });
      if (_disposed) return false;
      _busy = false;
      _stage = SkillWizardStage.complete;
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

  void _initializePreview(Map<String, dynamic> draft) {
    _draft = Map.unmodifiable(draft);
    final schema =
        (draft['payload_schema'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final renderSpec =
        (draft['render_spec'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    _displayName =
        draft['display_name']?.toString() ?? draft['name']?.toString() ?? '新技能';
    _icon = renderSpec['icon']?.toString() ?? '•';
    _layout = renderSpec['card_layout']?.toString() ?? 'horizontal';
    _accent = 'neutral';
    _primary = renderSpec['primary_field']?.toString();
    _secondary = renderSpec['secondary_field']?.toString();
    _info
      ..clear()
      ..addAll(
        (renderSpec['meta_fields'] as List? ?? const [])
            .whereType<Map>()
            .map((meta) => meta['field']?.toString() ?? '')
            .where((field) => field.isNotEmpty)
            .take(3),
      );
    _formats.clear();
    if (_primary case final key?) {
      _formats[key] = renderSpec['primary_format']?.toString();
    }
    if (_secondary case final key?) {
      _formats[key] = renderSpec['secondary_format']?.toString();
    }
    for (final meta
        in (renderSpec['meta_fields'] as List? ?? const []).whereType<Map>()) {
      final key = meta['field']?.toString();
      if (key != null && key.isNotEmpty) {
        _formats[key] = meta['format']?.toString();
      }
    }
    _fields = List.unmodifiable(
      schema.entries
          .where((entry) {
            final metadata = entry.value;
            return metadata is! Map || metadata['type']?.toString() != 'uuid';
          })
          .map((entry) {
            final metadata = entry.value is Map
                ? (entry.value as Map).cast<String, dynamic>()
                : const <String, dynamic>{};
            final label = metadata['label']?.toString().trim();
            return SkillPreviewField(
              key: entry.key,
              label: label == null || label.isEmpty ? entry.key : label,
              type: metadata['type']?.toString() ?? 'string',
            );
          }),
    );
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
    if (disposeRepository && repository is ApiSkillWizardRepository) {
      (repository as ApiSkillWizardRepository).dispose();
    }
    super.dispose();
  }
}
