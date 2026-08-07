import '../api/api_client.dart';
import '../chat/recent_session.dart';

/// Result of a flash capture (POST /api/flash). `cards` are the derived asset/
/// event/contact/task cards, same shape the chat renders.
class FlashResult {
  final bool ok;
  final String sessionId;
  final String recordingId;
  final String physicalSessionId;
  final String inputTurnId;
  final String reply;
  final String summary;
  final List<Map<String, dynamic>> cards;
  final String error;
  final bool hasPending;

  FlashResult({
    required this.ok,
    required this.sessionId,
    required this.recordingId,
    required this.physicalSessionId,
    required this.inputTurnId,
    required this.reply,
    required this.summary,
    required this.cards,
    required this.error,
    required this.hasPending,
  });

  factory FlashResult.fromJson(Map<String, dynamic> j) => FlashResult(
    ok: j['ok'] == true,
    sessionId: j['session_id'] as String? ?? '',
    recordingId: (j['recording_id'] ?? j['session_id']) as String? ?? '',
    physicalSessionId: j['physical_session_id'] as String? ?? '',
    inputTurnId: j['input_turn_id'] as String? ?? '',
    reply: j['reply'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    cards: ((j['cards'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(),
    error: j['error'] as String? ?? '',
    hasPending: j['has_pending'] == true,
  );
}

/// [source] records the real capture modality. [captureSessionType] can force
/// onboarding typed capture into a flash session while keeping source='typed'.
Future<FlashResult> sendFlash(
  ApiClient api,
  String text, {
  String source = 'voice',
  String captureSessionType = '',
  String clientTaskId = '',
}) async {
  final res = await api.postJson('/api/flash', {
    'text': text,
    'source': source,
    if (clientTaskId.isNotEmpty) 'client_task_id': clientTaskId,
    if (captureSessionType.isNotEmpty)
      'capture_session_type': captureSessionType,
  });
  final result = FlashResult.fromJson((res as Map).cast<String, dynamic>());
  final recentSessionId = result.physicalSessionId.isNotEmpty
      ? result.physicalSessionId
      : result.sessionId;
  if (recentSessionId.isNotEmpty) {
    await RecentSessionStore.save(id: recentSessionId, type: 'flash');
  }
  return result;
}
