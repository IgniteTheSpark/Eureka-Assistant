import 'package:flutter/foundation.dart';

import 'onboarding_repository.dart';

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

  bool get hasSkill => _skillId != null;

  Future<void> loadCatalog() async {
    _loadingCatalog = true;
    _error = null;
    notifyListeners();
    try {
      final data = await repository.fetchCatalog();
      final categories = (data['categories'] as List?)?.cast<Map<String, dynamic>>();
      _categories = categories ?? const [];
    } catch (e) {
      _error = '分类目录加载失败，请稍后重试';
    } finally {
      _loadingCatalog = false;
      notifyListeners();
    }
  }

  void selectCategory(String? categoryId) {
    _selectedCategory = categoryId;
    _selectedFields = const [];
    _error = null;
    notifyListeners();
  }

  List<Map<String, dynamic>> categoryFields(String categoryId) {
    for (final category in _categories) {
      if (category['id'] == categoryId) {
        final fields = (category['fields'] as List?)?.cast<Map<String, dynamic>>();
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
    final category = _selectedCategory;
    if (category == null || _selectedFields.isEmpty) {
      _error = '请选择分类和至少一个字段';
      return false;
    }
    _error = null;
    try {
      final data = await repository.createSkill(
        category: category,
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

  Future<bool> skip() async {
    try {
      await repository.skip();
      return true;
    } catch (_) {
      _error = '跳过失败，请重试';
      return false;
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
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    repository.close();
    super.dispose();
  }
}
