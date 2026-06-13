import '../api/api_client.dart';
import '../chat/recent_session.dart';

/// Result of a flash capture (POST /api/flash). `cards` are the derived asset/
/// event/contact/task cards, same shape the chat renders.
class FlashResult {
  final bool ok;
  final String sessionId;
  final String inputTurnId;
  final String reply;
  final String summary;
  final List<Map<String, dynamic>> cards;
  final String error;

  FlashResult({
    required this.ok,
    required this.sessionId,
    required this.inputTurnId,
    required this.reply,
    required this.summary,
    required this.cards,
    required this.error,
  });

  factory FlashResult.fromJson(Map<String, dynamic> j) => FlashResult(
    ok: j['ok'] == true,
    sessionId: j['session_id'] as String? ?? '',
    inputTurnId: j['input_turn_id'] as String? ?? '',
    reply: j['reply'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    cards: ((j['cards'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(),
    error: j['error'] as String? ?? '',
  );
}

/// [source] records the real capture modality. [captureSessionType] can force
/// onboarding typed capture into a flash session while keeping source='typed'.
Future<FlashResult> sendFlash(
  ApiClient api,
  String text, {
  String source = 'voice',
  String captureSessionType = '',
}) async {
  final res = await api.postJson('/api/flash', {
    'text': text,
    'source': source,
    if (captureSessionType.isNotEmpty)
      'capture_session_type': captureSessionType,
  });
  final result = FlashResult.fromJson((res as Map).cast<String, dynamic>());
  if (result.sessionId.isNotEmpty) {
    await RecentSessionStore.save(id: result.sessionId, type: 'flash');
  }
  return result;
}
