import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart';
import 'auth_store.dart';

/// One server-sent event: an `event:` type + its decoded `data`.
/// `data` is the parsed JSON object when possible, else the raw string.
class SseEvent {
  final String type;
  final dynamic data;
  SseEvent(this.type, this.data);

  Map<String, dynamic> get json =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};
}

/// Stream SSE frames from a POST endpoint. The backend's chat + flash routes
/// reply with `POST` + `text/event-stream` (frames: `event: <t>` / `data: <json>`
/// separated by a blank line), so this mirrors the web `parsePostSseStream`.
///
/// Yields an [SseEvent] per frame until the stream closes. Lines starting with
/// `:` (heartbeat comments) are ignored. Throws [ApiException] on a non-2xx.
Stream<SseEvent> postSse(
  String path,
  Map<String, dynamic> body, {
  String? baseUrl,
  http.Client? client,
}) {
  final req = http.Request('POST', Uri.parse('${baseUrl ?? AppConfig.apiBase}$path'));
  req.headers['Content-Type'] = 'application/json';
  req.body = jsonEncode(body);
  return _sse(req, client);
}

/// Stream SSE frames from a GET endpoint (e.g. /api/notifications/stream — the
/// live hardware bridge channel: `listening` / `capture` / `notification`).
Stream<SseEvent> getSse(String path, {String? baseUrl, http.Client? client}) {
  final req = http.Request('GET', Uri.parse('${baseUrl ?? AppConfig.apiBase}$path'));
  return _sse(req, client);
}

Stream<SseEvent> _sse(http.Request req, http.Client? client) async* {
  final c = client ?? http.Client();
  try {
    req.headers['Accept'] = 'text/event-stream';
    if (AuthStore.token != null) {
      req.headers['Authorization'] = 'Bearer ${AuthStore.token}';
    }

    final res = await c.send(req);
    if (res.statusCode >= 400) {
      // 401 self-heal: mirror ApiClient's REST behavior so an expired token on a
      // chat / report SSE drops the user back to login instead of just surfacing
      // a raw error (codex r2 — SSE 401 was not triggering onUnauthorized).
      if (res.statusCode == 401 && AuthStore.token != null) {
        AuthStore.onUnauthorized?.call();
      }
      throw ApiException(res.statusCode, await res.stream.bytesToString());
    }

    var eventType = 'message';
    final dataLines = <String>[];

    SseEvent? flush() {
      if (dataLines.isEmpty) return null;
      final raw = dataLines.join('\n');
      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        parsed = raw;
      }
      final ev = SseEvent(eventType, parsed);
      eventType = 'message';
      dataLines.clear();
      return ev;
    }

    await for (final line
        in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        final ev = flush();
        if (ev != null) yield ev;
        continue;
      }
      if (line.startsWith(':')) continue; // heartbeat / comment
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).replaceFirst(' ', ''));
      }
    }
    final tail = flush();
    if (tail != null) yield tail;
  } finally {
    if (client == null) c.close();
  }
}
