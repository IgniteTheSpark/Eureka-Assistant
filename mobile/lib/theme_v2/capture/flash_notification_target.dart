import 'package:flutter/material.dart';

import '../../pages/session_detail_page.dart';
import 'capture_session_page.dart';

/// Returns a Theme V2 recording id only for the new capture deep-link format.
/// Bare values remain legacy session ids for backwards compatibility.
String? flashRecordingIdFromLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.path != '/library') return null;
  final id = uri.queryParameters['recording_id']?.trim();
  return id == null || id.isEmpty ? null : id;
}

Widget flashNotificationTargetPage(String link) {
  final recordingId = flashRecordingIdFromLink(link);
  if (recordingId != null) {
    return CaptureSessionPage(recordingId: recordingId);
  }
  return SessionDetailPage(sessionId: link, title: '闪念');
}

Future<void> openFlashNotificationTarget(BuildContext context, String link) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => flashNotificationTargetPage(link)),
  );
}
