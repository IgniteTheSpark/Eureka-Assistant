import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/sse_client.dart';
import '../data_revision.dart';
import 'chat_models.dart';

/// Persists the last active chat session so the Agent entry resumes it (web
/// parity: `eureka:active_chat_session`). Cleared on 新对话 / logout.
const _kActiveSession = 'eureka:active_chat_session';

/// Drives one chat session: sends a turn to POST /api/chat and folds the SSE
/// frames (meta / token / tool_call / tool_result / error / done) into the
/// streaming agent message. Mirrors the web `useChat.applyFrame`.
class ChatController extends ChangeNotifier {
  final List<ChatMessage> messages = [];
  bool streaming = false;
  String? sessionId;
  String? error;

  /// When this chat is bound to a subject (opened via an asset's 讨论), the
  /// subject is held *pending* — no session is created until the first message
  /// is sent, so merely opening a discuss thread never leaves an empty session.
  String? subjectType;
  String? subjectId;

  /// Readable title of the current session (from the sidebar row when replayed).
  String? sessionTitle;

  /// Attached context assets ({id, label}) restored on loadSession, so the chip
  /// rail repopulates when reopening a history session (codex r2).
  List<({String id, String label})> contextAssets = [];

  final ApiClient _api = ApiClient();

  /// True once disposed — guards the durable-turn poll loop from notifying a
  /// dead controller (§1.5.1.3).
  bool _disposed = false;

  /// The session currently being reconcile-polled (a turn was still generating
  /// when we loaded it). Prevents overlapping poll loops.
  String? _pollingSession;

  @override
  void dispose() {
    _disposed = true;
    _api.close();
    super.dispose();
  }

  static Future<void> _persistActive(String? id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await sp.remove(_kActiveSession);
      } else {
        await sp.setString(_kActiveSession, id);
      }
    } catch (_) {/* best-effort */}
  }

  /// Resume the last active session (Agent entry with no bound subject). No-op
  /// if none persisted or it no longer loads (deleted / other user → empty).
  Future<void> resumeLast() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getString(_kActiveSession);
      if (id != null && id.isNotEmpty) await loadSession(id);
    } catch (_) {/* stay on a blank chat */}
  }

  /// Start a fresh conversation. Clears the bound subject (anchored context) AND
  /// the attached context assets — a deliberately-new conversation must carry no
  /// context from the previous one.
  void reset() {
    messages.clear();
    sessionId = null;
    sessionTitle = null;
    subjectType = null;
    subjectId = null;
    contextAssets = [];
    error = null;
    _persistActive(null);
    notifyListeners();
  }

  /// A human-readable header title: the session's stored title, else the first
  /// user line (matching the backend's auto-title), else 新对话.
  String get displayTitle {
    final t = sessionTitle?.trim();
    if (t != null && t.isNotEmpty) return t;
    for (final m in messages) {
      if (m.isUser && m.text.trim().isNotEmpty) {
        final s = m.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        return s.length > 18 ? '${s.substring(0, 18)}…' : s;
      }
    }
    return '新对话';
  }

  /// Bind a subject (asset/event/contact) without creating a session. If a
  /// thread for this subject already exists, peek it (查不建) and replay it.
  Future<void> bindSubject(String type, String id) async {
    subjectType = type;
    subjectId = id;
    try {
      final res = await _api.postJson('/api/sessions', {
        'session_type': 'chat',
        'subject_type': type,
        'subject_id': id,
        'peek_only': true,
      });
      final sid = (res is Map ? res['session_id'] : null) as String?;
      if (sid != null && sid.isNotEmpty) await loadSession(sid);
    } catch (_) {
      // no existing thread — stay empty until the first send creates one
    }
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

  /// Delete a session (DELETE /api/sessions/{id}). Its captured assets survive
  /// (the backend detaches them); only the conversation is removed. Resets the
  /// view if the deleted session was the active one.
  Future<bool> deleteSession(String id) async {
    try {
      await _api.deleteJson('/api/sessions/$id');
      if (sessionId == id) reset();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Load + replay a session's history into [messages]. [title] (when passed
  /// from the sidebar row) drives the readable header.
  Future<void> loadSession(String id, {String? title}) async {
    if (title != null) sessionTitle = title;
    final res = await _api.getJson('/api/sessions/$id/messages');
    final raw = (res is Map ? res['messages'] : null) as List? ?? const [];
    _applyMessages(raw);
    sessionId = id;
    // Restore the attached context assets so the chip rail isn't empty after
    // reopening a history session (codex r2). Best-effort — a failure just
    // leaves no chips, same as before.
    try {
      final s = await _api.getJson('/api/sessions/$id');
      final sess = (s is Map ? s['session'] : null) as Map?;
      final ca = (sess?['context_assets'] as List?) ?? const [];
      contextAssets = ca
          .whereType<Map>()
          .map((m) => (id: m['id'] as String? ?? '', label: m['label'] as String? ?? '资产'))
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (_) {
      contextAssets = [];
    }
    _persistActive(id);
    notifyListeners();
    // §1.5.1.3 batch A — a turn may still be generating server-side (we left
    // mid-generation and came back). Its agent message is `running` → shown as
    // 「分析中…」; poll until it lands, then auto-render the reply/cards.
    if (_hasPending(raw)) _reconcilePending(id);
  }

  /// Rebuild [messages] from a /messages payload. Agent messages with
  /// status='running' (§1.5.1.3) replay as a 「分析中…」 placeholder (streaming
  /// + empty parts), which the durable-turn poll later fills.
  void _applyMessages(List raw) {
    messages.clear();
    for (final mm in raw.whereType<Map>()) {
      final m = mm.cast<String, dynamic>();
      if (m['role'] == 'user') {
        messages.add(ChatMessage.user(m['id'] as String? ?? 'u', m['text'] as String? ?? ''));
      } else if (m['role'] == 'agent') {
        final running = (m['status'] as String? ?? 'done') == 'running';
        final msg = ChatMessage.agent(m['id'] as String? ?? 'a');
        msg.streaming = running;   // running → 「分析中…」 (chat_page renders it)
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
  }

  /// Any agent turn still generating server-side?
  bool _hasPending(List raw) => raw.whereType<Map>().any(
      (m) => m['role'] == 'agent' && (m['status'] as String? ?? 'done') == 'running');

  /// Reconcile a session that had an in-flight turn on load: poll the message
  /// log until the running turn lands (or a timeout), then rebuild + render the
  /// reply/cards. Stops if the user switches sessions or the controller dies.
  Future<void> _reconcilePending(String id) async {
    if (_pollingSession == id) return;   // already polling this one
    _pollingSession = id;
    final deadline = DateTime.now().add(const Duration(seconds: 150));
    try {
      while (!_disposed && sessionId == id && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (_disposed || sessionId != id) break;
        final res = await _api.getJson('/api/sessions/$id/messages');
        final raw = (res is Map ? res['messages'] : null) as List? ?? const [];
        if (_disposed || sessionId != id) break;
        if (!_hasPending(raw)) {
          _applyMessages(raw);     // turn landed → reply + cards now present
          notifyListeners();
          bumpData();              // a turn may have created assets → refresh other surfaces
          break;
        }
      }
    } catch (_) {/* best-effort; stop polling on error */}
    finally {
      if (_pollingSession == id) _pollingSession = null;
    }
  }

  /// Ensure a session exists so context can be attached / a subject bound before
  /// the first message. Binds the pending subject if one is set (so the created
  /// session is the subject's thread, not an orphan blank one).
  Future<String?> ensureSession() async {
    if (sessionId != null) return sessionId;
    try {
      final body = <String, dynamic>{'session_type': 'chat'};
      if (subjectType != null && subjectId != null) {
        body['subject_type'] = subjectType;
        body['subject_id'] = subjectId;
      }
      final res = await _api.postJson('/api/sessions', body);
      sessionId = (res is Map ? res['session_id'] : null) as String?;
      return sessionId;
    } catch (_) {
      return null;
    }
  }

  /// Attach one or more assets as context to the current session in a single
  /// PATCH (web's 添加资产 flow; picker is multi-select).
  Future<bool> attachContexts(List<String> assetIds) async {
    if (assetIds.isEmpty) return true;
    final sid = await ensureSession();
    if (sid == null) return false;
    try {
      await _api.patchJson('/api/sessions/$sid/context', {'add': assetIds});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Attach a single asset as context (convenience wrapper).
  Future<bool> attachContext(String assetId) => attachContexts([assetId]);

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

    // Lazy subject binding: a discuss thread only becomes a real session now,
    // on the first message. (/api/chat has no subject param, so the bound
    // session must exist before the turn; plain chats let the backend create
    // it via the SSE `meta` frame.)
    if (sessionId == null && subjectType != null && subjectId != null) {
      await ensureSession();
    }

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
      // A turn may have created/updated assets (todo, event, …) via tools —
      // refresh every other surface (library / calendar / category lists).
      bumpData();
    }
  }

  void _apply(ChatMessage agent, SseEvent ev) {
    switch (ev.type) {
      case 'meta':
        final sid = ev.json['session_id'];
        if (sid is String && sid.isNotEmpty) {
          sessionId = sid;
          _persistActive(sid); // a new lazily-created session becomes the active one
        }
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
