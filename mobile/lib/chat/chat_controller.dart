import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/sse_client.dart';
import '../data_revision.dart';
import '../theme_v2/session/session_card_contract.dart';
import 'chat_models.dart';
import 'recent_session.dart';

typedef ChatTurnStream =
    Stream<SseEvent> Function(String path, Map<String, dynamic> body);

/// Explicit write tools in the Assistant MCP contract. A tool result must also
/// contain its structured successful persistence receipt before it can publish
/// a Library-invalidating mutation.
const _persistedMutationToolNames = <String>{
  'tool_create_asset',
  'tool_create_todo',
  'tool_create_note',
  'tool_update_asset',
  'tool_delete_asset',
  'tool_create_contact',
  'tool_update_contact',
  'tool_delete_contact',
  'tool_create_event',
  'tool_update_event',
  'tool_delete_event',
  'tool_add_event_attendee',
  'tool_update_event_attendee',
  'tool_delete_event_attendee',
  'tool_link_event_file',
  'tool_create_task',
  'bulk_import',
};

bool _isConfirmedPersistedMutationToolResult(
  String name,
  Map<String, dynamic> response,
) {
  if (!_persistedMutationToolNames.contains(name)) return false;
  final payloads = _toolResultPayloads(response);
  if (name == 'bulk_import') {
    // Chat's bulk path is synthesized only from cards the backend already
    // persisted, so its grouped card arrays are its success receipt.
    return payloads.any(
      (payload) => const {
        'assets',
        'events',
        'contacts',
        'tasks',
      }.any((key) => payload[key] is List && (payload[key] as List).isNotEmpty),
    );
  }
  return payloads.any((payload) => payload['ok'] == true);
}

Iterable<Map<String, dynamic>> _toolResultPayloads(
  Map<String, dynamic> response,
) sync* {
  yield response;

  final structured = response['structuredContent'];
  if (structured is Map) {
    yield structured.cast<String, dynamic>();
    final result = structured['result'];
    if (result is String) {
      final parsed = _decodeToolResult(result);
      if (parsed != null) yield parsed;
    }
  }

  final content = response['content'];
  if (content is List && content.isNotEmpty && content.first is Map) {
    final text = (content.first as Map)['text'];
    if (text is String) {
      final parsed = _decodeToolResult(text);
      if (parsed != null) yield parsed;
    }
  }
}

Map<String, dynamic>? _decodeToolResult(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } on FormatException {
    return null;
  }
}

/// Persists the last active chat session so the Agent entry resumes it (web
/// parity: `eureka:active_chat_session`). Cleared on 新对话 / logout.
const _kActiveSession = 'eureka:active_chat_session';

/// Drives one chat session: sends a turn to POST /api/chat and folds the SSE
/// frames (meta / token / tool_call / tool_result / error / done) into the
/// streaming agent message. Mirrors the web `useChat.applyFrame`.
class ChatController extends ChangeNotifier {
  ChatController({
    ApiClient? api,
    ChatTurnStream? turnStream,
    DateTime Function()? now,
    Duration reconcileInterval = const Duration(milliseconds: 1500),
    Duration reconcileTimeout = const Duration(seconds: 150),
  }) : _reconcileInterval = reconcileInterval,
       _reconcileTimeout = reconcileTimeout,
       _now = now ?? DateTime.now,
       _api = api ?? ApiClient(),
       _ownsApi = api == null,
       _turnStream = turnStream ?? ((path, body) => postSse(path, body));

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

  final ApiClient _api;
  final bool _ownsApi;
  final ChatTurnStream _turnStream;
  final DateTime Function() _now;
  final Duration _reconcileInterval;
  final Duration _reconcileTimeout;

  String? _retryableUserText;
  ChatMessage? _failedAgent;
  StreamSubscription<SseEvent>? _activeTurnSubscription;
  Completer<void>? _activeTurnCompleter;
  ChatMessage? _activeAgent;
  var _turnRevision = 0;
  var _sessionLoadRevision = 0;
  String? _pendingSessionId;
  Future<String?>? _ensureSessionFuture;
  String? _reconcileRetrySessionId;
  final Set<String> _deletedSessionIds = {};

  /// True once disposed — guards the durable-turn poll loop from notifying a
  /// dead controller (§1.5.1.3).
  bool _disposed = false;

  /// The session currently being reconcile-polled (a turn was still generating
  /// when we loaded it). Prevents overlapping poll loops.
  String? _pollingSession;
  int? _pollingRevision;

  @override
  void dispose() {
    _disposed = true;
    _sessionLoadRevision++;
    _ensureSessionFuture = null;
    _cancelActiveTurn(notify: false);
    if (_ownsApi) _api.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static Future<void> _persistActive(String? id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await sp.remove(_kActiveSession);
      } else {
        await sp.setString(_kActiveSession, id);
      }
    } catch (_) {
      /* best-effort */
    }
  }

  /// Resume the last active session (Agent entry with no bound subject). No-op
  /// if none persisted or it no longer loads (deleted / other user → empty).
  Future<void> resumeLast() async {
    final revision = _sessionLoadRevision;
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getString(_kActiveSession);
      if (revision == _sessionLoadRevision && id != null && id.isNotEmpty) {
        await loadSession(id);
      }
    } catch (_) {
      /* stay on a blank chat */
    }
  }

  /// Start a fresh conversation. Clears the bound subject (anchored context) AND
  /// the attached context assets — a deliberately-new conversation must carry no
  /// context from the previous one.
  void reset() {
    _sessionLoadRevision++;
    _pendingSessionId = null;
    _ensureSessionFuture = null;
    _cancelActiveTurn(notify: false);
    messages.clear();
    streaming = false;
    sessionId = null;
    sessionTitle = null;
    subjectType = null;
    subjectId = null;
    contextAssets = [];
    error = null;
    _retryableUserText = null;
    _failedAgent = null;
    _reconcileRetrySessionId = null;
    _persistActive(null);
    RecentSessionStore.clear();
    _notify();
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
    final revision = ++_sessionLoadRevision;
    _pendingSessionId = null;
    _ensureSessionFuture = null;
    _cancelActiveTurn(notify: false);
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
      if (revision != _sessionLoadRevision ||
          subjectType != type ||
          subjectId != id) {
        return;
      }
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
        DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
    }).toList();
  }

  /// Delete a session (DELETE /api/sessions/{id}). Its captured assets survive
  /// (the backend detaches them); only the conversation is removed. Resets the
  /// view if the deleted session was the active one.
  Future<bool> deleteSession(String id) async {
    _deletedSessionIds.add(id);
    try {
      if (_pendingSessionId == id) {
        _sessionLoadRevision++;
        _pendingSessionId = null;
      }
      await _api.deleteJson('/api/sessions/$id');
      if (sessionId == id) reset();
      return true;
    } catch (_) {
      _deletedSessionIds.remove(id);
      return false;
    }
  }

  /// Load + replay a session's history into [messages]. [title] (when passed
  /// from the sidebar row) drives the readable header.
  Future<void> loadSession(String id, {String? title}) async {
    if (_deletedSessionIds.contains(id)) return;
    final revision = ++_sessionLoadRevision;
    _pendingSessionId = id;
    _ensureSessionFuture = null;

    late final List raw;
    try {
      final res = await _api.getJson('/api/sessions/$id/messages');
      raw = (res is Map ? res['messages'] : null) as List? ?? const [];
    } catch (_) {
      if (revision == _sessionLoadRevision) _pendingSessionId = null;
      rethrow;
    }
    if (revision != _sessionLoadRevision ||
        _pendingSessionId != id ||
        _deletedSessionIds.contains(id)) {
      return;
    }

    // Restore the attached context assets so the chip rail isn't empty after
    // reopening a history session (codex r2). Best-effort — a failure just
    // leaves no chips, same as before.
    Map? session;
    try {
      final s = await _api.getJson('/api/sessions/$id');
      session = (s is Map ? s['session'] : null) as Map?;
    } catch (_) {
      session = null;
    }
    if (revision != _sessionLoadRevision ||
        _pendingSessionId != id ||
        _deletedSessionIds.contains(id)) {
      return;
    }

    _cancelActiveTurn(notify: false);
    final restoredContexts = ((session?['context_assets'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (m) => (
            id: m['id'] as String? ?? '',
            label: m['label'] as String? ?? '资产',
          ),
        )
        .where((context) => context.id.isNotEmpty)
        .toList();
    final storedTitle = (session?['title'] as String?)?.trim();

    messages
      ..clear()
      ..addAll(_messagesFrom(raw));
    sessionId = id;
    sessionTitle =
        title ?? ((storedTitle?.isNotEmpty ?? false) ? storedTitle : null);
    contextAssets = restoredContexts;
    error = null;
    _retryableUserText = null;
    _failedAgent = null;
    _reconcileRetrySessionId = null;
    streaming = _hasPending(raw);
    _pendingSessionId = null;
    _persistActive(id);
    RecentSessionStore.save(id: id, type: 'chat');
    _notify();
    // §1.5.1.3 batch A — a turn may still be generating server-side (we left
    // mid-generation and came back). Its agent message is `running` → shown as
    // 「分析中…」; poll until it lands, then auto-render the reply/cards.
    if (_hasPending(raw)) {
      _reconcilePending(id, revision, _pendingAgentMessageIds(raw));
    }
  }

  /// Rebuild [messages] from a /messages payload. Agent messages with
  /// status='running' (§1.5.1.3) replay as a 「分析中…」 placeholder (streaming
  /// + empty parts), which the durable-turn poll later fills.
  List<ChatMessage> _messagesFrom(List raw) {
    final restored = <ChatMessage>[];
    for (final mm in raw.whereType<Map>()) {
      final m = mm.cast<String, dynamic>();
      if (m['role'] == 'user') {
        restored.add(
          ChatMessage.user(
            m['id'] as String? ?? 'u',
            m['text'] as String? ?? '',
            inputTurnId: m['input_turn_id'] as String?,
          ),
        );
      } else if (m['role'] == 'agent') {
        final status = m['status'] as String? ?? 'done';
        final running = status == 'running';
        final msg = ChatMessage.agent(
          m['id'] as String? ?? 'a',
          inputTurnId: m['input_turn_id'] as String?,
        );
        msg.streaming = running; // running → 「分析中…」 (chat_page renders it)
        if (running) msg.processingStartedAt = _now();
        _appendStoredToolCalls(msg, m['tool_call']);
        _appendStoredToolResults(msg, m['tool_result']);
        final text = m['text'] as String?;
        if (status == 'failed') {
          msg.parts.add(
            ErrorPart(text?.isNotEmpty == true ? text! : '回答失败，请重试'),
          );
          msg.text = text ?? '';
        } else if (text != null && text.isNotEmpty) {
          msg.parts.add(TextPart(text));
          msg.text = text;
        }
        final cards = m['cards'];
        if (cards is List && cards.isNotEmpty) {
          final messageCards = sessionMessageCards(cards);
          if (messageCards.isNotEmpty) {
            msg.parts.add(CardsPart(messageCards));
          }
        }
        final el = m['elapsed_ms'];
        if (el is num) msg.elapsedMs = el.toInt();
        final tokens = m['total_tokens'];
        if (tokens is num) msg.tokens = tokens.toInt();
        restored.add(msg);
      }
    }
    return restored;
  }

  void _appendStoredToolCalls(ChatMessage message, dynamic raw) {
    if (raw is! Map) return;
    final calls = raw['calls'] is List ? raw['calls'] as List : [raw];
    for (final call in calls.whereType<Map>()) {
      message.parts.add(ToolCallPart(call['name']?.toString() ?? '?'));
    }
  }

  void _appendStoredToolResults(ChatMessage message, dynamic raw) {
    if (raw is! Map) return;
    final results = raw['results'] is List ? raw['results'] as List : [raw];
    for (final result in results.whereType<Map>()) {
      message.parts.add(
        ToolResultPart(
          result['name']?.toString() ?? '?',
          (result['response'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
    }
  }

  void _applyMessages(List raw) {
    messages
      ..clear()
      ..addAll(_messagesFrom(raw));
  }

  /// Any agent turn still generating server-side?
  bool _hasPending(List raw) => raw.whereType<Map>().any(
    (m) =>
        m['role'] == 'agent' && (m['status'] as String? ?? 'done') == 'running',
  );

  /// Reconcile a session that had an in-flight turn on load: poll the message
  /// log until the running turn lands (or a timeout), then rebuild + render the
  /// reply/cards. Stops if the user switches sessions or the controller dies.
  Set<String> _pendingAgentMessageIds(List raw) => raw
      .whereType<Map>()
      .where(
        (message) =>
            message['role'] == 'agent' && message['status'] == 'running',
      )
      .map((message) => message['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();

  Future<void> _reconcilePending(
    String id,
    int revision,
    Set<String> pendingAgentIds,
  ) async {
    if (_pollingSession == id && _pollingRevision == revision) {
      return; // already polling this exact history generation
    }
    _pollingSession = id;
    _pollingRevision = revision;
    final deadline = DateTime.now().add(_reconcileTimeout);
    var settled = false;
    try {
      while (!_disposed &&
          sessionId == id &&
          revision == _sessionLoadRevision &&
          DateTime.now().isBefore(deadline)) {
        var remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        final delay = _reconcileInterval.compareTo(remaining) < 0
            ? _reconcileInterval
            : remaining;
        await Future<void>.delayed(delay);
        if (!_isCurrentReconciliation(id, revision)) break;
        remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        final res = await _api
            .getJson('/api/sessions/$id/messages')
            .timeout(remaining);
        final raw = (res is Map ? res['messages'] : null) as List? ?? const [];
        if (!_isCurrentReconciliation(id, revision)) break;
        if (!_hasPending(raw)) {
          _applyMessages(raw); // turn landed → reply + cards now present
          streaming = false;
          error = null;
          _reconcileRetrySessionId = null;
          settled = true;
          _notify();
          _publishTurnRefresh(
            messages
                .where((message) => pendingAgentIds.contains(message.id))
                .any(_messageHasConfirmedMutation),
          );
          break;
        }
      }
    } catch (_) {
      _markReconcileFailure(id, revision);
    } finally {
      if (!settled &&
          _isCurrentReconciliation(id, revision) &&
          !DateTime.now().isBefore(deadline)) {
        _markReconcileFailure(id, revision);
      }
      if (_pollingSession == id && _pollingRevision == revision) {
        _pollingSession = null;
        _pollingRevision = null;
      }
    }
  }

  bool _isCurrentReconciliation(String id, int revision) =>
      !_disposed &&
      sessionId == id &&
      revision == _sessionLoadRevision &&
      _pollingSession == id &&
      _pollingRevision == revision;

  void _markReconcileFailure(String id, int revision) {
    if (!_isCurrentReconciliation(id, revision)) return;
    for (final message in messages) {
      if (!message.isUser) message.streaming = false;
    }
    streaming = false;
    error = '会话生成状态同步失败，请重试';
    _reconcileRetrySessionId = id;
    _notify();
  }

  /// Ensure a session exists so context can be attached / a subject bound before
  /// the first message. Binds the pending subject if one is set (so the created
  /// session is the subject's thread, not an orphan blank one).
  Future<String?> ensureSession() {
    if (sessionId != null) return Future<String?>.value(sessionId);
    final pending = _ensureSessionFuture;
    if (pending != null) return pending;
    final revision = _sessionLoadRevision;
    late final Future<String?> tracked;
    tracked = _createSession(revision).whenComplete(() {
      if (identical(_ensureSessionFuture, tracked)) {
        _ensureSessionFuture = null;
      }
    });
    _ensureSessionFuture = tracked;
    return tracked;
  }

  Future<String?> _createSession(int revision) async {
    try {
      final body = <String, dynamic>{'session_type': 'chat'};
      if (subjectType != null && subjectId != null) {
        body['subject_type'] = subjectType;
        body['subject_id'] = subjectId;
      }
      final res = await _api.postJson('/api/sessions', body);
      if (_disposed || revision != _sessionLoadRevision) return sessionId;
      final created = (res is Map ? res['session_id'] : null) as String?;
      sessionId ??= created;
      return sessionId;
    } catch (_) {
      return null;
    }
  }

  /// Attach one or more assets as context to the current session in a single
  /// PATCH (web's 添加资产 flow; picker is multi-select).
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) async {
    if (assetIds.isEmpty) return true;
    final sid = await ensureSession();
    if (sid == null) return false;
    try {
      await _api.patchJson('/api/sessions/$sid/context', {'add': assetIds});
      if (sessionId != sid) return true;
      final byId = {
        for (final context in contextAssets) context.id: context.label,
      };
      for (final id in assetIds) {
        byId[id] = labels[id]?.trim().isNotEmpty == true
            ? labels[id]!.trim()
            : byId[id] ?? '资产';
      }
      contextAssets = [
        for (final entry in byId.entries) (id: entry.key, label: entry.value),
      ];
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Attach a single asset as context (convenience wrapper).
  Future<bool> attachContext(String assetId, {String? label}) => attachContexts(
    [assetId],
    labels: label == null ? const {} : {assetId: label},
  );

  /// 沉淀为资产 — resolve the Theme V2 skill id, then create a schema-valid
  /// todo or note linked to this session. Throws on failure so the UI can show it.
  Future<void> precipitate(String text, String skill) async {
    final normalized = text.trim();
    var title = normalized.replaceAll(RegExp(r'\s+'), ' ');
    if (title.length > 24) title = title.substring(0, 24);
    final payload = skill == 'todo'
        ? <String, dynamic>{'title': normalized}
        : <String, dynamic>{'title': title, 'content': normalized};
    final response = await _api.getJson('/api/user-skills');
    final rows = response is List
        ? response
        : response is Map
        ? (response['skills'] as List? ?? const [])
        : const [];
    String? userSkillId;
    for (final row in rows.whereType<Map>()) {
      if (row['machine_name'] == skill) {
        userSkillId = row['id'] as String?;
        break;
      }
    }
    if (userSkillId == null || userSkillId.isEmpty) {
      throw StateError('未找到可用的$skill容器');
    }
    await _api.postJson('/api/assets', {
      'user_skill_id': userSkillId,
      'payload': payload,
      if (sessionId case final id? when id.isNotEmpty) 'session_id': id,
    });
  }

  Future<void> send(String text) => _sendTurn(text, appendUserMessage: true);

  /// Replays the most recent failed turn without appending another user row.
  ///
  /// The failed assistant response remains in the transcript, but its obsolete
  /// error chip is removed before the retry starts. A second failure simply
  /// becomes the next retry target.
  Future<void> retryLastFailedTurn() async {
    final reconcileId = _reconcileRetrySessionId;
    if (reconcileId != null && reconcileId.isNotEmpty && !streaming) {
      try {
        await loadSession(reconcileId, title: sessionTitle);
      } catch (_) {
        if (!_disposed && sessionId == reconcileId) {
          error = '会话生成状态同步失败，请重试';
          _notify();
        }
      }
      return;
    }
    final text = _retryableUserText;
    if (text == null || text.isEmpty || streaming) return;
    _failedAgent?.parts.removeWhere((part) => part is ErrorPart);
    _failedAgent?.elapsedMs = null;
    await _sendTurn(text, appendUserMessage: false);
  }

  Future<void> _sendTurn(String text, {required bool appendUserMessage}) async {
    final t = text.trim();
    if (t.isEmpty || streaming) return;
    _sessionLoadRevision++;
    _pendingSessionId = null;
    _ensureSessionFuture = null;
    final revision = ++_turnRevision;
    error = null;
    if (appendUserMessage) {
      _retryableUserText = null;
      _failedAgent = null;
    }

    // Lazy subject binding: a discuss thread only becomes a real session now,
    // on the first message. (/api/chat has no subject param, so the bound
    // session must exist before the turn; plain chats let the backend create
    // it via the SSE `meta` frame.)
    streaming = true;
    _notify();
    if (sessionId == null && subjectType != null && subjectId != null) {
      await ensureSession();
    }
    if (revision != _turnRevision || _disposed) return;

    final stamp = DateTime.now().microsecondsSinceEpoch;
    if (appendUserMessage) messages.add(ChatMessage.user('u-$stamp', t));
    final agent = ChatMessage.agent('a-$stamp')..processingStartedAt = _now();
    messages.add(agent);
    _activeAgent = agent;
    _notify();

    final completer = Completer<void>();
    _activeTurnCompleter = completer;
    var finalized = false;
    void finalize({Object? failure}) {
      if (finalized) return;
      finalized = true;
      if (revision != _turnRevision || _disposed) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (failure != null) {
        agent.parts.add(const ErrorPart('回答暂未完成，请重试'));
        error = failure.toString();
      }
      agent.streaming = false;
      streaming = false;
      _activeTurnSubscription = null;
      _activeTurnCompleter = null;
      _activeAgent = null;
      if (error == null) {
        _retryableUserText = null;
        _failedAgent = null;
      } else {
        _retryableUserText = t;
        _failedAgent = agent;
      }
      _notify();
      _publishTurnRefresh(_messageHasConfirmedMutation(agent));
      if (!completer.isCompleted) completer.complete();
    }

    try {
      final stream = _turnStream('/api/chat', {
        'user_text': t,
        'session_id': sessionId ?? '',
      });
      late final StreamSubscription<SseEvent> subscription;
      subscription = stream.listen(
        (event) {
          if (revision != _turnRevision || _disposed) return;
          _apply(agent, event);
          _notify();
        },
        onError: (Object failure, StackTrace _) => finalize(failure: failure),
        onDone: finalize,
        cancelOnError: true,
      );
      if (revision != _turnRevision || _disposed) {
        unawaited(subscription.cancel());
        finalize();
      } else {
        _activeTurnSubscription = subscription;
      }
    } catch (e) {
      finalize(failure: e);
    }
    await completer.future;
  }

  bool _messageHasConfirmedMutation(ChatMessage message) =>
      message.parts.whereType<ToolResultPart>().any(
        (part) =>
            _isConfirmedPersistedMutationToolResult(part.name, part.response),
      );

  void _publishTurnRefresh(bool hasConfirmedMutation) {
    if (hasConfirmedMutation) {
      bumpData();
    } else {
      requestDataRefresh();
    }
  }

  void _cancelActiveTurn({required bool notify}) {
    _turnRevision++;
    final subscription = _activeTurnSubscription;
    _activeTurnSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final agent = _activeAgent;
    _activeAgent = null;
    if (agent != null) agent.streaming = false;
    final completer = _activeTurnCompleter;
    _activeTurnCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (subscription != null || agent != null) {
      streaming = false;
      if (notify) _notify();
    }
  }

  void _apply(ChatMessage agent, SseEvent ev) {
    switch (ev.type) {
      case 'meta':
        agent.advanceWorkPhase(AgentWorkPhase.understanding);
        final sid = ev.json['session_id'];
        if (sid is String && sid.isNotEmpty) {
          sessionId = sid;
          _persistActive(
            sid,
          ); // a new lazily-created session becomes the active one
          RecentSessionStore.save(id: sid, type: 'chat');
        }
        final inputTurnId = ev.json['input_turn_id'];
        if (inputTurnId is String && inputTurnId.isNotEmpty) {
          agent.inputTurnId = inputTurnId;
          for (final message in messages.reversed) {
            if (message.isUser && message.inputTurnId == null) {
              message.inputTurnId = inputTurnId;
              break;
            }
          }
        }
      case 'token':
        agent.advanceWorkPhase(AgentWorkPhase.composing);
        final txt = ev.json['text'];
        if (txt is String && txt.isNotEmpty) _mergeText(agent, txt);
      case 'tool_call':
        agent.advanceWorkPhase(AgentWorkPhase.executing);
        agent.parts.add(ToolCallPart(ev.json['name'] as String? ?? '?'));
      case 'tool_result':
        agent.advanceWorkPhase(AgentWorkPhase.executing);
        final resp =
            (ev.json['response'] as Map?)?.cast<String, dynamic>() ?? {};
        agent.parts.add(
          ToolResultPart(ev.json['name'] as String? ?? '?', resp),
        );
      case 'error':
        final message = ev.json['message'] as String? ?? 'stream error';
        agent.parts.add(const ErrorPart('回答暂未完成，请重试'));
        final elapsed = ev.json['elapsed_ms'];
        if (elapsed is num) agent.elapsedMs = elapsed.toInt();
        error = message;
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
