import 'package:flutter/foundation.dart';

import '../../../api/api_client.dart';
import 'skill_configuration_repository.dart';

@immutable
class SkillManagementField {
  const SkillManagementField({
    required this.key,
    required this.label,
    required this.type,
    required this.original,
    this.meaning = '',
    this.hidden = false,
    this.metadata = const <String, dynamic>{},
  });

  final String key;
  final String label;
  final String type;
  final String meaning;
  final bool original;
  final bool hidden;
  final Map<String, dynamic> metadata;

  SkillManagementField copyWith({
    String? label,
    String? meaning,
    bool? hidden,
  }) => SkillManagementField(
    key: key,
    label: label ?? this.label,
    type: type,
    original: original,
    meaning: meaning ?? this.meaning,
    hidden: hidden ?? this.hidden,
    metadata: metadata,
  );
}

@immutable
class SkillManagementDraft {
  const SkillManagementDraft({
    required this.displayName,
    required this.description,
    required this.schema,
    required this.renderSpec,
    required this.expectedUpdatedAt,
  });

  final String displayName;
  final String description;
  final Map<String, dynamic> schema;
  final Map<String, dynamic> renderSpec;
  final DateTime? expectedUpdatedAt;

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'description': description,
    'schema': schema,
    'render_spec': renderSpec,
    if (expectedUpdatedAt != null)
      'expected_updated_at': expectedUpdatedAt!.toUtc().toIso8601String(),
  };
}

abstract interface class SkillManagementRepository {
  Future<ConfigurableSkill> load(String userSkillId);
  Future<ConfigurableSkill> save(
    String userSkillId,
    SkillManagementDraft draft,
  );
  Future<int> deletionImpact(String userSkillId);
  Future<void> delete(String userSkillId);
}

class ApiSkillManagementRepository implements SkillManagementRepository {
  ApiSkillManagementRepository([ApiClient? api])
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<ConfigurableSkill> load(String userSkillId) async {
    final response = await _api.getJson('/api/user-skills/$userSkillId');
    return ConfigurableSkill.fromJson(
      (response as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<ConfigurableSkill> save(
    String userSkillId,
    SkillManagementDraft draft,
  ) async {
    final response = await _api.patchJson(
      '/api/user-skills/$userSkillId',
      draft.toJson(),
    );
    return ConfigurableSkill.fromJson(
      (response as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<int> deletionImpact(String userSkillId) async {
    final response = await _api.getJson(
      '/api/user-skills/$userSkillId/deletion-impact',
    );
    return int.tryParse((response as Map)['asset_count']?.toString() ?? '') ??
        0;
  }

  @override
  Future<void> delete(String userSkillId) =>
      _api.deleteJson('/api/user-skills/$userSkillId');

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

enum SkillManagementState { idle, loading, ready, saving, deleting, error }

class SkillManagementController extends ChangeNotifier {
  SkillManagementController({
    required this.repository,
    required this.userSkillId,
    this.disposeRepository = false,
  });

  final SkillManagementRepository repository;
  final String userSkillId;
  final bool disposeRepository;

  SkillManagementState _state = SkillManagementState.idle;
  ConfigurableSkill? _skill;
  String _displayName = '';
  String _description = '';
  List<SkillManagementField> _fields = const [];
  String? _errorMessage;
  int? _deletionAssetCount;
  bool _disposed = false;

  SkillManagementState get state => _state;
  ConfigurableSkill? get skill => _skill;
  String get displayName => _displayName;
  String get description => _description;
  List<SkillManagementField> get fields => List.unmodifiable(_fields);
  String? get errorMessage => _errorMessage;
  int? get deletionAssetCount => _deletionAssetCount;
  bool get busy =>
      _state == SkillManagementState.loading ||
      _state == SkillManagementState.saving ||
      _state == SkillManagementState.deleting;

  Future<void> load() async {
    if (_state == SkillManagementState.loading) return;
    _setState(SkillManagementState.loading);
    try {
      final loaded = await repository.load(userSkillId);
      if (_disposed) return;
      _applySkill(loaded);
      _setState(SkillManagementState.ready);
    } catch (error) {
      _fail('Skill 加载失败：$error');
    }
  }

  void setDisplayName(String value) {
    _displayName = value;
    _notify();
  }

  void setDescription(String value) {
    _description = value;
    _notify();
  }

  bool updateExistingKey(String key, String replacement) => false;

  bool updateExistingType(String key, String replacement) => false;

  bool updateFieldLabel(String key, String label) =>
      _replaceField(key, (field) => field.copyWith(label: label));

  bool updateFieldMeaning(String key, String meaning) =>
      _replaceField(key, (field) => field.copyWith(meaning: meaning));

  bool setFieldHidden(String key, bool hidden) {
    final visibleCount = _fields.where((field) => !field.hidden).length;
    if (hidden && visibleCount <= 1) return false;
    return _replaceField(key, (field) => field.copyWith(hidden: hidden));
  }

  void addField({
    required String key,
    required String label,
    required String type,
    String meaning = '',
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty ||
        _fields.any((field) => field.key == normalizedKey)) {
      return;
    }
    _fields = [
      ..._fields,
      SkillManagementField(
        key: normalizedKey,
        label: label.trim().isEmpty ? normalizedKey : label.trim(),
        type: type,
        original: false,
        meaning: meaning.trim(),
      ),
    ];
    _notify();
  }

  void reorderField(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _fields.length) return;
    final next = [..._fields];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    _fields = next;
    _notify();
  }

  Future<bool> save() async {
    final current = _skill;
    if (current == null || _displayName.trim().isEmpty || busy) return false;
    _setState(SkillManagementState.saving);
    try {
      final saved = await repository.save(
        userSkillId,
        SkillManagementDraft(
          displayName: _displayName.trim(),
          description: _description.trim(),
          schema: _serializeSchema(current.rootSchema),
          renderSpec: current.renderSpec,
          expectedUpdatedAt: current.updatedAt,
        ),
      );
      if (_disposed) return false;
      _applySkill(saved);
      _setState(SkillManagementState.ready);
      return true;
    } catch (error) {
      _fail('保存失败：$error');
      return false;
    }
  }

  Future<int?> loadDeletionImpact() async {
    try {
      _deletionAssetCount = await repository.deletionImpact(userSkillId);
      _notify();
      return _deletionAssetCount;
    } catch (error) {
      _fail('无法确认受影响的记录：$error');
      return null;
    }
  }

  Future<int?> deleteSkill() async {
    if (busy) return null;
    final count = _deletionAssetCount ?? await loadDeletionImpact();
    if (count == null) return null;
    _setState(SkillManagementState.deleting);
    try {
      await repository.delete(userSkillId);
      return count;
    } catch (error) {
      _fail('删除失败：$error');
      return null;
    }
  }

  bool _replaceField(
    String key,
    SkillManagementField Function(SkillManagementField) transform,
  ) {
    final index = _fields.indexWhere((field) => field.key == key);
    if (index < 0) return false;
    final next = [..._fields];
    next[index] = transform(next[index]);
    _fields = next;
    _notify();
    return true;
  }

  Map<String, dynamic> _serializeSchema(Map<String, dynamic> originalRoot) {
    return {
      ...originalRoot,
      'type': 'object',
      'properties': {
        for (final field in _fields)
          field.key: {
            ...field.metadata,
            'type': field.type,
            'title': field.label,
            if (field.meaning.isNotEmpty) 'description': field.meaning,
            if (field.hidden) 'x-hidden': true else 'x-hidden': false,
          },
      },
      'required': <String>[],
      'additionalProperties': false,
    };
  }

  void _applySkill(ConfigurableSkill skill) {
    _skill = skill;
    _displayName = skill.displayName;
    _description = skill.description;
    final properties =
        (skill.rootSchema['properties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    _fields = [
      for (final entry in skill.payloadSchema.entries)
        if (entry.value['type']?.toString() != 'uuid')
          SkillManagementField(
            key: entry.key,
            label: entry.value['label']?.toString() ?? entry.key,
            type:
                (properties[entry.key] as Map?)?['type']?.toString() ??
                entry.value['type']?.toString() ??
                'string',
            original: true,
            meaning:
                (properties[entry.key] as Map?)?['description']?.toString() ??
                '',
            hidden: (properties[entry.key] as Map?)?['x-hidden'] == true,
            metadata:
                (properties[entry.key] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
          ),
    ];
  }

  void _setState(SkillManagementState value) {
    _state = value;
    _errorMessage = null;
    _notify();
  }

  void _fail(String message) {
    if (_disposed) return;
    _state = SkillManagementState.error;
    _errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (disposeRepository && repository is ApiSkillManagementRepository) {
      (repository as ApiSkillManagementRepository).dispose();
    }
    super.dispose();
  }
}
