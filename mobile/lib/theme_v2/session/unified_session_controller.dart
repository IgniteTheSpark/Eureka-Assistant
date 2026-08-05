import 'package:flutter/foundation.dart';

import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import '../capture/capture_session_controller.dart';
import 'session_controller.dart';

enum UnifiedSessionSource { chat, flash }

/// Presents ordinary agent chats and daily Flash sessions as one archive while
/// preserving their separate, established API workflows.
class UnifiedSessionController extends ChangeNotifier
    implements ThemeV2SessionController {
  UnifiedSessionController({
    ThemeV2SessionController? chatController,
    ThemeV2SessionController? flashController,
    this.ownsChatController = true,
    this.ownsFlashController = true,
    UnifiedSessionSource initialSource = UnifiedSessionSource.chat,
  }) : _chatController =
           chatController ??
           ChatControllerSessionAdapter(ChatController(), ownsChat: true),
       _flashController = flashController ?? CaptureSessionController(),
       _activeSource = initialSource {
    _chatController.addListener(_onChatChanged);
    _flashController.addListener(_onFlashChanged);
  }

  final ThemeV2SessionController _chatController;
  final ThemeV2SessionController _flashController;
  final bool ownsChatController;
  final bool ownsFlashController;
  final Map<String, UnifiedSessionSource> _sourceBySessionId = {};
  UnifiedSessionSource _activeSource;
  var _disposed = false;

  ThemeV2SessionController get _activeController =>
      _activeSource == UnifiedSessionSource.chat
      ? _chatController
      : _flashController;

  void _onChatChanged() {
    if (_activeSource == UnifiedSessionSource.chat) _notify();
  }

  void _onFlashChanged() {
    if (_activeSource == UnifiedSessionSource.flash) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _activate(UnifiedSessionSource source) {
    if (_activeSource == source) return;
    _activeSource = source;
    _notify();
  }

  UnifiedSessionSource _sourceFor(String id) {
    return _sourceBySessionId[id] ?? _activeSource;
  }

  @override
  List<ChatMessage> get messages => _activeController.messages;

  @override
  bool get streaming => _activeController.streaming;

  @override
  String? get error => _activeController.error;

  @override
  String? get sessionId => _activeController.sessionId;

  @override
  String get displayTitle => _activeController.displayTitle;

  @override
  List<({String id, String label})> get contextAssets =>
      _activeController.contextAssets;

  @override
  Future<List<SessionInfo>> listSessions() async {
    final results = await Future.wait([
      _chatController.listSessions(),
      _flashController.listSessions(),
    ]);
    final chatSessions = results[0];
    final flashSessions = results[1];
    for (final session in chatSessions) {
      _sourceBySessionId[session.id] = UnifiedSessionSource.chat;
    }
    for (final session in flashSessions) {
      _sourceBySessionId[session.id] = UnifiedSessionSource.flash;
    }
    // Physical daily Flash Sessions now also appear in /api/sessions. Prefer
    // the Flash adapter for the shared UUID until its compatibility surface is
    // fully retired, and never show the same Session twice in history.
    final byId = <String, SessionInfo>{
      for (final session in chatSessions) session.id: session,
      for (final session in flashSessions) session.id: session,
    };
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> loadSession(String id, {String? title}) async {
    final previousSource = _activeSource;
    final source = _sourceFor(id);
    _activate(source);
    try {
      await _activeController.loadSession(id, title: title);
    } catch (_) {
      _activate(previousSource);
      rethrow;
    }
  }

  @override
  Future<bool> deleteSession(String id) async {
    final source = _sourceFor(id);
    final controller = source == UnifiedSessionSource.chat
        ? _chatController
        : _flashController;
    final deleted = await controller.deleteSession(id);
    if (deleted) _sourceBySessionId.remove(id);
    return deleted;
  }

  @override
  Future<void> send(String text) => _activeController.send(text);

  @override
  Future<void> retryLastFailedTurn() => _activeController.retryLastFailedTurn();

  @override
  Future<void> precipitate(String text, String skill) =>
      _activeController.precipitate(text, skill);

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) => _activeController.attachContexts(assetIds, labels: labels);

  @override
  Future<void> resumeLast() async {
    _activate(UnifiedSessionSource.chat);
    await _chatController.resumeLast();
  }

  @override
  Future<void> bindSubject(String type, String id) async {
    _activate(UnifiedSessionSource.chat);
    await _chatController.bindSubject(type, id);
  }

  @override
  void reset() {
    _activate(UnifiedSessionSource.chat);
    _chatController.reset();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _chatController.removeListener(_onChatChanged);
    _flashController.removeListener(_onFlashChanged);
    if (ownsChatController && _chatController is ChangeNotifier) {
      (_chatController as ChangeNotifier).dispose();
    }
    if (ownsFlashController && _flashController is ChangeNotifier) {
      (_flashController as ChangeNotifier).dispose();
    }
    super.dispose();
  }
}
