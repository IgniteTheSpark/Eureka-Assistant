import 'package:flutter/foundation.dart';

@immutable
class SessionInvalidation {
  const SessionInvalidation({
    required this.sessionId,
    required this.sessionDate,
    required this.revision,
    required this.reason,
  });

  final String sessionId;
  final String sessionDate;
  final int revision;
  final String reason;

  factory SessionInvalidation.fromJson(Map<String, dynamic> json) {
    final rawRevision = json['revision'];
    return SessionInvalidation(
      sessionId: json['session_id']?.toString().trim() ?? '',
      sessionDate: json['session_date']?.toString().trim() ?? '',
      revision: rawRevision is num
          ? rawRevision.toInt()
          : int.tryParse(rawRevision?.toString() ?? '') ?? 0,
      reason: json['reason']?.toString().trim() ?? '',
    );
  }
}

/// SSE is an invalidation channel only. Controllers refetch their authoritative
/// Session payload instead of appending event data directly to the transcript.
class SessionInvalidations extends ValueNotifier<SessionInvalidation?> {
  SessionInvalidations._() : super(null);

  static final SessionInvalidations instance = SessionInvalidations._();

  void apply(Map<String, dynamic> json) {
    final next = SessionInvalidation.fromJson(json);
    if (next.sessionId.isEmpty || next.revision < 1) return;
    value = next;
  }
}
