import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../chat/recent_session.dart';

@immutable
class FlashCaptureProvenance {
  const FlashCaptureProvenance({
    required this.deviceCaptureKey,
    required this.deviceKind,
    required this.deviceId,
    required this.deviceFileName,
    required this.localAudioSha256,
    required this.localAudioSizeBytes,
    this.captureStartedAt,
    this.captureEndedAt,
  });

  final String deviceCaptureKey;
  final String deviceKind;
  final String deviceId;
  final String deviceFileName;
  final DateTime? captureStartedAt;
  final DateTime? captureEndedAt;
  final String localAudioSha256;
  final int localAudioSizeBytes;

  Map<String, dynamic> toJson() => {
    'device_capture_key': deviceCaptureKey.trim(),
    'device_kind': deviceKind.trim().toLowerCase(),
    'device_id': deviceId.trim(),
    'device_file_name': deviceFileName.trim(),
    if (captureStartedAt != null)
      'capture_started_at': captureStartedAt!.toUtc().toIso8601String(),
    if (captureEndedAt != null)
      'capture_ended_at': captureEndedAt!.toUtc().toIso8601String(),
    'local_audio_sha256': localAudioSha256.trim().toLowerCase(),
    'local_audio_size_bytes': localAudioSizeBytes,
  };
}

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
  FlashCaptureProvenance? provenance,
}) async {
  final res = await api.postJson('/api/flash', {
    'text': text,
    'source': source,
    if (clientTaskId.isNotEmpty) 'client_task_id': clientTaskId,
    if (captureSessionType.isNotEmpty)
      'capture_session_type': captureSessionType,
    if (provenance != null) ...provenance.toJson(),
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
