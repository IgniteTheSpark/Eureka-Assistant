import 'dart:async';

import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/reka_companion_controller.dart';
import 'package:eureka/theme_v2/capture/reka_terminal.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/shell/reka_mini.dart';
import 'package:eureka/theme_v2/shell/reka_shell_companion.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/voice_input/reka_voice_capture.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mini Reka is centered above Dock and reports hold movement', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final offsets = <double>[];
    var starts = 0;
    var releases = 0;
    Rect? tapAnchor;

    await tester.pumpWidget(
      _host(
        Stack(
          children: [
            ThemeV2FloatingDock(
              selectedIndex: 1,
              onDestinationSelected: (_) {},
            ),
            RekaShellCompanion(
              mode: RekaShellCompanionMode.mini,
              controller: harness.companion,
              todayRekaController: harness.today,
              onRekaTap: (anchor) => tapAnchor = anchor,
              onLongPressStart: () => starts += 1,
              onLongPressMove: offsets.add,
              onLongPressEnd: () => releases += 1,
              onLongPressCancel: () {},
              onOpenDetail: () {},
            ),
          ],
        ),
      ),
    );

    expect(
      tester.getCenter(find.byKey(RekaMini.targetKey)).dx,
      closeTo(
        tester.getCenter(find.byKey(ThemeV2FloatingDock.dockKey)).dx,
        .01,
      ),
    );
    final miniBottom = tester.getBottomLeft(find.byKey(RekaMini.visualKey)).dy;
    final dockTop = tester
        .getTopLeft(find.byKey(ThemeV2FloatingDock.dockKey))
        .dy;
    expect(dockTop - miniBottom, closeTo(6, .01));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(RekaMini.targetKey)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(starts, 1);
    expect(offsets.last, closeTo(-80, .01));
    expect(releases, 1);

    await tester.tap(find.byKey(RekaMini.targetKey));
    expect(tapAnchor, isNotNull);
    expect(tapAnchor!.size, const Size.square(RekaMini.targetExtent));
  });

  testWidgets('Today mode renders only terminal and follows safe Reka anchor', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.today.layout(
      const Size(400, 700),
      reservedInsets: const EdgeInsets.fromLTRB(4, 80, 4, 80),
    );
    harness.activities.apply(
      CaptureActivityEvent(
        aliases: const {'client:ring-status'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.understanding,
        occurredAt: DateTime.utc(2026, 8, 21),
      ),
    );

    await tester.pumpWidget(
      _host(
        RekaShellCompanion(
          mode: RekaShellCompanionMode.today,
          controller: harness.companion,
          todayRekaController: harness.today,
          onRekaTap: (_) {},
          onLongPressStart: () {},
          onLongPressMove: (_) {},
          onLongPressEnd: () {},
          onLongPressCancel: () {},
          onOpenDetail: () {},
        ),
      ),
    );

    expect(find.byKey(RekaMini.targetKey), findsNothing);
    expect(find.byType(RekaTerminal), findsOneWidget);
    final firstRect = tester.getRect(find.byType(RekaTerminal));
    expect(firstRect.left, greaterThanOrEqualTo(16));
    expect(firstRect.right, lessThanOrEqualTo(384));
    expect(firstRect.top, greaterThanOrEqualTo(16));
    expect(firstRect.bottom, lessThanOrEqualTo(684));

    harness.today.beginDrag(harness.today.rekaCenter);
    harness.today.updateDrag(
      const Offset(300, 420),
      const Duration(milliseconds: 16),
    );
    await tester.pump();

    final secondRect = tester.getRect(find.byType(RekaTerminal));
    expect(secondRect.left, greaterThan(firstRect.left));
    expect(secondRect.right, lessThanOrEqualTo(384));
  });

  testWidgets('reduced motion uses immediate companion transitions', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      _host(
        RekaShellCompanion(
          mode: RekaShellCompanionMode.mini,
          controller: harness.companion,
          todayRekaController: harness.today,
          onRekaTap: (_) {},
          onLongPressStart: () {},
          onLongPressMove: (_) {},
          onLongPressEnd: () {},
          onLongPressCancel: () {},
          onOpenDetail: () {},
        ),
        disableAnimations: true,
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(RekaShellCompanion.transitionKey),
    );
    expect(switcher.duration, Duration.zero);
    expect(find.byType(RekaTerminal), findsNothing);
  });
}

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 700),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(body: SizedBox(width: 400, height: 700, child: child)),
  ),
);

class _Harness {
  _Harness()
    : activities = CaptureActivityCoordinator(),
      session = _FakeSession('unused'),
      today = TodayRekaMotionController() {
    voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _Service(session)),
      sendFlash: (_, _) async {},
      haptic: () {},
    );
    companion = RekaCompanionController(voice: voice, activities: activities);
  }

  final CaptureActivityCoordinator activities;
  final _FakeSession session;
  final TodayRekaMotionController today;
  late final RekaVoiceCaptureCoordinator voice;
  late final RekaCompanionController companion;

  Future<void> dispose() async {
    companion.dispose();
    await voice.close();
    voice.dispose();
    activities.dispose();
    today.dispose();
  }
}

class _Service implements VoiceInputServiceClient {
  _Service(this.session);
  final _FakeSession session;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async => session;
}

class _FakeSession implements VoiceInputSessionHandle {
  _FakeSession(this.voiceSessionId);
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>.broadcast();

  @override
  final String voiceSessionId;

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => VoiceInputMode.reka;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}
