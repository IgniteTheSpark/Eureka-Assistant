import 'dart:async';

import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/pages/chat_page.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/session/session_history_drawer.dart';
import 'package:eureka/theme_v2/session/session_transcript.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionViewState mapping', () {
    test('maps the explicit state priority', () {
      expect(
        SessionViewState.resolve(
          messages: const [],
          streaming: false,
          error: null,
          historyOpen: false,
        ).surface,
        SessionSurfaceState.empty,
      );
      expect(
        SessionViewState.resolve(
          messages: [_assistant('ready')],
          streaming: false,
          error: null,
          historyOpen: false,
        ).surface,
        SessionSurfaceState.loaded,
      );
      expect(
        SessionViewState.resolve(
          messages: [_assistant('partial', streaming: true)],
          streaming: true,
          error: null,
          historyOpen: false,
        ).surface,
        SessionSurfaceState.analyzing,
      );
      expect(
        SessionViewState.resolve(
          messages: [_assistant('partial')],
          streaming: false,
          error: 'failed',
          historyOpen: false,
        ).surface,
        SessionSurfaceState.error,
      );
      expect(
        SessionViewState.resolve(
          messages: [_assistant('partial')],
          streaming: true,
          error: 'failed',
          historyOpen: true,
        ).surface,
        SessionSurfaceState.history,
      );
    });
  });

  testWidgets('renders mature transcript parts and never mounts shell chrome', (
    tester,
  ) async {
    final controller = FakeSessionController(
      messages: [
        ChatMessage.user('u1', '创建日程'),
        _assistant(
          '**已完成**',
          parts: [
            const TextPart('**已完成**'),
            CardsPart([
              {
                'id': 'asset-1',
                'user_skill_name': 'todo',
                'payload': {'title': '提交设计'},
              },
            ]),
          ],
        ),
      ],
    );

    await _pumpSession(tester, controller: controller);

    expect(find.byType(SkillCard), findsOneWidget);
    expect(find.byKey(const ValueKey('session-transcript')), findsOneWidget);
    final assistantText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => widget.text.toPlainText().contains('已完成'));
    expect(assistantText.text.style?.fontFamily, 'Geist');
    expect(find.byType(ThemeV2FloatingDock), findsNothing);
    expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
    expect(
      Theme.of(
        tester.element(find.byType(ThemeV2SessionPage)),
      ).extension<ThemeV2Tokens>(),
      isNotNull,
    );
  });

  testWidgets(
    'error keeps transcript visible and retry uses controller contract',
    (tester) async {
      final controller = FakeSessionController(
        messages: [ChatMessage.user('u1', '整理录音'), _assistant('已读取录音')],
        error: '录音不可访问',
      );
      await _pumpSession(tester, controller: controller);

      expect(find.text('整理录音'), findsOneWidget);
      expect(find.text('整理中断'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('session-retry')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('重试最近失败的消息'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session-retry')));
      await tester.pump();

      expect(controller.retryCount, 1);
      expect(
        controller.messages.where((message) => message.isUser),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'history is at most 304 wide and supports retry/new/load/delete',
    (tester) async {
      final controller = FakeSessionController(
        messages: [ChatMessage.user('u1', '现有消息')],
        sessions: [SessionInfo('s1', '7月23日 闪念', DateTime(2026, 7, 23))],
      );
      await _pumpSession(
        tester,
        controller: controller,
        size: const Size(280, 720),
      );

      await tester.tap(find.bySemanticsLabel('历史会话'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionHistoryDrawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SessionHistoryDrawer),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      expect(find.text('搜索'), findsNothing);
      expect(
        tester.getSize(find.byType(SessionHistoryDrawer)).width,
        lessThanOrEqualTo(240),
      );

      await tester.tap(find.text('7月23日 闪念'));
      await tester.pumpAndSettle();
      expect(controller.loadedSessionIds, ['s1']);

      await tester.tap(find.bySemanticsLabel('历史会话'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SessionHistoryDrawer),
          matching: find.text('新会话'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.resetCount, 1);
    },
  );

  testWidgets('history error retries and delete preserves asset semantics', (
    tester,
  ) async {
    final controller = FakeSessionController(
      sessions: [SessionInfo('s1', '待删除会话', DateTime(2026, 7, 23))],
      listFailuresRemaining: 1,
    );
    await _pumpSession(tester, controller: controller);
    await tester.tap(find.bySemanticsLabel('历史会话'));
    await tester.pumpAndSettle();

    expect(find.text('历史会话加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('待删除会话'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('删除 待删除会话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('产生的资产会保留'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(controller.sessions, isEmpty);
  });

  testWidgets('theme changes preserve controller, transcript and draft', (
    tester,
  ) async {
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    final controller = FakeSessionController(
      messages: [ChatMessage.user('u1', '不会丢失')],
      streaming: true,
    );

    await _pumpSession(tester, controller: controller, brightness: brightness);
    await tester.enterText(
      find.byKey(const ValueKey('session-composer-field')),
      '保留草稿',
    );

    brightness.value = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('不会丢失'), findsOneWidget);
    expect(find.text('保留草稿'), findsOneWidget);
    expect(controller.streaming, isTrue);
    expect(
      ThemeV2Tokens.of(
        tester.element(find.byKey(const ValueKey('session-composer-field'))),
      ).background,
      ThemeV2Tokens.dark.background,
    );
  });

  testWidgets('header controls expose explicit 44px semantics', (tester) async {
    final controller = FakeSessionController();
    await _pumpSession(tester, controller: controller);

    for (final label in ['返回', '新会话', '历史会话']) {
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('sending dismisses the keyboard before the request completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    final controller = FakeSessionController(sendCompleter: pending);
    await _pumpSession(tester, controller: controller);

    final field = find.byKey(const ValueKey('session-composer-field'));
    await tester.tap(field);
    await tester.enterText(field, '今天有什么待办？');
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('session-send')));
    await tester.pump();

    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    pending.complete();
    await tester.pump();
  });

  testWidgets('header and watermark count user turns instead of messages', (
    tester,
  ) async {
    final messages = <ChatMessage>[];
    for (var index = 0; index < 6; index++) {
      messages
        ..add(ChatMessage.user('u-$index', '第 ${index + 1} 次输入'))
        ..add(_assistant('第 ${index + 1} 次回复', streaming: index == 5));
    }
    await _pumpSession(
      tester,
      controller: FakeSessionController(messages: messages, streaming: true),
    );

    expect(find.text('06'), findsNWidgets(2));
    expect(find.text('12'), findsNothing);
  });

  testWidgets('transcript actions expose 44px button targets', (tester) async {
    final message = _assistant(
      '这是一段足够长、可以沉淀为资产的回复内容',
      parts: [
        const ToolResultPart('tool_query_asset', {
          'assets': [
            {
              'asset_id': 'asset-1',
              'user_skill_name': 'notes',
              'payload': {'title': '查询结果'},
            },
          ],
        }),
        const TextPart('这是一段足够长、可以沉淀为资产的回复内容'),
      ],
    );
    await _pumpSession(
      tester,
      controller: FakeSessionController(messages: [message]),
    );

    for (final label in ['查询资产 · 找到 1 项', '沉淀为资产']) {
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
  });

  testWidgets('token-only transcript growth follows the bottom', (
    tester,
  ) async {
    final messages = [
      for (var i = 0; i < 18; i++) _assistant('第 $i 条较长的历史回复，用来制造可滚动的会话内容。'),
    ];
    final streaming = _assistant('开始', streaming: true);
    messages.add(streaming);
    final controller = FakeSessionController(
      messages: messages,
      streaming: true,
    );
    await _pumpSession(
      tester,
      controller: controller,
      size: const Size(360, 640),
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(SessionTranscript),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    streaming
      ..parts[0] = TextPart('开始${List.filled(30, '持续增长的流式内容').join()}')
      ..text = '持续增长的流式内容';
    controller.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 3),
    );
  });

  testWidgets(
    'only the latest concurrent history selection closes the drawer',
    (tester) async {
      final loadA = Completer<void>();
      final loadB = Completer<void>();
      final controller = FakeSessionController(
        sessions: [
          SessionInfo('a', '会话 A', DateTime(2026, 7, 23)),
          SessionInfo('b', '会话 B', DateTime(2026, 7, 24)),
        ],
        loadCompleters: {'a': loadA, 'b': loadB},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ThemeV2SessionPage(
                      controller: controller,
                      initializeController: false,
                      initialHistoryOpen: true,
                    ),
                  ),
                );
              },
              child: const Text('打开 Session'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开 Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('会话 A'));
      await tester.pump();
      await tester.tap(find.text('会话 B'));
      await tester.pump();

      loadB.complete();
      await tester.pumpAndSettle();
      loadA.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ThemeV2SessionPage), findsOneWidget);
    },
  );

  testWidgets('new conversation invalidates an unfinished history selection', (
    tester,
  ) async {
    final pendingLoad = Completer<void>();
    final controller = FakeSessionController(
      sessions: [SessionInfo('a', '会话 A', DateTime(2026, 7, 23))],
      loadCompleters: {'a': pendingLoad},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ThemeV2SessionPage(
                    controller: controller,
                    initializeController: false,
                    initialHistoryOpen: true,
                  ),
                ),
              );
            },
            child: const Text('打开 Session'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 Session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会话 A'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(SessionHistoryDrawer),
        matching: find.text('新会话'),
      ),
    );
    pendingLoad.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ThemeV2SessionPage), findsOneWidget);
    expect(controller.resetCount, 1);
  });

  testWidgets('ChatPage keeps its constructor and selects the V2 route once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const ChatPage(startBlank: true, themeV2Override: true),
      ),
    );
    await tester.pump();

    expect(find.byType(ThemeV2SessionPage), findsOneWidget);
    expect(find.byType(ThemeV2FloatingDock), findsNothing);
  });

  testWidgets('ChatPage rollout off leaves the legacy session intact', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const ChatPage(startBlank: true, themeV2Override: false),
      ),
    );
    await tester.pump();

    expect(find.byType(ThemeV2SessionPage), findsNothing);
    expect(find.text('问 Agent 任何事…'), findsWidgets);
  });

  testWidgets(
    'history load clears context chips missing from the new session',
    (tester) async {
      final controller = FakeSessionController(
        contextAssets: [(id: 'old', label: '旧资产')],
      );
      await _pumpSession(tester, controller: controller);
      expect(find.text('旧资产'), findsOneWidget);

      controller.contextAssets = [];
      await controller.loadSession('new-session');
      await tester.pump();

      expect(find.text('旧资产'), findsNothing);
    },
  );

  testWidgets('late initialization failure is harmless after route disposal', (
    tester,
  ) async {
    final pending = Completer<void>();
    final controller = FakeSessionController(loadCompleter: pending);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2SessionPage(
          controller: controller,
          boundSessionId: 'pending',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    pending.completeError(StateError('late load failure'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

ChatMessage _assistant(
  String text, {
  bool streaming = false,
  List<ChatPart>? parts,
}) {
  final message = ChatMessage.agent('a-$text')
    ..streaming = streaming
    ..text = text;
  message.parts.addAll(parts ?? [TextPart(text)]);
  return message;
}

Future<void> _pumpSession(
  WidgetTester tester, {
  required FakeSessionController controller,
  Size size = const Size(411, 960),
  ValueNotifier<Brightness>? brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final mode = brightness ?? ValueNotifier(Brightness.light);
  if (brightness == null) addTearDown(mode.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [renderSpecsProvider.overrideWith((ref) async => const {})],
      child: ValueListenableBuilder<Brightness>(
        valueListenable: mode,
        builder: (_, value, _) => MaterialApp(
          theme: buildEurekaTheme(
            value == Brightness.dark ? EurekaColors.dark : EurekaColors.light,
          ),
          home: ThemeV2SessionPage(
            controller: controller,
            initializeController: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class FakeSessionController extends ChangeNotifier
    implements ThemeV2SessionController {
  FakeSessionController({
    List<ChatMessage>? messages,
    this.streaming = false,
    this.error,
    List<SessionInfo>? sessions,
    List<({String id, String label})>? contextAssets,
    this.loadCompleter,
    this.loadCompleters,
    this.sendCompleter,
    this.listFailuresRemaining = 0,
  }) : messages = messages ?? [],
       sessions = sessions ?? [],
       contextAssets = contextAssets ?? [];

  @override
  final List<ChatMessage> messages;

  @override
  bool streaming;

  @override
  String? error;

  @override
  String? sessionId;

  @override
  String get displayTitle => '测试会话';

  @override
  List<({String id, String label})> contextAssets;

  final List<SessionInfo> sessions;
  final Completer<void>? loadCompleter;
  final Map<String, Completer<void>>? loadCompleters;
  final Completer<void>? sendCompleter;
  int listFailuresRemaining;
  int listCallCount = 0;
  final List<String> loadedSessionIds = [];
  int retryCount = 0;
  int resetCount = 0;

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) async => true;

  @override
  Future<void> bindSubject(String type, String id) async {}

  @override
  Future<bool> deleteSession(String id) async {
    sessions.removeWhere((session) => session.id == id);
    return true;
  }

  @override
  Future<void> loadSession(String id, {String? title}) async {
    await loadCompleter?.future;
    await loadCompleters?[id]?.future;
    loadedSessionIds.add(id);
    sessionId = id;
    notifyListeners();
  }

  @override
  Future<List<SessionInfo>> listSessions() async {
    listCallCount++;
    if (listFailuresRemaining > 0) {
      listFailuresRemaining--;
      throw StateError('history unavailable');
    }
    return List.of(sessions);
  }

  @override
  Future<void> precipitate(String text, String skill) async {}

  @override
  void reset() {
    resetCount++;
    messages.clear();
    error = null;
    notifyListeners();
  }

  @override
  Future<void> resumeLast() async {}

  @override
  Future<void> retryLastFailedTurn() async {
    retryCount++;
  }

  @override
  Future<void> send(String text) async {
    await sendCompleter?.future;
  }
}
