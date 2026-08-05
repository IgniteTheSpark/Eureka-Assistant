import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:eureka/theme_v2/session/unified_session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'history merges chat and flash sessions in newest-first order',
    () async {
      final chat = _FakeSessionController(
        sessions: [SessionInfo('chat-1', '产品讨论', DateTime(2026, 8, 4, 20))],
      );
      final flash = _FakeSessionController(
        sessions: [
          SessionInfo('2026-08-05', '8月5日 闪念', DateTime(2026, 8, 5, 9)),
        ],
      );
      final controller = UnifiedSessionController(
        chatController: chat,
        flashController: flash,
        ownsChatController: false,
        ownsFlashController: false,
      );

      final sessions = await controller.listSessions();

      expect(sessions.map((session) => session.id), ['2026-08-05', 'chat-1']);
      controller.dispose();
    },
  );

  test(
    'opening a merged flash session routes subsequent chat and delete',
    () async {
      final chat = _FakeSessionController(
        sessions: [SessionInfo('chat-1', '产品讨论', DateTime(2026, 8, 4))],
      );
      final flash = _FakeSessionController(
        sessions: [SessionInfo('2026-08-05', '8月5日 闪念', DateTime(2026, 8, 5))],
      );
      final controller = UnifiedSessionController(
        chatController: chat,
        flashController: flash,
        ownsChatController: false,
        ownsFlashController: false,
      );
      await controller.listSessions();

      await controller.loadSession('2026-08-05', title: '8月5日 闪念');
      await controller.send('继续分析');
      final deleted = await controller.deleteSession('2026-08-05');

      expect(flash.loadedIds, ['2026-08-05']);
      expect(flash.sentTexts, ['继续分析']);
      expect(flash.deletedIds, ['2026-08-05']);
      expect(chat.loadedIds, isEmpty);
      expect(chat.sentTexts, isEmpty);
      expect(deleted, isTrue);
      controller.dispose();
    },
  );

  test('physical flash session appears once and keeps flash routing', () async {
    final physical = SessionInfo(
      'physical-flash-1',
      '8月5日 闪念',
      DateTime(2026, 8, 5),
    );
    final chat = _FakeSessionController(sessions: [physical]);
    final flash = _FakeSessionController(sessions: [physical]);
    final controller = UnifiedSessionController(
      chatController: chat,
      flashController: flash,
      ownsChatController: false,
      ownsFlashController: false,
    );

    final history = await controller.listSessions();
    await controller.loadSession(physical.id);

    expect(history.map((item) => item.id), [physical.id]);
    expect(flash.loadedIds, [physical.id]);
    expect(chat.loadedIds, isEmpty);
    controller.dispose();
  });

  test('a capture entry loads directly through the flash workflow', () async {
    final chat = _FakeSessionController();
    final flash = _FakeSessionController();
    final controller = UnifiedSessionController(
      chatController: chat,
      flashController: flash,
      ownsChatController: false,
      ownsFlashController: false,
      initialSource: UnifiedSessionSource.flash,
    );

    await controller.loadSession('recording-uuid');

    expect(flash.loadedIds, ['recording-uuid']);
    expect(chat.loadedIds, isEmpty);
    controller.dispose();
  });

  test('new conversation returns to the ordinary chat workflow', () async {
    final chat = _FakeSessionController();
    final flash = _FakeSessionController();
    final controller = UnifiedSessionController(
      chatController: chat,
      flashController: flash,
      ownsChatController: false,
      ownsFlashController: false,
      initialSource: UnifiedSessionSource.flash,
    );

    controller.reset();
    await controller.send('一个全新的问题');

    expect(chat.resetCount, 1);
    expect(chat.sentTexts, ['一个全新的问题']);
    expect(flash.sentTexts, isEmpty);
    controller.dispose();
  });
}

class _FakeSessionController extends ChangeNotifier
    implements ThemeV2SessionController {
  _FakeSessionController({this.sessions = const []});

  final List<SessionInfo> sessions;
  final List<String> loadedIds = [];
  final List<String> sentTexts = [];
  final List<String> deletedIds = [];
  int resetCount = 0;

  @override
  final List<ChatMessage> messages = [];

  @override
  bool streaming = false;

  @override
  String? error;

  @override
  String? sessionId;

  @override
  String get displayTitle => sessionId ?? '新对话';

  @override
  List<({String id, String label})> get contextAssets => const [];

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) async => true;

  @override
  Future<void> bindSubject(String type, String id) async {}

  @override
  Future<bool> deleteSession(String id) async {
    deletedIds.add(id);
    return true;
  }

  @override
  Future<void> loadSession(String id, {String? title}) async {
    loadedIds.add(id);
    sessionId = id;
    notifyListeners();
  }

  @override
  Future<List<SessionInfo>> listSessions() async => sessions;

  @override
  Future<void> precipitate(String text, String skill) async {}

  @override
  void reset() {
    resetCount += 1;
    sessionId = null;
    messages.clear();
    notifyListeners();
  }

  @override
  Future<void> resumeLast() async {}

  @override
  Future<void> retryLastFailedTurn() async {}

  @override
  Future<void> send(String text) async {
    sentTexts.add(text);
  }
}
