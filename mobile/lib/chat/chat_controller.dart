import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/sse_client.dart';
import 'chat_models.dart';

/// Drives one chat session: sends a turn to POST /api/chat and folds the SSE
/// frames (meta / token / tool_call / tool_result / error / done) into the
/// streaming agent message. Mirrors the web `useChat.applyFrame`.
class ChatController extends ChangeNotifier {
  final List<ChatMessage> messages = [];
  bool streaming = false;
  String? sessionId;
  String? error;

  final ApiClient _api = ApiClient();

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  /// Start a fresh conversation.
  void reset() {
    messages.clear();
    sessionId = null;
    error = null;
    notifyListeners();
  }

  /// List the user's sessions for the sidebar (newest first per backend).
  Future<List<SessionInfo>> listSessions() async {
    final res = await _api.getJson('/api/sessions');
    final raw = (res is Map ? res['sessions'] : null) as List? ?? const [];
    return raw.whereType<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      final title = (m['title'] as String?)?.trim();
      return SessionInfo(
        m['id'] as String? ?? '',
        (title == null || title.isEmpty) ? '新对话' : title,
        DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
    }).toList();
  }

  /// Load + replay a session's history into [messages].
  Future<void> loadSession(String id) async {
    final res = await _api.getJson('/api/sessions/$id/messages');
    final raw = (res is Map ? res['messages'] : null) as List? ?? const [];
    messages.clear();
    for (final mm in raw.whereType<Map>()) {
      final m = mm.cast<String, dynamic>();
      if (m['role'] == 'user') {
        messages.add(ChatMessage.user(m['id'] as String? ?? 'u', m['text'] as String? ?? ''));
      } else if (m['role'] == 'agent') {
        final msg = ChatMessage.agent(m['id'] as String? ?? 'a');
        msg.streaming = false;
        final tc = m['tool_call'];
        if (tc is Map) msg.parts.add(ToolCallPart(tc['name'] as String? ?? '?'));
        final tr = m['tool_result'];
        if (tr is Map) {
          msg.parts.add(ToolResultPart(
              tr['name'] as String? ?? '?', (tr['response'] as Map?)?.cast<String, dynamic>() ?? {}));
        }
        final text = m['text'] as String?;
        if (text != null && text.isNotEmpty) {
          msg.parts.add(TextPart(text));
          msg.text = text;
        }
        final cards = m['cards'];
        if (cards is List && cards.isNotEmpty) {
          msg.parts.add(CardsPart(
              cards.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()));
        }
        final el = m['elapsed_ms'];
        if (el is num) msg.elapsedMs = el.toInt();
        messages.add(msg);
      }
    }
    sessionId = id;
    notifyListeners();
  }

  /// 沉淀为资产 — turn a Q&A answer into an asset of [skill] (todo/notes/idea/
  /// misc), linked to this session. Throws on failure so the UI can show it.
  Future<void> precipitate(String text, String skill) async {
    final payload = <String, dynamic>{'content': text};
    if (skill == 'notes' || skill == 'idea') {
      var title = text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (title.length > 24) title = title.substring(0, 24);
      payload['title'] = title;
    }
    await _api.postJson('/api/assets', {
      'user_skill_name': skill,
      'payload': payload,
      'session_id': sessionId ?? '',
    });
  }

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || streaming) return;
    error = null;

    final stamp = DateTime.now().microsecondsSinceEpoch;
    messages.add(ChatMessage.user('u-$stamp', t));
    final agent = ChatMessage.agent('a-$stamp');
    messages.add(agent);
    streaming = true;
    notifyListeners();

    try {
      await for (final ev in postSse('/api/chat', {
        'user_text': t,
        'session_id': sessionId ?? '',
      })) {
        _apply(agent, ev);
        notifyListeners();
      }
    } catch (e) {
      agent.parts.add(ErrorPart(e.toString()));
      error = e.toString();
    } finally {
      agent.streaming = false;
      streaming = false;
      notifyListeners();
    }
  }

  void _apply(ChatMessage agent, SseEvent ev) {
    switch (ev.type) {
      case 'meta':
        final sid = ev.json['session_id'];
        if (sid is String && sid.isNotEmpty) sessionId = sid;
      case 'token':
        final txt = ev.json['text'];
        if (txt is String && txt.isNotEmpty) _mergeText(agent, txt);
      case 'tool_call':
        agent.parts.add(ToolCallPart(ev.json['name'] as String? ?? '?'));
      case 'tool_result':
        final resp = (ev.json['response'] as Map?)?.cast<String, dynamic>() ?? {};
        agent.parts.add(ToolResultPart(ev.json['name'] as String? ?? '?', resp));
      case 'error':
        agent.parts.add(ErrorPart(ev.json['message'] as String? ?? 'stream error'));
      case 'done':
        agent.elapsedMs = (ev.json['elapsed_ms'] as num?)?.toInt();
        agent.tokens = (ev.json['total_tokens'] as num?)?.toInt();
    }
  }

  void _mergeText(ChatMessage agent, String chunk) {
    final parts = agent.parts;
    if (parts.isNotEmpty && parts.last is TextPart) {
      parts[parts.length - 1] = TextPart((parts.last as TextPart).text + chunk);
    } else {
      parts.add(TextPart(chunk));
    }
    agent.text += chunk;
  }
}
