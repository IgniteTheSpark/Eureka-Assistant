import 'package:eureka/theme_v2/onboarding/onboarding_repository.dart';

/// Configurable in-memory OnboardingRepository for onboarding tests.
class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository({
    this.categories = const [],
    this.skillResponse,
    this.previewResponse,
    this.confirmResponse,
    this.failCreate = false,
    this.failPreview = false,
    this.failConfirm = false,
  });

  List<Map<String, dynamic>> categories;
  Map<String, dynamic>? skillResponse;
  Map<String, dynamic>? previewResponse;
  Map<String, dynamic>? confirmResponse;
  bool failCreate;
  bool failPreview;
  bool failConfirm;

  String? lastCategory;
  List<Map<String, dynamic>>? lastFields;
  String? lastSkillId;
  Map<String, dynamic>? lastPayload;
  String? lastIdempotencyKey;
  int confirmCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchCatalog() async {
    return {'version': 'test', 'categories': categories};
  }

  @override
  Future<Map<String, dynamic>> createSkill({
    required String category,
    required List<Map<String, dynamic>> fields,
  }) async {
    if (failCreate) throw Exception('create failed');
    lastCategory = category;
    lastFields = fields;
    return skillResponse ??
        {
          'skill': {
            'id': 'skill-1',
            'machine_name': 'onb_1',
            'display_name': category,
            'schema': const <String, dynamic>{},
          },
          'created': true,
        };
  }

  @override
  Future<Map<String, dynamic>> preview({
    required String userSkillId,
    required String sourceText,
  }) async {
    if (failPreview) throw Exception('preview failed');
    lastSkillId = userSkillId;
    return previewResponse ??
        {
          'payload': null,
          'field_warnings': const <String>[],
          'manual_fields': const <Map<String, dynamic>>[],
        };
  }

  @override
  Future<Map<String, dynamic>> confirm({
    required String skillId,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) async {
    confirmCalls++;
    if (failConfirm) throw Exception('confirm failed');
    lastSkillId = skillId;
    lastPayload = payload;
    lastIdempotencyKey = idempotencyKey;
    return confirmResponse ??
        {'ok': true, 'asset_id': 'asset-1', 'created': true};
  }

  @override
  Future<Map<String, dynamic>> skip({required String idempotencyKey}) async {
    return {'ok': true, 'onboarding_status': 'skipped'};
  }

  @override
  void close() {}
}
