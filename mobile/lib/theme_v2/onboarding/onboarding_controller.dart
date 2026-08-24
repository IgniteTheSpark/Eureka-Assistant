import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'onboarding_repository.dart';

const _fallbackCategories = <Map<String, dynamic>>[
  {
    'id': 'running',
    'label': '跑步',
    'description': '记录距离、时长与地点',
    'fields': [
      {'key': 'distance_km', 'label': '距离(公里)', 'type': 'number'},
      {'key': 'duration_min', 'label': '时长(分钟)', 'type': 'duration'},
      {'key': 'location', 'label': '地点', 'type': 'text'},
    ],
    'hint': '我今天沿着河边跑了 5 公里，用了 32 分钟。',
  },
  {
    'id': 'drinking_water',
    'label': '喝水',
    'description': '记录每天的饮水量与方式',
    'fields': [
      {'key': 'amount_ml', 'label': '水量(毫升)', 'type': 'number'},
      {'key': 'time', 'label': '时间', 'type': 'time'},
      {'key': 'container', 'label': '容器', 'type': 'text'},
    ],
    'hint': '下午我在办公室用保温杯喝了 500 毫升水。',
  },
  {
    'id': 'baby_feeding',
    'label': '宝宝喂养',
    'description': '记录宝宝每次喂养的方式与奶量',
    'fields': [
      {'key': 'method', 'label': '喂养方式', 'type': 'text'},
      {'key': 'amount_ml', 'label': '奶量(毫升)', 'type': 'number'},
      {'key': 'time', 'label': '时间', 'type': 'time'},
    ],
    'hint': '早上八点我用奶瓶喂了宝宝 120 毫升。',
  },
  {
    'id': 'dancing',
    'label': '跳舞',
    'description': '记录舞蹈练习的舞种与时长',
    'fields': [
      {'key': 'style', 'label': '舞种', 'type': 'text'},
      {'key': 'studio', 'label': '舞室', 'type': 'text'},
      {'key': 'duration_min', 'label': '时长(分钟)', 'type': 'duration'},
    ],
    'hint': '今晚我在星梦舞蹈室练了 60 分钟嘻哈。',
  },
];

/// In-memory onboarding state machine (§6.1). Durable server state is only
/// `pending | skipped | completed` on UserAccount; everything here is discarded
/// when the page is destroyed.
class OnboardingController extends ChangeNotifier {
  OnboardingController({OnboardingRepository? repository})
    : repository = repository ?? OnboardingRepository();

  final OnboardingRepository repository;

  bool _loadingCatalog = false;
  String? _error;
  List<Map<String, dynamic>> _categories = const [];
  String? _selectedCategory;
  List<Map<String, dynamic>> _selectedFields = const [];
  String? _skillId;
  Map<String, dynamic>? _previewPayload;
  List<String> _fieldWarnings = const [];
  List<Map<String, dynamic>> _manualFields = const [];
  String? _createdAssetId;
  bool _creatingSkill = false;
  bool _previewing = false;
  bool _confirming = false;
  bool _skipping = false;
  String? _lastConfirmationSignature;
  String? _lastConfirmationKey;
  final Uuid _uuid = const Uuid();
  late final String _skipIdempotencyKey = _uuid.v4();

  bool get loadingCatalog => _loadingCatalog;
  String? get error => _error;
  List<Map<String, dynamic>> get categories => _categories;
  String? get selectedCategory => _selectedCategory;
  List<Map<String, dynamic>> get selectedFields => _selectedFields;
  String? get skillId => _skillId;
  Map<String, dynamic>? get previewPayload => _previewPayload;
  List<String> get fieldWarnings => _fieldWarnings;
  List<Map<String, dynamic>> get manualFields => _manualFields;
  String? get createdAssetId => _createdAssetId;
  bool get creatingSkill => _creatingSkill;
  bool get previewing => _previewing;
  bool get confirming => _confirming;
  bool get skipping => _skipping;

  List<Map<String, dynamic>> get previewFields {
    if (_previewPayload != null) {
      return [
        for (final field in _selectedFields)
          {
            ...field,
            'value': _previewPayload![field['key']] == null
                ? ''
                : '${_previewPayload![field['key']]}',
            'extracted': _previewPayload!.containsKey(field['key']),
          },
      ];
    }
    return [
      for (final field in _manualFields)
        {...field, 'value': '', 'extracted': false},
    ];
  }

  bool get hasSkill => _skillId != null;

  Future<void> loadCatalog() async {
    _loadingCatalog = true;
    _error = null;
    notifyListeners();
    try {
      final data = await repository.fetchCatalog();
      final categories = (data['categories'] as List?)
          ?.cast<Map<String, dynamic>>();
      _categories = categories ?? const [];
    } catch (e) {
      _categories = _fallbackCategories;
      _error = '分类目录暂不可用，已切换到本地分类';
    } finally {
      _loadingCatalog = false;
      notifyListeners();
    }
  }

  void selectCategory(String? categoryId) {
    _selectedCategory = categoryId;
    _selectedFields = const [];
    _skillId = null;
    _error = null;
    notifyListeners();
  }

  List<Map<String, dynamic>> categoryFields(String categoryId) {
    for (final category in _categories) {
      if (category['id'] == categoryId) {
        final fields = (category['fields'] as List?)
            ?.cast<Map<String, dynamic>>();
        return fields ?? const [];
      }
    }
    return const [];
  }

  void toggleField(Map<String, dynamic> field) {
    final key = field['key'];
    final current = _selectedFields;
    final exists = current.any((f) => f['key'] == key);
    _selectedFields = exists
        ? current.where((f) => f['key'] != key).toList()
        : [...current, field];
    notifyListeners();
  }

  Future<bool> createSkill() async {
    if (_creatingSkill) return false;
    final category = _selectedCategory;
    if (category == null || _selectedFields.isEmpty) {
      _error = category == null ? '请选择记录类型' : '请至少选择一个记录字段';
      notifyListeners();
      return false;
    }
    _creatingSkill = true;
    _error = null;
    notifyListeners();
    try {
      final data = await repository.createSkill(
        category: category,
        fieldKeys: [
          for (final field in _selectedFields) field['key'] as String,
        ],
      );
      final skill = (data['skill'] as Map?)?.cast<String, dynamic>();
      _skillId = skill?['id'] as String?;
      return _skillId != null;
    } catch (_) {
      _error = '创建记录类型失败，请重试';
      return false;
    } finally {
      _creatingSkill = false;
      notifyListeners();
    }
  }

  Future<bool> runPreview(String sourceText) async {
    if (_previewing) return false;
    final skillId = _skillId;
    if (skillId == null) {
      _error = '请先创建记录类型';
      notifyListeners();
      return false;
    }
    _previewing = true;
    _error = null;
    _previewPayload = null;
    _fieldWarnings = const [];
    _manualFields = const [];
    notifyListeners();
    try {
      final data = await repository.preview(
        userSkillId: skillId,
        sourceText: sourceText,
      );
      _previewPayload = (data['payload'] as Map?)?.cast<String, dynamic>();
      _fieldWarnings =
          (data['field_warnings'] as List?)?.cast<String>() ?? const [];
      _manualFields =
          (data['manual_fields'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      return true;
    } catch (_) {
      _error = '提取失败，请重试或直接手动填写';
      return false;
    } finally {
      _previewing = false;
      notifyListeners();
    }
  }

  Future<bool> confirm({required Map<String, dynamic> payload}) async {
    if (_confirming) return false;
    final skillId = _skillId;
    if (skillId == null) {
      _error = '请先创建记录类型';
      notifyListeners();
      return false;
    }
    final signature = _confirmationSignature(skillId, payload);
    final idempotencyKey = signature == _lastConfirmationSignature
        ? _lastConfirmationKey!
        : _uuid.v4();
    _lastConfirmationSignature = signature;
    _lastConfirmationKey = idempotencyKey;
    _confirming = true;
    _error = null;
    notifyListeners();
    try {
      final data = await repository.confirm(
        skillId: skillId,
        payload: payload,
        idempotencyKey: idempotencyKey,
      );
      _createdAssetId = data['asset_id'] as String?;
      if (_createdAssetId != null) {
        _lastConfirmationSignature = null;
        _lastConfirmationKey = null;
      }
      return _createdAssetId != null;
    } catch (_) {
      _error = '确认失败，请重试';
      return false;
    } finally {
      _confirming = false;
      notifyListeners();
    }
  }

  /// Confirms with user-edited preview values. Rejects an all-empty payload
  /// client-side before any request is sent (§6).
  Future<bool> confirmFromEdits({
    required Map<String, String> rawValues,
  }) async {
    final skillId = _skillId;
    if (skillId == null) {
      _error = '请先创建记录类型';
      return false;
    }
    final payload = _coercePayload(rawValues);
    if (payload.isEmpty) {
      _error = '请至少填写一个字段';
      notifyListeners();
      return false;
    }
    return confirm(payload: payload);
  }

  String _confirmationSignature(String skillId, Map<String, dynamic> payload) {
    return jsonEncode({'skill_id': skillId, 'payload': _canonicalize(payload)});
  }

  dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return [for (final item in value) _canonicalize(item)];
    return value;
  }

  Map<String, dynamic> _coercePayload(Map<String, String> rawValues) {
    final payload = <String, dynamic>{};
    for (final field in previewFields) {
      final key = field['key'] as String;
      final text = (rawValues[key] ?? '').trim();
      if (text.isEmpty) continue;
      payload[key] = _coerceValue(text, field['type'] as String? ?? 'text');
    }
    return payload;
  }

  dynamic _coerceValue(String text, String type) {
    if (type == 'number' || type == 'duration') {
      return num.tryParse(text) ?? text;
    }
    return text;
  }

  Future<bool> skip() async {
    if (_skipping) return false;
    _skipping = true;
    _error = null;
    notifyListeners();
    try {
      await repository.skip(idempotencyKey: _skipIdempotencyKey);
      return true;
    } catch (_) {
      _error = '跳过失败，请重试';
      return false;
    } finally {
      _skipping = false;
      notifyListeners();
    }
  }

  void clear() {
    _categories = const [];
    _selectedCategory = null;
    _selectedFields = const [];
    _skillId = null;
    _previewPayload = null;
    _fieldWarnings = const [];
    _manualFields = const [];
    _createdAssetId = null;
    _lastConfirmationSignature = null;
    _lastConfirmationKey = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    repository.close();
    super.dispose();
  }
}
