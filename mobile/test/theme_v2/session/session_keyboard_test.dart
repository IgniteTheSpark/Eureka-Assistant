import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/session/session_composer.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:eureka/voice_input/voice_input_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_state_test.dart' show FakeSessionController;

void main() {
  testWidgets(
    'composer follows the real keyboard inset without losing content',
    (tester) async {
      final controller = FakeSessionController(
        messages: [ChatMessage.user('u1', '键盘打开仍保留')],
        streaming: true,
      );

      await _pumpKeyboard(
        tester,
        controller: controller,
        viewInsets: const EdgeInsets.only(bottom: 300),
      );

      final composer = tester.getRect(
        find.byKey(const ValueKey('session-composer')),
      );
      expect(composer.bottom, lessThanOrEqualTo(500));
      expect(find.text('键盘打开仍保留'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-analyzing')), findsOneWidget);
    },
  );

  testWidgets('long large-scale input wraps without overflow', (tester) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(
      tester,
      controller: controller,
      size: const Size(360, 800),
      textScaler: const TextScaler.linear(1.8),
      viewInsets: const EdgeInsets.only(bottom: 280),
    );

    await tester.enterText(
      find.byKey(const ValueKey('session-composer-field')),
      List.filled(30, '这是一段很长的中文输入').join(),
    );
    await tester.pump();

    final exception = tester.takeException();
    expect(exception, isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('session-composer'))).height,
      lessThan(240),
    );
  });

  testWidgets('long text scrolls inside a bounded composer', (tester) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(tester, controller: controller);

    final fieldFinder = find.byKey(const ValueKey('session-composer-field'));
    await tester.enterText(
      fieldFinder,
      List<String>.generate(40, (index) => '第$index段很长的输入内容').join('\n'),
    );
    await tester.pump();

    final bound = tester.getSize(
      find.byKey(const ValueKey('session-composer-field-bound')),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: fieldFinder, matching: find.byType(Scrollable)).first,
    );
    expect(bound.height, lessThanOrEqualTo(116));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice and send actions keep a fixed bottom alignment', (
    tester,
  ) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(tester, controller: controller);

    await tester.enterText(
      find.byKey(const ValueKey('session-composer-field')),
      List<String>.filled(30, '很长的消息内容').join('\n'),
    );
    await tester.pump();

    final mic = tester.getRect(find.byKey(VoiceInputField.micKey));
    final send = tester.getRect(find.byKey(const ValueKey('session-send')));
    expect(mic.size, const Size.square(SessionComposer.actionSize));
    expect(send.size, const Size.square(SessionComposer.actionSize));
    expect((mic.bottom - send.bottom).abs(), lessThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('send is disabled for empty input and while streaming', (
    tester,
  ) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(tester, controller: controller);

    IconButton sendButton() =>
        tester.widget<IconButton>(find.byKey(const ValueKey('session-send')));

    expect(sendButton().onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('session-composer-field')),
      '可以发送',
    );
    await tester.pump();
    expect(sendButton().onPressed, isNotNull);

    controller.streaming = true;
    controller.notifyListeners();
    await tester.pump();
    expect(sendButton().onPressed, isNull);
  });
}

Future<void> _pumpKeyboard(
  WidgetTester tester, {
  required FakeSessionController controller,
  Size size = const Size(360, 800),
  EdgeInsets viewInsets = EdgeInsets.zero,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: 1,
        viewInsets: viewInsets,
        textScaler: textScaler,
      ),
      child: MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2SessionPage(
          controller: controller,
          initializeController: false,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
