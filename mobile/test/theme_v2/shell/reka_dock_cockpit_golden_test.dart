import 'dart:async';
import 'dart:io';

import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/reka_companion_controller.dart';
import 'package:eureka/theme_v2/capture/reka_terminal_models.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/shell/reka_shell_companion.dart';
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
    testWidgets('Dock cockpit ${scenario.name}', (tester) async {
      final harness = _Harness(scenario.state);
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
          disableAnimations: true,
          child: RepaintBoundary(
            key: const ValueKey('reka-cockpit-golden-surface'),
            child: Stack(
              children: [
                ThemeV2FloatingDock(
                  selectedIndex: 1,
                  onDestinationSelected: (_) {},
                  rekaCockpit: RekaDockCockpit(
                    controller: harness.companion,
                    onTap: (_) {},
                    onLongPressStart: () {},
                    onLongPressMove: (_) {},
                    onLongPressEnd: () {},
                    onLongPressCancel: () {},
                  ),
                ),
                if (scenario.includesTerminal)
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
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final target = scenario.includesTerminal
          ? find.byKey(const ValueKey('reka-cockpit-golden-surface'))
          : find.byKey(ThemeV2FloatingDock.compositionKey);
      await expectLater(
        target,
        matchesGoldenFile('goldens/reka-cockpit-${scenario.fileName}.png'),
      );
      await harness.closeCapture();
    });
  }
}

enum _State { idle, listening, cancelArmed, understanding }

extension on _State {
  RekaTerminalPhase? get phase => switch (this) {
    _State.idle => null,
    _State.listening => RekaTerminalPhase.listening,
    _State.cancelArmed => RekaTerminalPhase.cancelArmed,
    _State.understanding => RekaTerminalPhase.understanding,
  };
}

enum _Scenario {
  idleLight(Brightness.light, _State.idle, 'idle-light'),
  idleDark(Brightness.dark, _State.idle, 'idle-dark'),
  listeningLight(Brightness.light, _State.listening, 'listening-light'),
  listeningDark(Brightness.dark, _State.listening, 'listening-dark'),
  understanding(Brightness.light, _State.understanding, 'understanding-light'),
  cancelArmed(Brightness.light, _State.cancelArmed, 'cancel-armed-light'),
  terminal(
    Brightness.light,
    _State.understanding,
    'terminal-open-light',
    includesTerminal: true,
  ),
  reduceMotion(Brightness.light, _State.idle, 'reduce-motion-light');

  const _Scenario(
    this.brightness,
    this.state,
    this.fileName, {
    this.includesTerminal = false,
  });

  final Brightness brightness;
  final _State state;
  final String fileName;
  final bool includesTerminal;
}

class _GoldenHost extends StatelessWidget {
  const _GoldenHost({
    required this.brightness,
    required this.disableAnimations,
    required this.child,
  });

  final Brightness brightness;
  final bool disableAnimations;
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
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
  _Harness(_State state)
    : activities = CaptureActivityCoordinator(),
      session = _FakeSession(),
      today = TodayRekaMotionController() {
    voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _Service(session)),
      sendFlash: (_, _) async {},
      haptic: () {},
    );
    companion = _GoldenCompanionController(
      phase: state.phase,
      voice: voice,
      activities: activities,
    );
  }

  final CaptureActivityCoordinator activities;
  final _FakeSession session;
  final TodayRekaMotionController today;
  late final RekaVoiceCaptureCoordinator voice;
  late final RekaCompanionController companion;

  Future<void> dispose() async {
    companion.dispose();
    await closeCapture();
    voice.dispose();
    activities.dispose();
    today.dispose();
  }

  Future<void> closeCapture() => voice.close();
}

class _GoldenCompanionController extends RekaCompanionController {
  _GoldenCompanionController({
    required RekaTerminalPhase? phase,
    required super.voice,
    required super.activities,
  }) : _model = phase == null
           ? null
           : RekaTerminalModel(
               identity: 'golden-${phase.name}',
               aliases: const {'client:golden'},
               source: CaptureActivitySource.app,
               phase: phase,
               statusLabel: switch (phase) {
                 RekaTerminalPhase.listening => '聆听中',
                 RekaTerminalPhase.cancelArmed => '松手取消',
                 RekaTerminalPhase.understanding => '正在理解',
                 _ => phase.name,
               },
             );

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
