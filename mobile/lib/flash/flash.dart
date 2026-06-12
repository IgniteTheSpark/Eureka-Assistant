import '../api/api_client.dart';

/// Result of a flash capture (POST /api/flash). `cards` are the derived asset/
/// event/contact/task cards, same shape the chat renders.
class FlashResult {
  final bool ok;
  final String reply;
  final String summary;
  final List<Map<String, dynamic>> cards;
  final String error;

  FlashResult({
    required this.ok,
    required this.reply,
    required this.summary,
    required this.cards,
    required this.error,
  });

  factory FlashResult.fromJson(Map<String, dynamic> j) => FlashResult(
        ok: j['ok'] == true,
        reply: j['reply'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        cards: ((j['cards'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        error: j['error'] as String? ?? '',
      );
}

/// [source] = capture modality: 'voice'(硬件闪念,默认)→ 闪念 session;
/// 'typed'(打字,如 onboarding 首捕)→ 中性「记录」session(打字 ≠ 闪念)。
Future<FlashResult> sendFlash(ApiClient api, String text, {String source = 'voice'}) async {
  final res = await api.postJson('/api/flash', {'text': text, 'source': source});
  return FlashResult.fromJson((res as Map).cast<String, dynamic>());
}
