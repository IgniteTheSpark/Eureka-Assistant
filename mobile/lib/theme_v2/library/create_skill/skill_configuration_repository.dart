import 'package:flutter/foundation.dart';

import '../../../api/api_client.dart';
import '../../asset/asset_card_display.dart';
import '../../asset/card_field_selection.dart';

@immutable
class ConfigurableSkill {
  const ConfigurableSkill({
    required this.userSkillId,
    required this.name,
    required this.displayName,
    required this.payloadSchema,
    required this.renderSpec,
    required this.samplePayload,
  });

  factory ConfigurableSkill.fromJson(Map<String, dynamic> json) {
    final name =
        json['name']?.toString() ?? json['machine_name']?.toString() ?? '';
    final schema = _payloadSchema(json, name);
    return ConfigurableSkill(
      userSkillId:
          json['user_skill_id']?.toString() ?? json['id']?.toString() ?? '',
      name: name,
      displayName:
          json['display_name']?.toString() ??
          json['name']?.toString() ??
          'Skill',
      payloadSchema: Map.unmodifiable(schema),
      renderSpec: Map.unmodifiable(
        (json['render_spec'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      samplePayload: Map.unmodifiable(_samplePayload(schema)),
    );
  }

  final String userSkillId;
  final String name;
  final String displayName;
  final Map<String, dynamic> payloadSchema;
  final Map<String, dynamic> renderSpec;
  final Map<String, dynamic> samplePayload;

  static Map<String, dynamic> _samplePayload(Map<String, dynamic> schema) {
    return {
      for (final entry in schema.entries)
        if ((entry.value as Map?)?['type']?.toString() != 'uuid')
          entry.key: _sampleValue(
            entry.key,
            (entry.value as Map?)?.cast<String, dynamic>() ?? const {},
          ),
    };
  }

  static Map<String, dynamic> _payloadSchema(
    Map<String, dynamic> json,
    String machineName,
  ) {
    final legacy = (json['payload_schema'] as Map?)?.cast<String, dynamic>();
    if (legacy != null) {
      return {
        for (final entry in legacy.entries)
          entry.key: _localizedFieldMetadata(
            machineName,
            entry.key,
            entry.value,
          ),
      };
    }
    final root = (json['schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    final properties =
        (root['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final required = (root['required'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    return {
      for (final entry in properties.entries)
        entry.key: _fieldMetadata(
          machineName,
          entry.key,
          entry.value,
          required,
        ),
    };
  }

  static Map<String, dynamic> _fieldMetadata(
    String machineName,
    String key,
    dynamic raw,
    Set<String> required,
  ) {
    final metadata = (raw as Map?)?.cast<String, dynamic>() ?? const {};
    final format = metadata['format']?.toString();
    return {
      ...metadata,
      'type': switch (format) {
        'date' => 'date',
        'date-time' => 'datetime',
        'uuid' => 'uuid',
        _ => metadata['type']?.toString() ?? 'string',
      },
      'label': _fieldLabel(machineName, key, metadata),
      'required': required.contains(key),
      'long': metadata['x-long'] == true,
    };
  }

  static Map<String, dynamic> _localizedFieldMetadata(
    String machineName,
    String key,
    dynamic raw,
  ) {
    final metadata = (raw as Map?)?.cast<String, dynamic>() ?? const {};
    return {...metadata, 'label': _fieldLabel(machineName, key, metadata)};
  }

  static String _fieldLabel(
    String machineName,
    String key,
    Map<String, dynamic> metadata,
  ) {
    for (final candidate in [
      metadata['label'],
      metadata['title'],
      _builtInFieldLabels[machineName]?[key],
    ]) {
      final label = candidate?.toString().trim() ?? '';
      if (label.isNotEmpty && label != key) return label;
    }
    return key;
  }

  static dynamic _sampleValue(String key, Map<String, dynamic> metadata) {
    final label = metadata['label']?.toString().trim();
    final value = label == null || label.isEmpty ? key : label;
    return metadata['type']?.toString() == 'array' ? [value] : value;
  }
}

const _builtInFieldLabels = <String, Map<String, String>>{
  'notes': {'title': '标题', 'content': '内容', 'domain': '领域'},
  'todo': {
    'title': '标题',
    'content': '内容',
    'due_date': '截止时间',
    'period': '时段',
    'occurred_at': '发生时间',
    'status': '完成状态',
    'domain': '领域',
  },
  'contact': {
    'name': '姓名',
    'phone': '电话',
    'company': '公司',
    'title': '职位',
    'email': '邮箱',
    'notes': '备注',
    'domain': '领域',
  },
  'event': {
    'title': '标题',
    'start_at': '开始时间',
    'end_at': '结束时间',
    'location': '地点',
    'attendees': '参与人',
    'description': '备注',
  },
};

abstract interface class SkillConfigurationRepository {
  Future<ConfigurableSkill> load(String userSkillId);

  Future<void> saveCardDisplay(
    String userSkillId,
    CardDisplayConfig config,
    Map<String, dynamic> originalRenderSpec,
  );
}

class ApiSkillConfigurationRepository implements SkillConfigurationRepository {
  ApiSkillConfigurationRepository([ApiClient? api])
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<ConfigurableSkill> load(String userSkillId) async {
    final response = await _api.getJson('/api/user-skills');
    final rows = response is List
        ? response
        : ((response is Map ? response['skills'] : null) as List? ?? []);
    for (final raw in rows.whereType<Map>()) {
      final row = raw.cast<String, dynamic>();
      final id =
          row['user_skill_id']?.toString() ?? row['id']?.toString() ?? '';
      if (id == userSkillId) return ConfigurableSkill.fromJson(row);
    }
    throw StateError('找不到这个 Skill');
  }

  @override
  Future<void> saveCardDisplay(
    String userSkillId,
    CardDisplayConfig config,
    Map<String, dynamic> originalRenderSpec,
  ) async {
    await _api.patchJson('/api/user-skills/$userSkillId', {
      'render_spec': config.applyToRenderSpec(originalRenderSpec),
    });
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

enum SkillConfigurationState { idle, loading, ready, error, saving, saved }

class SkillCardConfigurationController extends ChangeNotifier {
  SkillCardConfigurationController({
    required this.repository,
    required this.userSkillId,
    this.disposeRepository = false,
  });

  final SkillConfigurationRepository repository;
  final String userSkillId;
  final bool disposeRepository;

  SkillConfigurationState _state = SkillConfigurationState.idle;
  ConfigurableSkill? _skill;
  CardFieldSelectionController? _selection;
  String? _errorMessage;
  bool _disposed = false;

  SkillConfigurationState get state => _state;
  ConfigurableSkill? get skill => _skill;
  CardFieldSelectionController? get selection => _selection;
  String? get errorMessage => _errorMessage;
  bool get busy =>
      _state == SkillConfigurationState.loading ||
      _state == SkillConfigurationState.saving;

  Future<void> load() async {
    if (_state != SkillConfigurationState.idle &&
        _state != SkillConfigurationState.error) {
      return;
    }
    _state = SkillConfigurationState.loading;
    _errorMessage = null;
    _notify();
    try {
      final skill = await repository.load(userSkillId);
      if (_disposed) return;
      _skill = skill;
      _replaceSelection(skill);
      _state = SkillConfigurationState.ready;
    } catch (error) {
      if (_disposed) return;
      _state = SkillConfigurationState.error;
      _errorMessage = '展示设置加载失败：$error';
    }
    _notify();
  }

  Future<bool> save() async {
    final skill = _skill;
    final selection = _selection;
    if (skill == null ||
        selection == null ||
        _state == SkillConfigurationState.saving) {
      return false;
    }
    _state = SkillConfigurationState.saving;
    _errorMessage = null;
    _notify();
    try {
      await repository.saveCardDisplay(
        userSkillId,
        selection.config,
        skill.renderSpec,
      );
      if (_disposed) return false;
      _state = SkillConfigurationState.saved;
      _notify();
      return true;
    } catch (error) {
      if (_disposed) return false;
      _state = SkillConfigurationState.ready;
      _errorMessage = '展示设置保存失败：$error';
      _notify();
      return false;
    }
  }

  void _replaceSelection(ConfigurableSkill skill) {
    _selection?.removeListener(_selectionChanged);
    _selection?.dispose();
    final fields = <CardSelectableField>[];
    for (final entry in skill.payloadSchema.entries) {
      final metadata = entry.value is Map
          ? (entry.value as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      if (metadata['type']?.toString() == 'uuid') continue;
      fields.add(
        CardSelectableField(
          id: entry.key,
          label: metadata['label']?.toString() ?? entry.key,
          type: metadata['type']?.toString() ?? 'string',
        ),
      );
    }
    if (fields.isEmpty) throw StateError('这个 Skill 没有可展示字段');
    CardDisplayConfig config;
    try {
      config = CardDisplayConfig.fromRenderSpec(skill.renderSpec);
    } on FormatException {
      config = CardDisplayConfig(primaryFieldId: fields.first.id);
    }
    _selection = CardFieldSelectionController(fields: fields, config: config)
      ..addListener(_selectionChanged);
  }

  void _selectionChanged() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _selection?.removeListener(_selectionChanged);
    _selection?.dispose();
    if (disposeRepository && repository is ApiSkillConfigurationRepository) {
      (repository as ApiSkillConfigurationRepository).dispose();
    }
    super.dispose();
  }
}
