import 'dart:async';
import 'dart:io';

import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/reka_companion_controller.dart';
import 'package:eureka/theme_v2/capture/reka_terminal_models.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_output_coordinator.dart';
import 'package:eureka/theme_v2/home/today_reka_capture_cue.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/shell/reka_shell_companion.dart';
import 'package:eureka/theme_v2/shell/shell_reka_presentation_controller.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/voice_input/reka_voice_capture.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  for (final scenario in _Scenario.values) {
    testWidgets('floating dither Reka ${scenario.name}', (tester) async {
      final harness = _Harness(scenario);
      addTearDown(harness.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.includesTerminal
          ? const Size(400, 420)
          : const Size(320, 220);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _GoldenHost(
          brightness: scenario.brightness,
          child: RepaintBoundary(
            key: const ValueKey('shell-dither-reka-golden-surface'),
            child: Stack(
              children: [
                ThemeV2FloatingDock(
                  selectedIndex: 1,
                  onDestinationSelected: (_) {},
                ),
                RekaShellCompanion(
                  mode: RekaShellCompanionMode.mini,
                  controller: harness.companion,
                  todayRekaController: harness.today,
                  presentationController: harness.presentation,
                  forceDitherFallback: true,
                  onRekaTap: (_) {},
                  onLongPressStart: () {},
                  onLongPressMove: (_) {},
                  onLongPressEnd: () {},
                  onLongPressCancel: () {},
                  onOpenDetail: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byKey(const ValueKey('shell-dither-reka-golden-surface')),
        matchesGoldenFile('goldens/shell-dither-reka-${scenario.fileName}.png'),
      );
    });
  }
}

enum _Scenario {
  idleLight(Brightness.light, TodayRekaCaptureAction.idle, 'idle-light'),
  idleDark(Brightness.dark, TodayRekaCaptureAction.idle, 'idle-dark'),
  listening(
    Brightness.light,
    TodayRekaCaptureAction.listening,
    'listening-light',
  ),
  understanding(
    Brightness.light,
    TodayRekaCaptureAction.understanding,
    'understanding-light',
  ),
  terminal(
    Brightness.light,
    TodayRekaCaptureAction.understanding,
    'terminal-open-light',
    includesTerminal: true,
  );

  const _Scenario(
    this.brightness,
    this.action,
    this.fileName, {
    this.includesTerminal = false,
  });

  final Brightness brightness;
  final TodayRekaCaptureAction action;
  final String fileName;
  final bool includesTerminal;
}

class _GoldenHost extends StatelessWidget {
  const _GoldenHost({required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQueryData(
      disableAnimations: true,
      platformBrightness: brightness,
      textScaler: TextScaler.noScaling,
    ),
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      theme: buildThemeV2Theme(brightness),
      home: Scaffold(body: child),
    ),
  );
}

class _Harness {
  _Harness(_Scenario scenario)
    : activities = CaptureActivityCoordinator(),
      session = _FakeSession(),
      today = TodayRekaMotionController(),
      presentation = ShellRekaPresentationController() {
    voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _Service(session)),
      sendFlash: (_, _) async {},
      haptic: () {},
    );
    companion = _GoldenCompanionController(
      showTerminal: scenario.includesTerminal,
      voice: voice,
      activities: activities,
    );
    presentation.update(
      refreshSignal: 0,
      cue: const TodayOutputCue.idle(),
      captureCue: TodayRekaCaptureCue(
        action: scenario.action,
        isRealtime: scenario.action != TodayRekaCaptureAction.idle,
      ),
    );
  }

  final CaptureActivityCoordinator activities;
  final _FakeSession session;
  final TodayRekaMotionController today;
  final ShellRekaPresentationController presentation;
  late final RekaVoiceCaptureCoordinator voice;
  late final RekaCompanionController companion;

  Future<void> dispose() async {
    companion.dispose();
    await voice.close();
    voice.dispose();
    activities.dispose();
    today.dispose();
    presentation.dispose();
  }
}

class _GoldenCompanionController extends RekaCompanionController {
  _GoldenCompanionController({
    required bool showTerminal,
    required super.voice,
    required super.activities,
  }) : _model = showTerminal
           ? const RekaTerminalModel(
               identity: 'golden-understanding',
               aliases: {'client:golden'},
               source: CaptureActivitySource.app,
               phase: RekaTerminalPhase.understanding,
               statusLabel: '正在理解',
             )
           : null;

  final RekaTerminalModel? _model;

  @override
  RekaTerminalModel? get terminal => _model;
}

class _Service implements VoiceInputServiceClient {
  const _Service(this.session);

  final _FakeSession session;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async => session;
}

class _FakeSession implements VoiceInputSessionHandle {
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>.broadcast();

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => VoiceInputMode.reka;

  @override
  String get voiceSessionId => 'golden-session';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}
