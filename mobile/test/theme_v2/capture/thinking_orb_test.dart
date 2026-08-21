import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme_v2/capture/thinking_orb.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/session/session_analysis_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes ten distinct product states and complete mappings', () {
    expect(ThinkingOrbVisualState.values, hasLength(10));
    expect(thinkingOrbMorphDuration, const Duration(milliseconds: 220));
    expect(
      ThinkingOrbVisualState.values.map(thinkingOrbProfile).toSet(),
      hasLength(10),
    );
    expect(
      thinkingOrbStateForCapture(CaptureActivityPhase.done),
      ThinkingOrbVisualState.success,
    );
    expect(
      thinkingOrbStateForAgent(AgentWorkPhase.executing),
      ThinkingOrbVisualState.executing,
    );
    expect(
      thinkingOrbStateForAgent(AgentWorkPhase.composing),
      ThinkingOrbVisualState.composing,
    );
    expect(
      thinkingOrbProfile(ThinkingOrbVisualState.listening),
      isNot(thinkingOrbProfile(ThinkingOrbVisualState.transcribing)),
    );
  });

  testWidgets('thinking orb is Flutter-native and morphs between states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const Center(
          child: ThinkingOrb(state: ThinkingOrbVisualState.listening, size: 32),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ThinkingOrb),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(ThinkingOrb)), const Size.square(32));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: const Center(
          child: ThinkingOrb(
            state: ThinkingOrbVisualState.organizing,
            size: 32,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 219));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the orb static across state changes', (
    tester,
  ) async {
    Widget host(ThinkingOrbVisualState state) => MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(child: ThinkingOrb(state: state, size: 32)),
      ),
    );

    await tester.pumpWidget(host(ThinkingOrbVisualState.listening));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(host(ThinkingOrbVisualState.organizing));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
