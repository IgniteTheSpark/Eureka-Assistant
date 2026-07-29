import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/session/session_transcript.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_state_test.dart' show FakeSessionController;

void main() {
  testWidgets('focuses the exact middle input turn instead of the tail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 720);
    addTearDown(tester.view.reset);
    final messages = <ChatMessage>[
      _user('u1', '第一轮 ${'较长内容 ' * 28}', 'turn-1'),
      _assistant('a1', '第一轮回复 ${'说明 ' * 18}'),
      _user('u2', '第二轮目标 ${'需要精确定位 ' * 28}', 'turn-2'),
      _assistant('a2', '第二轮回复 ${'说明 ' * 18}'),
      _user('u3', '第三轮 ${'较长内容 ' * 28}', 'turn-3'),
      _assistant('a3', '第三轮回复 ${'说明 ' * 18}'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2SessionPage(
          controller: FakeSessionController(messages: messages),
          initializeController: false,
          focusedInputTurnId: 'turn-2',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final focused = find.byKey(const ValueKey('session-focused-turn-turn-2'));
    expect(focused, findsOneWidget);
    final transcript = tester.widget<ListView>(
      find.descendant(
        of: find.byType(SessionTranscript),
        matching: find.byType(ListView),
      ),
    );
    expect(transcript.controller!.offset, greaterThan(0));
    expect(
      transcript.controller!.offset,
      lessThan(transcript.controller!.position.maxScrollExtent),
    );
    expect(tester.getCenter(focused).dy, inInclusiveRange(180, 540));
  });

  testWidgets('reduce motion makes the focused-turn highlight immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: ThemeV2SessionPage(
            controller: FakeSessionController(
              messages: [_user('u2', '目标输入', 'turn-2')],
            ),
            initializeController: false,
            focusedInputTurnId: 'turn-2',
          ),
        ),
      ),
    );
    await tester.pump();

    final highlight = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('session-focused-turn-turn-2')),
    );
    expect(highlight.duration, Duration.zero);
  });
}

ChatMessage _user(String id, String text, String inputTurnId) =>
    ChatMessage.user(id, text, inputTurnId: inputTurnId);

ChatMessage _assistant(String id, String text) {
  final message = ChatMessage.agent(id)
    ..streaming = false
    ..text = text
    ..parts.add(TextPart(text));
  return message;
}
