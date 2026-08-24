import 'dart:async';

import 'package:eureka/theme_v2/onboarding/onboarding_repository.dart';

/// Configurable in-memory OnboardingRepository for onboarding tests.
class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository({
    this.categories = const [],
    this.skillResponse,
    this.previewResponse,
    this.confirmResponse,
    this.failCatalog = false,
    this.failCreate = false,
    this.failPreview = false,
    this.failConfirm = false,
    this.failSkip = false,
    this.createGate,
  });

  List<Map<String, dynamic>> categories;
  Map<String, dynamic>? skillResponse;
  Map<String, dynamic>? previewResponse;
  Map<String, dynamic>? confirmResponse;
  bool failCatalog;
  bool failCreate;
  bool failPreview;
  bool failConfirm;
  bool failSkip;
  Completer<void>? createGate;

  String? lastCategory;
  List<String>? lastFieldKeys;
  String? lastSkillId;
  Map<String, dynamic>? lastPayload;
  String? lastIdempotencyKey;
  final List<String> confirmKeys = [];
  int createCalls = 0;
  int confirmCalls = 0;
  int skipCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchCatalog() async {
    if (failCatalog) throw Exception('catalog failed');
    return {'version': 'test', 'categories': categories};
  }

  @override
  Future<Map<String, dynamic>> createSkill({
    required String category,
    required List<String> fieldKeys,
  }) async {
    createCalls++;
    await createGate?.future;
    if (failCreate) throw Exception('create failed');
    lastCategory = category;
    lastFieldKeys = fieldKeys;
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
    lastSkillId = skillId;
    lastPayload = payload;
    lastIdempotencyKey = idempotencyKey;
    confirmKeys.add(idempotencyKey);
    if (failConfirm) throw Exception('confirm failed');
    return confirmResponse ??
        {'ok': true, 'asset_id': 'asset-1', 'created': true};
  }

  @override
  Future<Map<String, dynamic>> skip({required String idempotencyKey}) async {
    skipCalls++;
    if (failSkip) throw Exception('skip failed');
    return {'ok': true, 'onboarding_status': 'skipped'};
  }

  @override
  void close() {}
}
