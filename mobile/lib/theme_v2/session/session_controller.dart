import 'package:flutter/foundation.dart';

import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';

/// Testable contract between the Theme V2 view and a session workflow.
abstract interface class ThemeV2SessionController implements Listenable {
  List<ChatMessage> get messages;
  bool get streaming;
  String? get error;
  String? get sessionId;
  String get displayTitle;
  List<({String id, String label})> get contextAssets;

  Future<void> resumeLast();
  Future<void> bindSubject(String type, String id);
  Future<void> loadSession(String id, {String? title});
  Future<List<SessionInfo>> listSessions();
  Future<bool> deleteSession(String id);
  Future<void> send(String text);
  Future<void> retryLastFailedTurn();
  Future<void> precipitate(String text, String skill);
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels,
  });
  void reset();
}

/// Marker for controllers backed by the daily Flash workflow. The Session
/// surface uses it to keep Flash as the active source while still presenting
/// the product-wide unified archive.
abstract interface class FlashSessionWorkflow {}

/// Supplies a product-specific turn count when visible messages and the
/// product count differ. Daily Flash counts hardware recordings only.
abstract interface class SessionTurnCountSource {
  int get sessionTurnCount;
}

class ChatControllerSessionAdapter extends ChangeNotifier
    implements ThemeV2SessionController {
  ChatControllerSessionAdapter(this.chat, {this.ownsChat = false}) {
    chat.addListener(_forward);
  }

  final ChatController chat;
  final bool ownsChat;
  var _disposed = false;

  void _forward() {
    if (!_disposed) notifyListeners();
  }

  @override
  List<ChatMessage> get messages => chat.messages;

  @override
  bool get streaming => chat.streaming;

  @override
  String? get error => chat.error;

  @override
  String? get sessionId => chat.sessionId;

  @override
  String get displayTitle => chat.displayTitle;

  @override
  List<({String id, String label})> get contextAssets => chat.contextAssets;

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) => chat.attachContexts(assetIds, labels: labels);

  @override
  Future<void> bindSubject(String type, String id) =>
      chat.bindSubject(type, id);

  @override
  Future<bool> deleteSession(String id) => chat.deleteSession(id);

  @override
  Future<void> loadSession(String id, {String? title}) =>
      chat.loadSession(id, title: title);

  @override
  Future<List<SessionInfo>> listSessions() => chat.listSessions();

  @override
  Future<void> precipitate(String text, String skill) =>
      chat.precipitate(text, skill);

  @override
  void reset() => chat.reset();

  @override
  Future<void> resumeLast() => chat.resumeLast();

  @override
  Future<void> retryLastFailedTurn() => chat.retryLastFailedTurn();

  @override
  Future<void> send(String text) => chat.send(text);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    chat.removeListener(_forward);
    if (ownsChat) chat.dispose();
    super.dispose();
  }
}
