import 'package:flutter/foundation.dart';

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
  },
  _customCategoryEntry,
];

const _customCategoryEntry = <String, dynamic>{
  'id': 'custom',
  'label': '自定义记录',
  'description': '用自己的字段记录一件重要的事',
  'fields': <Map<String, dynamic>>[],
};

const _customCategoryId = 'custom';

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
  String _customCategoryName = '';
  List<Map<String, dynamic>> _selectedFields = const [];
  String? _skillId;
  Map<String, dynamic>? _previewPayload;
  List<String> _fieldWarnings = const [];
  List<Map<String, dynamic>> _manualFields = const [];
  String? _createdAssetId;
  final String _skipIdempotencyKey =
      'onb-skip-${DateTime.now().microsecondsSinceEpoch}';

  bool get loadingCatalog => _loadingCatalog;
  String? get error => _error;
  List<Map<String, dynamic>> get categories => _categories;
  String? get selectedCategory => _selectedCategory;
  String get customCategoryName => _customCategoryName;
  List<Map<String, dynamic>> get selectedFields => _selectedFields;
  String? get skillId => _skillId;
  Map<String, dynamic>? get previewPayload => _previewPayload;
  List<String> get fieldWarnings => _fieldWarnings;
  List<Map<String, dynamic>> get manualFields => _manualFields;
  String? get createdAssetId => _createdAssetId;

  List<Map<String, dynamic>> get previewFields {
    if (_previewPayload != null) {
      return [
        for (final field in _selectedFields)
          {
            ...field,
            'value':
                _previewPayload![field['key']] == null
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

  bool get isCustomCategory => _selectedCategory == _customCategoryId;

  Future<void> loadCatalog() async {
    _loadingCatalog = true;
    _error = null;
    notifyListeners();
    try {
      final data = await repository.fetchCatalog();
      final categories = (data['categories'] as List?)
          ?.cast<Map<String, dynamic>>();
      _categories = _withCustomCategory(categories ?? const []);
    } catch (e) {
      _categories = _fallbackCategories;
      _error = '分类目录暂不可用，已切换到本地分类';
    } finally {
      _loadingCatalog = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _withCustomCategory(
    List<Map<String, dynamic>> categories,
  ) {
    if (categories.any((c) => c['id'] == _customCategoryId)) return categories;
    return [...categories, _customCategoryEntry];
  }

  void selectCategory(String? categoryId) {
    _selectedCategory = categoryId;
    _selectedFields = const [];
    _error = null;
    notifyListeners();
  }

  void setCustomCategoryName(String name) {
    _customCategoryName = name;
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

  void addCustomField(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      _error = '字段名称不能为空';
      notifyListeners();
      return;
    }
    final key = _keyFromLabel(trimmed);
    final field = <String, dynamic>{
      'key': key,
      'label': trimmed,
      'type': 'text',
    };
    final exists = _selectedFields.any((f) => f['key'] == key);
    _selectedFields = [
      for (final f in _selectedFields)
        if (f['key'] == key) field else f,
      if (!exists) field,
    ];
    _error = null;
    notifyListeners();
  }

  String _keyFromLabel(String label) {
    final cleaned = label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_\u4e00-\u9fff]'), '');
    return cleaned.isEmpty ? 'field_${_selectedFields.length + 1}' : cleaned;
  }

  Future<bool> createSkill() async {
    final category = _selectedCategory;
    if (category == null || _selectedFields.isEmpty) {
      _error = '请选择分类和至少一个字段';
      notifyListeners();
      return false;
    }
    final effectiveCategory = isCustomCategory
        ? _customCategoryName.trim()
        : category;
    if (effectiveCategory.isEmpty) {
      _error = '请填写自定义记录名称';
      notifyListeners();
      return false;
    }
    _error = null;
    try {
      final data = await repository.createSkill(
        category: effectiveCategory,
        fields: _selectedFields,
      );
      final skill = (data['skill'] as Map?)?.cast<String, dynamic>();
      _skillId = skill?['id'] as String?;
      notifyListeners();
      return _skillId != null;
    } catch (e) {
      _error = '创建记录类型失败，请重试';
      return false;
    }
  }

  Future<bool> runPreview(String sourceText) async {
    final skillId = _skillId;
    if (skillId == null) {
      _error = '请先创建记录类型';
      return false;
    }
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
      notifyListeners();
      return true;
    } catch (e) {
      _error = '提取失败，请重试或直接手动填写';
      return false;
    }
  }

  Future<bool> confirm({
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) async {
    final skillId = _skillId;
    if (skillId == null) {
      _error = '请先创建记录类型';
      return false;
    }
    _error = null;
    try {
      final data = await repository.confirm(
        skillId: skillId,
        payload: payload,
        idempotencyKey: idempotencyKey,
      );
      _createdAssetId = data['asset_id'] as String?;
      notifyListeners();
      return _createdAssetId != null;
    } catch (e) {
      _error = '确认失败，请重试';
      return false;
    }
  }

  /// Confirms with user-edited preview values. Rejects an all-empty payload
  /// client-side before any request is sent (§6).
  Future<bool> confirmFromEdits({
    required Map<String, String> rawValues,
    required String idempotencyKey,
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
    return confirm(payload: payload, idempotencyKey: idempotencyKey);
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
    try {
      await repository.skip(idempotencyKey: _skipIdempotencyKey);
      return true;
    } catch (_) {
      _error = '跳过失败，请重试';
      return false;
    }
  }

  void clear() {
    _categories = const [];
    _selectedCategory = null;
    _customCategoryName = '';
    _selectedFields = const [];
    _skillId = null;
    _previewPayload = null;
    _fieldWarnings = const [];
    _manualFields = const [];
    _createdAssetId = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    repository.close();
    super.dispose();
  }
}
