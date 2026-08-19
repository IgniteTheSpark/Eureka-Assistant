import '../../api/api_client.dart';

/// Data access for the Theme V2 onboarding flow (§6).
///
/// Talks to the dedicated onboarding endpoints; the catalog endpoint is
/// public, everything else requires an authenticated session.
class OnboardingRepository {
  OnboardingRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Loads the curated category catalog (public, no auth).
  Future<Map<String, dynamic>> fetchCatalog() async {
    final res = await _client.getJson('/api/onboarding/catalog');
    return (res as Map).cast<String, dynamic>();
  }

  /// Creates (or idempotently returns) a UserSkill from a category + fields.
  Future<Map<String, dynamic>> createSkill({
    required String category,
    required List<Map<String, dynamic>> fields,
  }) async {
    final res = await _client.postJson('/api/onboarding/skills', {
      'category': category,
      'fields': fields,
    });
    return (res as Map).cast<String, dynamic>();
  }

  /// Runs extraction-only preview; never persists an Asset.
  Future<Map<String, dynamic>> preview({
    required String userSkillId,
    required String sourceText,
  }) async {
    final res = await _client.postJson('/api/onboarding/preview', {
      'user_skill_id': userSkillId,
      'source_text': sourceText,
    });
    return (res as Map).cast<String, dynamic>();
  }

  /// Confirms the first Asset (idempotent via [idempotencyKey]).
  Future<Map<String, dynamic>> confirm({
    required String skillId,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) async {
    final res = await _client.postJson('/api/onboarding/confirm', {
      'skill_id': skillId,
      'payload': payload,
      'idempotency_key': idempotencyKey,
    });
    return (res as Map).cast<String, dynamic>();
  }

  /// Marks onboarding as skipped (idempotent).
  Future<Map<String, dynamic>> skip({required String idempotencyKey}) async {
    final res = await _client.postJson('/api/onboarding/skip', {
      'idempotency_key': idempotencyKey,
    });
    return (res as Map).cast<String, dynamic>();
  }

  void close() => _client.close();
}
