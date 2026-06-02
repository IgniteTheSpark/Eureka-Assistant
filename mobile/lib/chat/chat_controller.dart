import 'package:flutter/foundation.dart';

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
