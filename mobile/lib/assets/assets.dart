import '../api/api_client.dart';

/// One asset row from GET /api/assets.
class AssetItem {
  final String id;
  final String skillName;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  AssetItem({
    required this.id,
    required this.skillName,
    required this.payload,
    required this.createdAt,
  });

  factory AssetItem.fromJson(Map<String, dynamic> j) => AssetItem(
        id: j['id'] as String? ?? '',
        skillName: j['user_skill_name'] as String? ?? 'misc',
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );

  /// Best-effort display title from the payload (content / title / name / amount).
  String get title {
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
