import '../api/api_client.dart';

/// One asset row from GET /api/assets.
class AssetItem {
  final String id;
  final String skillName;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? sessionId;

  /// A readable title resolved against the skill's render_spec (see
  /// `readableTitle`). When set, [title] returns it — so custom skills whose
  /// content lives in a non-standard field don't fall back to the machine name.
  final String? titleOverride;

  AssetItem({
    required this.id,
    required this.skillName,
    required this.payload,
    required this.createdAt,
    this.sessionId,
    this.titleOverride,
  });

  factory AssetItem.fromJson(Map<String, dynamic> j) => AssetItem(
        id: j['id'] as String? ?? '',
        skillName: j['user_skill_name'] as String? ?? 'misc',
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        sessionId: j['session_id'] as String?,
      );

  AssetItem copyWithTitle(String t) => AssetItem(
        id: id,
        skillName: skillName,
        payload: payload,
        createdAt: createdAt,
        sessionId: sessionId,
        titleOverride: t,
      );

  /// Best-effort display title. Prefers an explicit [titleOverride] (resolved via
  /// render_spec), then common payload fields (content / title / name / amount).
  String get title {
    final o = titleOverride?.trim();
    if (o != null && o.isNotEmpty) return o;
    final p = payload;
    final t = p['content'] ?? p['title'] ?? p['name'] ?? p['amount'];
    return (t ?? '').toString();
  }
}

Future<List<AssetItem>> fetchAssets(ApiClient api) async {
  final res = await api.getJson('/api/assets');
  final list = (res is Map ? res['assets'] : null) as List? ?? const [];
  return list
      .whereType<Map>()
      .map((e) => AssetItem.fromJson(e.cast<String, dynamic>()))
      .toList();
}
