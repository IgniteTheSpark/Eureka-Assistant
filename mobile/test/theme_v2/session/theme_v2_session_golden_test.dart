import 'dart:io';

import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_state_test.dart' show FakeSessionController;

enum _GoldenState {
  loaded,
  analyzing,
  history,
  keyboard,
  reviewReady,
  longReviewReady,
  empty,
  error,
}

void main() {
  const surface = ValueKey('session-golden-surface');

  setUpAll(() async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'))).load();
    await (FontLoader('Geist Mono')..addFont(
          rootBundle.load('assets/fonts/GeistMono/GeistMono-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    if (pingFang.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(pingFang.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  for (final brightness in Brightness.values) {
    final suffix = brightness.name;
    for (final state in _GoldenState.values) {
      testWidgets('${state.name} 411 $suffix', (tester) async {
        final controller = _controllerFor(state);
        final legacy = brightness == Brightness.dark
            ? EurekaColors.dark
            : EurekaColors.light;
        final theme = buildThemeV2Theme(brightness).copyWith(
          extensions: [
            ...buildThemeV2Theme(brightness).extensions.values,
            EurekaTheme(legacy),
          ],
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(411, 960);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              renderSpecsProvider.overrideWith((ref) async => const {}),
            ],
            child: MediaQuery(
              data: MediaQueryData(
                size: const Size(411, 960),
                devicePixelRatio: 1,
                disableAnimations: true,
                viewInsets: state == _GoldenState.keyboard
                    ? const EdgeInsets.only(bottom: 396)
                    : EdgeInsets.zero,
              ),
              child: MaterialApp(
                theme: theme,
                home: RepaintBoundary(
                  key: surface,
                  child: ThemeV2SessionPage(
                    controller: controller,
                    initializeController: false,
                    initialHistoryOpen: state == _GoldenState.history,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (state == _GoldenState.keyboard ||
            state == _GoldenState.reviewReady ||
            state == _GoldenState.longReviewReady) {
          final field = find.byKey(const ValueKey('session-composer-field'));
          await tester.tap(field);
          await tester.pump();
          if (state != _GoldenState.keyboard) {
            final text = state == _GoldenState.reviewReady
                ? '请整理访谈反馈，并输出三个行动建议。'
                : List<String>.generate(
                    10,
                    (index) => '第 ${index + 1} 行访谈重点',
                  ).join('\n');
            await tester.enterText(field, text);
            await tester.pump();
            tester.widget<TextField>(field).focusNode!.unfocus();
            await tester.pump();
          }
        }
        await expectLater(
          find.byKey(surface),
          matchesGoldenFile('goldens/session-${state.name}-411-$suffix.png'),
        );
      });
    }
  }
}

FakeSessionController _controllerFor(_GoldenState state) {
  final user = ChatMessage.user('u1', '帮我添加一个今天下午的会议。');
  final assistant = ChatMessage.agent('a1')
    ..streaming = false
    ..text = '已识别为日程，并补全为一小时的时间窗口。'
    ..parts.addAll([
      const TextPart('已识别为日程，并补全为一小时的时间窗口。'),
      CardsPart([
        {
          'id': 'event-1',
          'user_skill_name': 'event',
          'payload': {'title': '深度复盘会', 'start_at': '2026-07-28T16:00:00'},
        },
      ]),
    ]);
  final messages = state == _GoldenState.empty
      ? <ChatMessage>[]
      : <ChatMessage>[user, assistant];
  if (state == _GoldenState.analyzing) {
    assistant.streaming = true;
  }
  return FakeSessionController(
    messages: messages,
    streaming: state == _GoldenState.analyzing,
    error: state == _GoldenState.error ? '录音文件暂时不可访问' : null,
    sessions: [
      SessionInfo('s1', '7月23日 闪念', DateTime(2026, 7, 23, 21, 6)),
      SessionInfo('s2', '下午会议', DateTime(2026, 7, 22, 16)),
      SessionInfo('s3', '客户回访', DateTime(2026, 7, 21, 15)),
    ],
  );
}
