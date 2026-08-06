import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme_v2/capture/capture_session_page.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new chat leaves flash workflow for a fresh agent session', (
    tester,
  ) async {
    final controller = _FakeCaptureController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CaptureSessionPage(
          recordingId: 'recording-1',
          controller: controller,
          newConversationBuilder: (_) =>
              const Scaffold(body: Text('fresh generic agent session')),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('新会话'));
    await tester.pumpAndSettle();

    expect(find.text('fresh generic agent session'), findsOneWidget);
    expect(controller.resetCount, 0);
  });
}

class _FakeCaptureController extends ChangeNotifier
    implements ThemeV2SessionController {
  var resetCount = 0;

  @override
  List<ChatMessage> get messages => const [];

  @override
  bool get streaming => false;

  @override
  String? get error => null;

  @override
  String? get sessionId => '2026-08-04';

  @override
  String get displayTitle => '8月4日 闪念';

  @override
  List<({String id, String label})> get contextAssets => const [];

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) async => false;

  @override
  Future<void> bindSubject(String type, String id) async {}

  @override
  Future<bool> deleteSession(String id) async => false;

  @override
  Future<void> loadSession(String id, {String? title}) async {}

  @override
  Future<List<SessionInfo>> listSessions() async => const [];

  @override
  Future<void> precipitate(String text, String skill) async {}

  @override
  void reset() => resetCount++;

  @override
  Future<void> resumeLast() async {}

  @override
  Future<void> retryLastFailedTurn() async {}

  @override
  Future<void> send(String text) async {}
}
