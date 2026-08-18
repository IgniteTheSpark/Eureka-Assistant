import 'package:flutter/foundation.dart';

import '../../../api/api_client.dart';
import '../../asset/asset_card_display.dart';
import '../../asset/card_field_selection.dart';
import '../../../render/render_spec.dart';
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
  Future<SkillDeletionImpactView> deletionImpact(String userSkillId);
  Future<SkillDeletionResultView> delete(
    String userSkillId,
    String confirmationToken,
  );
}

@immutable
class SkillDeletionImpactView {
  const SkillDeletionImpactView({
    required this.assetCount,
    required this.confirmationToken,
  });

  final int assetCount;
  final String confirmationToken;
}

@immutable
class SkillDeletionResultView {
  const SkillDeletionResultView({required this.deletedAssetCount});

  final int deletedAssetCount;
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
  Future<SkillDeletionImpactView> deletionImpact(String userSkillId) async {
    final response = await _api.getJson(
      '/api/user-skills/$userSkillId/deletion-impact',
    );
    final row = (response as Map).cast<String, dynamic>();
    final token =
        row['confirmation_token']?.toString() ??
        row['revision']?.toString() ??
        '';
    if (token.isEmpty) throw const FormatException('删除影响缺少确认令牌');
    return SkillDeletionImpactView(
      assetCount: int.tryParse(row['asset_count']?.toString() ?? '') ?? 0,
      confirmationToken: token,
    );
  }

  @override
  Future<SkillDeletionResultView> delete(
    String userSkillId,
    String confirmationToken,
  ) async {
    final response = await _api.deleteJson(
      '/api/user-skills/$userSkillId',
      query: {'confirmation_token': confirmationToken},
    );
    final row = (response as Map).cast<String, dynamic>();
    return SkillDeletionResultView(
      deletedAssetCount:
          int.tryParse(row['deleted_asset_count']?.toString() ?? '') ?? 0,
    );
  }

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
  CardFieldSelectionController? _cardSelection;
  String? _errorMessage;
  int? _deletionAssetCount;
  String? _deletionConfirmationToken;
  bool _disposed = false;

  SkillManagementState get state => _state;
  ConfigurableSkill? get skill => _skill;
  String get displayName => _displayName;
  String get description => _description;
  List<SkillManagementField> get fields => List.unmodifiable(_fields);
  CardFieldSelectionController? get cardSelection => _cardSelection;
  AssetCardViewData? get preview {
    final current = _skill;
    final selection = _cardSelection;
    if (current == null || selection == null) return null;
    final schema = {
      for (final field in _fields)
        field.key: {
          ...field.metadata,
          'type': field.type,
          'label': field.label,
          if (field.meaning.isNotEmpty) 'description': field.meaning,
          if (field.hidden) 'x-hidden': true,
        },
    };
    final spec = RenderSpec.fromJson(
      selection.config.applyToRenderSpec(current.renderSpec),
    ).withSchema(schema);
    return AssetCardViewData.fromPayload(
      payload: _draftSamplePayload(current),
      display: selection.config,
      spec: spec,
      skillLabel: _displayName,
    );
  }

  Map<String, dynamic> _draftSamplePayload(ConfigurableSkill skill) => {
    for (final field in _fields) field.key: _draftSampleValue(skill, field),
  };

  dynamic _draftSampleValue(
    ConfigurableSkill skill,
    SkillManagementField field,
  ) {
    final originalLabel =
        skill.payloadSchema[field.key]?['label']?.toString().trim() ??
        field.key;
    final sample = skill.samplePayload[field.key];
    if (field.original && field.label == originalLabel && sample != null) {
      return sample;
    }
    return field.label;
  }

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

  bool addField({
    required String key,
    required String label,
    required String type,
    String meaning = '',
  }) {
    final normalizedKey = key.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalizedKey)) {
      _errorMessage = '字段 ID 必须使用 snake_case';
      _notify();
      return false;
    }
    const supportedTypes = {'string', 'number', 'integer', 'boolean', 'array'};
    if (!supportedTypes.contains(type)) {
      _errorMessage = '暂不支持该字段类型';
      _notify();
      return false;
    }
    if (_fields.any((field) => field.key == normalizedKey)) {
      _errorMessage = '字段 ID 已存在';
      _notify();
      return false;
    }
    _errorMessage = null;
    _fields = [
      ..._fields,
      SkillManagementField(
        key: normalizedKey,
        label: label.trim().isEmpty ? normalizedKey : label.trim(),
        type: type,
        original: false,
        meaning: meaning.trim(),
        metadata: type == 'array'
            ? const {
                'items': {'type': 'string'},
              }
            : const <String, dynamic>{},
      ),
    ];
    _replaceCardSelection(_skill!);
    _notify();
    return true;
  }

  void reorderField(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _fields.length) return;
    final next = [..._fields];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    _fields = next;
    _replaceCardSelection(_skill!);
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
          renderSpec:
              _cardSelection?.config.applyToRenderSpec(current.renderSpec) ??
              current.renderSpec,
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
      final impact = await repository.deletionImpact(userSkillId);
      _deletionAssetCount = impact.assetCount;
      _deletionConfirmationToken = impact.confirmationToken;
      _errorMessage = null;
      if (_state == SkillManagementState.error) {
        _state = SkillManagementState.ready;
      }
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
    final token = _deletionConfirmationToken;
    if (token == null || token.isEmpty) return null;
    _setState(SkillManagementState.deleting);
    try {
      final result = await repository.delete(userSkillId, token);
      return result.deletedAssetCount;
    } catch (error) {
      if (error is ApiException &&
          error.statusCode == 409 &&
          error.body.contains('stale_delete_confirmation')) {
        _deletionAssetCount = null;
        _deletionConfirmationToken = null;
        _fail('删除影响已变化，请重新确认');
        return null;
      }
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
    _replaceCardSelection(_skill!);
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
    _replaceCardSelection(skill);
  }

  void _replaceCardSelection(ConfigurableSkill skill) {
    final fields = [
      for (final field in _fields)
        if (!field.hidden && field.type != 'uuid')
          CardSelectableField(
            id: field.key,
            label: field.label,
            type: field.type,
          ),
    ];
    final previous = _cardSelection?.config;
    final oldSelection = _cardSelection;
    if (oldSelection != null) {
      oldSelection.removeListener(_selectionChanged);
      oldSelection.dispose();
    }
    if (fields.isEmpty) {
      _cardSelection = null;
      return;
    }
    CardDisplayConfig initialConfig;
    try {
      initialConfig =
          previous ?? CardDisplayConfig.fromRenderSpec(skill.renderSpec);
    } on FormatException {
      initialConfig = CardDisplayConfig(primaryFieldId: fields.first.id);
    }
    _cardSelection = CardFieldSelectionController(
      fields: fields,
      config: initialConfig,
    )..addListener(_selectionChanged);
  }

  void _selectionChanged() => _notify();

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
    _cardSelection?.removeListener(_selectionChanged);
    _cardSelection?.dispose();
    if (disposeRepository && repository is ApiSkillManagementRepository) {
      (repository as ApiSkillManagementRepository).dispose();
    }
    super.dispose();
  }
}
