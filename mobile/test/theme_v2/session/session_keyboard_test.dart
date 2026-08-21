import 'dart:async';

import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/session/session_composer.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:eureka/voice_input/voice_input_field.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_scope.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_state_test.dart' show FakeSessionController;

void main() {
  testWidgets('idle composer is compact and omits send and context actions', (
    tester,
  ) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(tester, controller: controller);

    expect(find.byKey(const ValueKey('session-composer-footer')), findsNothing);
    expect(find.byKey(const ValueKey('session-send')), findsNothing);
    expect(find.byKey(VoiceInputField.micKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-composer-sparkle')),
      findsOneWidget,
    );
    expect(find.byTooltip('添加上下文资产'), findsNothing);
  });

  testWidgets('focus expands controls and dismissed drafts remain sendable', (
    tester,
  ) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(tester, controller: controller);
    final field = find.byKey(const ValueKey('session-composer-field'));

    await tester.tap(field);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('session-composer-footer')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('session-send')), findsOneWidget);

    await tester.enterText(field, '保留草稿');
    tester.widget<TextField>(field).focusNode!.unfocus();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('session-composer-footer')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('session-send')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('session-send')))
          .onPressed,
      isNotNull,
    );
  });

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
      lessThan(280),
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

  testWidgets('agent reply disables both send and voice', (tester) async {
    final controller = FakeSessionController();
    await _pumpKeyboard(tester, controller: controller);
    final field = find.byKey(const ValueKey('session-composer-field'));

    IconButton sendButton() =>
        tester.widget<IconButton>(find.byKey(const ValueKey('session-send')));

    await tester.tap(field);
    await tester.pump();
    expect(sendButton().onPressed, isNull);
    await tester.enterText(field, '可以发送');
    await tester.pump();
    expect(sendButton().onPressed, isNotNull);

    controller.streaming = true;
    controller.notifyListeners();
    await tester.pump();
    expect(sendButton().onPressed, isNull);
    expect(
      tester.widget<IconButton>(find.byKey(VoiceInputField.micKey)).onPressed,
      isNull,
    );
  });

  testWidgets('voice transcript always follows the newest line', (
    tester,
  ) async {
    final controller = FakeSessionController();
    final voiceSession = _ComposerVoiceSession();
    await _pumpKeyboard(
      tester,
      controller: controller,
      voiceService: _ComposerVoiceService(voiceSession),
    );
    final field = find.byKey(const ValueKey('session-composer-field'));

    await tester.tap(field);
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(find.byKey(VoiceInputField.micKey));
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(find.byKey(const ValueKey('session-send')), findsNothing);

    final firstTranscript = List<String>.generate(
      12,
      (index) => '第 ${index + 1} 行语音内容',
    ).join('\n');
    voiceSession.emit(
      VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.partial,
        sequence: 1,
        text: firstTranscript,
      ),
    );
    await tester.pump();

    ScrollableState fieldScroll() => tester.state<ScrollableState>(
      find.descendant(of: field, matching: find.byType(Scrollable)).first,
    );

    final scrollable = fieldScroll();
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    scrollable.position.jumpTo(0);

    final nextTranscript = '$firstTranscript\n第 13 行最新语音内容';
    voiceSession.emit(
      VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.partial,
        sequence: 2,
        text: nextTranscript,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      fieldScroll().position.pixels,
      closeTo(fieldScroll().position.maxScrollExtent, 1),
    );

    voiceSession.emit(
      VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.finalTranscript,
        sequence: 3,
        text: nextTranscript,
        audioDurationMs: 1200,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('session-send')), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(
      fieldScroll().position.pixels,
      closeTo(fieldScroll().position.maxScrollExtent, 1),
    );
  });
}

Future<void> _pumpKeyboard(
  WidgetTester tester, {
  required FakeSessionController controller,
  Size size = const Size(360, 800),
  EdgeInsets viewInsets = EdgeInsets.zero,
  TextScaler textScaler = TextScaler.noScaling,
  VoiceInputServiceClient? voiceService,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final session = ThemeV2SessionPage(
    controller: controller,
    initializeController: false,
  );
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
        home: voiceService == null
            ? session
            : VoiceInputHost(service: voiceService, child: session),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final class _ComposerVoiceService implements VoiceInputServiceClient {
  const _ComposerVoiceService(this.session);

  final _ComposerVoiceSession session;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async => session;
}

final class _ComposerVoiceSession implements VoiceInputSessionHandle {
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>();

  void emit(VoiceInputEvent event) => _events.add(event);

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => VoiceInputMode.ordinary;

  @override
  String get voiceSessionId => 'session-composer-test';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}
