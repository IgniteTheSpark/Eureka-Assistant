import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';
import '../../chat/chat_models.dart';
import '../session/session_controller.dart';
import '../session/session_invalidation.dart';

/// Adapter that projects Theme V2 capture recordings onto the
/// established Session transcript surface.
///
/// Theme V2 persists hardware/typed flashes as CaptureRecording + CaptureTurn,
/// not as legacy chat sessions. Keeping that distinction here avoids inventing
/// a second session store while still letting notification recipients replay
/// the exact transcript, organization summary, and derived records.
class CaptureSessionController extends ChangeNotifier
    implements ThemeV2SessionController, FlashSessionWorkflow {
  CaptureSessionController({
    ApiClient? api,
    ValueListenable<SessionInvalidation?>? invalidations,
    Duration invalidationDebounce = const Duration(milliseconds: 200),
  }) : _api = api ?? ApiClient(),
       _ownsApi = api == null,
       _invalidations = invalidations ?? SessionInvalidations.instance,
       _invalidationDebounce = invalidationDebounce {
    _invalidations.addListener(_onInvalidation);
  }

  final ApiClient _api;
  final bool _ownsApi;
  final ValueListenable<SessionInvalidation?> _invalidations;
  final Duration _invalidationDebounce;

  @override
  final List<ChatMessage> messages = [];

  @override
  bool streaming = false;

  @override
  String? error;

  @override
  String? sessionId;

  DateTime? _createdAt;
  String? _retryRecordingId;
  String? _physicalSessionId;
  String? _sessionDate;
  int _sessionRevision = 0;
  Timer? _invalidationTimer;
  final Map<String, String> _dateByPhysicalSessionId = {};
  var _loadRevision = 0;
  var _disposed = false;

  @override
  String get displayTitle {
    final createdAt = _createdAt;
    return createdAt == null ? '闪念' : '${createdAt.month}月${createdAt.day}日 闪念';
  }

  @override
  List<({String id, String label})> get contextAssets => const [];

  @override
  Future<void> loadSession(String id, {String? title}) async {
    await _loadSession(id, title: title, background: false);
  }

  Future<void> _loadSession(
    String id, {
    String? title,
    required bool background,
  }) async {
    final revision = ++_loadRevision;
    if (!background) {
      _invalidationTimer?.cancel();
      streaming = true;
      error = null;
      _notify();
    }
    try {
      Map<String, dynamic>? linkedRecording;
      var sessionDate = _isSessionDate(id)
          ? id
          : _dateByPhysicalSessionId[id] ?? '';
      if (sessionDate.isEmpty) {
        final response = await _api.getJson('/api/flash/recordings/$id');
        linkedRecording = ((response as Map)['recording'] as Map?)
            ?.cast<String, dynamic>();
        if (linkedRecording == null) {
          throw const FormatException('闪念详情格式不正确');
        }
        sessionDate = linkedRecording['session_date']?.toString().trim() ?? '';
        if (sessionDate.isEmpty) {
          final createdAt = DateTime.tryParse(
            linkedRecording['created_at']?.toString() ?? '',
          )?.toLocal();
          if (createdAt != null) {
            sessionDate = _dateKey(createdAt);
          }
        }
      }
      if (sessionDate.isEmpty) {
        throw const FormatException('闪念日期格式不正确');
      }
      Map<String, dynamic> dailySession;
      try {
        final dailyResponse = await _api.getJson(
          '/api/flash/sessions/$sessionDate',
        );
        dailySession =
            ((dailyResponse as Map)['session'] as Map?)
                ?.cast<String, dynamic>() ??
            const {};
      } on ApiException catch (exception) {
        if (exception.statusCode != 404 || linkedRecording == null) rethrow;
        dailySession = {
          'id': sessionDate,
          'date': sessionDate,
          'recordings': [linkedRecording],
        };
      }
      final recordings = (dailySession['recordings'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      if (recordings.isEmpty) {
        throw const FormatException('闪念 Session 没有内容');
      }
      final nextMessages = <ChatMessage>[];
      var hasPending = false;
      String? nextError;
      String? retryRecordingId;
      for (final recording in recordings) {
        final recordingId = recording['id']?.toString() ?? '';
        final references = ((recording['result_cards'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
        final cards = await Future.wait(references.map(_hydrateReference));
        final transcript = recording['asr_text']?.toString().trim() ?? '';
        final summary = recording['result_summary']?.toString().trim() ?? '';
        final inputTurnId = recording['input_turn_id']?.toString();
        final status = recording['process_status']?.toString() ?? '';
        if (transcript.isNotEmpty) {
          nextMessages.add(
            ChatMessage.user(
              'capture-$recordingId-user',
              transcript,
              inputTurnId: inputTurnId,
            ),
          );
        }
        if (summary.isNotEmpty || cards.isNotEmpty) {
          final agent = ChatMessage.agent(
            'capture-$recordingId-agent',
            inputTurnId: inputTurnId,
          )..streaming = false;
          if (summary.isNotEmpty) {
            agent
              ..text = summary
              ..parts.add(TextPart(summary));
          }
          if (cards.isNotEmpty) agent.parts.add(CardsPart(cards));
          nextMessages.add(agent);
        }
        hasPending =
            hasPending || !const {'done', 'empty', 'failed'}.contains(status);
        if (status == 'failed') {
          retryRecordingId = recordingId;
          nextError =
              recording['error_message']?.toString().trim().isNotEmpty == true
              ? recording['error_message'].toString().trim()
              : '闪念整理失败';
        }
      }
      final chatMessages = (dailySession['chat_messages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>());
      for (final item in chatMessages) {
        final id = item['id']?.toString() ?? '';
        final text = item['text']?.toString().trim() ?? '';
        if (id.isEmpty || text.isEmpty) continue;
        if (item['role'] == 'user') {
          nextMessages.add(ChatMessage.user(id, text, inputTurnId: id));
        } else {
          final agent = ChatMessage.agent(id)
            ..streaming = false
            ..text = text;
          agent.parts.add(TextPart(text));
          if (item['status'] == 'failed') {
            agent.parts.add(const ErrorPart('回答失败，请重试'));
          }
          nextMessages.add(agent);
        }
      }
      if (_disposed || revision != _loadRevision) return;
      messages
        ..clear()
        ..addAll(nextMessages);
      sessionId = sessionDate;
      _sessionDate = sessionDate;
      _physicalSessionId =
          dailySession['physical_session_id']?.toString().trim().isNotEmpty ==
              true
          ? dailySession['physical_session_id'].toString().trim()
          : linkedRecording?['physical_session_id']?.toString().trim();
      final rawSessionRevision = dailySession['session_revision'];
      _sessionRevision = rawSessionRevision is num
          ? rawSessionRevision.toInt()
          : int.tryParse(rawSessionRevision?.toString() ?? '') ??
                _sessionRevision;
      _createdAt = DateTime.tryParse(sessionDate);
      _retryRecordingId = retryRecordingId;
      streaming = hasPending;
      error = nextError;
      _notify();
    } on ApiException catch (exception) {
      if (_disposed || revision != _loadRevision) return;
      if (background) return;
      streaming = false;
      error = exception.statusCode == 404 ? '这条闪念不存在或已失效' : '闪念加载失败，请稍后重试';
      _notify();
      rethrow;
    } catch (_) {
      if (_disposed || revision != _loadRevision) return;
      if (background) return;
      streaming = false;
      error = '闪念加载失败，请稍后重试';
      _notify();
      rethrow;
    }
  }

  void _onInvalidation() {
    if (_disposed) return;
    final event = _invalidations.value;
    if (event == null || event.revision <= _sessionRevision) return;
    final physicalMatch =
        _physicalSessionId != null && event.sessionId == _physicalSessionId;
    final dateMatch =
        _sessionDate != null &&
        event.sessionDate.isNotEmpty &&
        event.sessionDate == _sessionDate;
    if (!physicalMatch && !dateMatch) return;
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_invalidationDebounce, () {
      final activeDate = _sessionDate;
      if (_disposed || activeDate == null) return;
      unawaited(_loadSession(activeDate, background: true));
    });
  }

  bool _isSessionDate(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _hydrateReference(
    Map<String, dynamic> reference,
  ) async {
    final kind = reference['kind']?.toString();
    try {
      if (kind == 'event') {
        final id = reference['event_id']?.toString() ?? '';
        if (id.isEmpty) return _fallbackCard(reference);
        final event = (await _api.getJson('/api/events/$id') as Map)
            .cast<String, dynamic>();
        return {
          ...event,
          ...reference,
          'event_id': id,
          'card_type': 'event',
          'core_records_only': true,
        };
      }
      if (kind == 'asset') {
        final id = reference['asset_id']?.toString() ?? '';
        if (id.isEmpty) return _fallbackCard(reference);
        final asset = (await _api.getJson('/api/assets/$id') as Map)
            .cast<String, dynamic>();
        final skill = reference['skill_machine_name']?.toString() ?? 'asset';
        return {
          ...asset,
          ...reference,
          'asset_id': id,
          'card_type': skill,
          'user_skill_name': skill,
          'core_records_only': true,
        };
      }
    } catch (_) {
      // A derived record may have been deleted after the capture. The session
      // itself still replays, with a stable reference card for provenance.
    }
    return _fallbackCard(reference);
  }

  Map<String, dynamic> _fallbackCard(Map<String, dynamic> reference) {
    final event = reference['kind'] == 'event';
    final skill = reference['skill_machine_name']?.toString() ?? 'asset';
    return {
      ...reference,
      'card_type': event ? 'event' : skill,
      if (!event) 'user_skill_name': skill,
      'core_records_only': true,
    };
  }

  @override
  Future<void> retryLastFailedTurn() async {
    final id = _retryRecordingId;
    if (id == null || id.isEmpty) return;
    await _api.postJson('/api/flash/recordings/$id/retry', const {});
    await loadSession(sessionId ?? id);
  }

  @override
  Future<void> resumeLast() async {}

  @override
  Future<void> bindSubject(String type, String id) async {}

  @override
  Future<List<SessionInfo>> listSessions() async {
    final response = await _api.getJson('/api/flash/sessions');
    final raw = response is Map
        ? response['sessions'] as List? ?? const []
        : response is List
        ? response
        : const [];
    return raw
        .whereType<Map>()
        .map((value) {
          final recording = value.cast<String, dynamic>();
          final date =
              recording['date']?.toString().trim() ??
              recording['id']?.toString().trim() ??
              '';
          final physicalId =
              recording['physical_session_id']?.toString().trim() ?? '';
          if (physicalId.isNotEmpty && date.isNotEmpty) {
            _dateByPhysicalSessionId[physicalId] = date;
          }
          final createdAt =
              DateTime.tryParse(
                recording['created_at']?.toString() ??
                    recording['date']?.toString() ??
                    '',
              )?.toLocal() ??
              DateTime.now();
          final declaredTitle = recording['title']?.toString().trim() ?? '';
          return SessionInfo(
            physicalId.isNotEmpty ? physicalId : date,
            declaredTitle.isEmpty
                ? '${createdAt.month}月${createdAt.day}日 闪念'
                : declaredTitle,
            createdAt,
          );
        })
        .where((session) => session.id.isNotEmpty)
        .toList();
  }

  @override
  Future<bool> deleteSession(String id) async {
    try {
      final date = _dateByPhysicalSessionId[id] ?? id;
      await _api.deleteJson('/api/flash/sessions/$date');
      _dateByPhysicalSessionId.remove(id);
      if (sessionId == date) reset();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> send(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty || streaming) return;
    final parentSessionId = sessionId;
    if (parentSessionId == null || !_isSessionDate(parentSessionId)) {
      error = '请先打开一个闪念 Session';
      _notify();
      return;
    }
    final localId = 'flash-chat-${DateTime.now().microsecondsSinceEpoch}';
    final userMessage = ChatMessage.user(localId, normalized);
    messages.add(userMessage);
    streaming = true;
    error = null;
    _notify();
    try {
      final response = await _api.postJson(
        '/api/flash/sessions/$parentSessionId/chat',
        {'user_text': normalized},
      );
      final body = (response as Map).cast<String, dynamic>();
      final reply = body['reply']?.toString().trim() ?? '';
      if (reply.isEmpty) {
        throw const FormatException('闪念问答响应格式不正确');
      }
      userMessage.inputTurnId = body['input_turn_id']?.toString();
      final agent =
          ChatMessage.agent(
              body['message_id']?.toString() ?? '$localId-agent',
              inputTurnId: userMessage.inputTurnId,
            )
            ..streaming = false
            ..text = reply;
      agent.parts.add(TextPart(reply));
      messages.add(agent);
      streaming = false;
      error = null;
      _notify();
    } catch (_) {
      streaming = false;
      error = '发送失败，请稍后重试';
      _notify();
    }
  }

  @override
  Future<void> precipitate(String text, String skill) async {}

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) async => false;

  @override
  void reset() {
    _loadRevision++;
    messages.clear();
    sessionId = null;
    _createdAt = null;
    _retryRecordingId = null;
    _physicalSessionId = null;
    _sessionDate = null;
    _sessionRevision = 0;
    _invalidationTimer?.cancel();
    streaming = false;
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadRevision++;
    _invalidationTimer?.cancel();
    _invalidations.removeListener(_onInvalidation);
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
