import 'dart:async';

import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/data_revision.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/home/home_agenda_panel.dart';
import 'package:eureka/theme_v2/home/today_dot_experiment_page.dart';
import 'package:eureka/theme_v2/home/today_living_surface.dart';
import 'package:eureka/theme_v2/home/today_reka_quick_actions.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:eureka/theme_v2/home/today_reka_capture_cue.dart';
import 'package:eureka/theme_v2/home/today_reka_scene.dart';
import 'package:eureka/today/today_data.dart';
import 'package:eureka/voice_input/reka_voice_capture.dart';
import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'long pressing the dithered Reka shows live text and release sends it',
    (tester) async {
      final session = _RekaVoiceSession();
      final sent = <(String, String)>[];
      final voice = RekaVoiceCaptureCoordinator(
        coordinator: VoiceInputCoordinator(service: _RekaVoiceService(session)),
        sendFlash: (text, sessionId) async => sent.add((text, sessionId)),
        haptic: () {},
      );
      addTearDown(() async {
        await voice.close();
        voice.dispose();
      });

      await tester.pumpWidget(
        _Host(
          child: TodayDotExperimentPage(
            repository: _ImmediateRepository(TodayData.empty),
            rekaVoiceCoordinator: voice,
            rekaBuilder: (_, _, _, _, _, _, _) => const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(TodayRekaScene.rekaTargetKey);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      await tester.pump();
      await tester.pump();
      expect(voice.state, RekaVoiceCaptureState.listening);

      session.emit(
        const VoiceTranscriptEvent(
          kind: VoiceTranscriptKind.partial,
          sequence: 1,
          text: '明天上午十点开会',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(voice.transcript, '明天上午十点开会');
      expect(find.text('明天上午十点开会'), findsNothing);
      expect(find.text('上滑取消 · 松开发送'), findsNothing);
      expect(find.text('手动记录'), findsNothing);

      await gesture.up();
      await tester.pump();
      expect(session.stopCount, 1);
      session.emit(
        const VoiceTranscriptEvent(
          kind: VoiceTranscriptKind.finalTranscript,
          sequence: 2,
          text: '明天上午十点开会。',
        ),
      );
      for (var i = 0; i < 8 && sent.isEmpty; i++) {
        await tester.pump();
      }
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();

      expect(sent, [('明天上午十点开会。', 'reka-page-session')]);
      expect(find.text('明天上午十点开会。'), findsNothing);
    },
  );

  testWidgets('sliding the dithered Reka upward cancels without a Flash', (
    tester,
  ) async {
    final session = _RekaVoiceSession();
    final sent = <String>[];
    final voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _RekaVoiceService(session)),
      sendFlash: (text, _) async => sent.add(text),
      haptic: () {},
    );
    addTearDown(() async {
      await voice.close();
      voice.dispose();
    });
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: _ImmediateRepository(TodayData.empty),
          rekaVoiceCoordinator: voice,
          rekaBuilder: (_, _, _, _, _, _, _) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(TodayRekaScene.rekaTargetKey)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await tester.pump();
    await tester.pump();

    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    expect(voice.state, RekaVoiceCaptureState.cancelArmed);
    expect(find.text('松开取消'), findsNothing);

    await gesture.up();
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();

    expect(session.cancelCount, 1);
    expect(sent, isEmpty);
    expect(voice.state, RekaVoiceCaptureState.idle);
    expect(find.text('松开取消'), findsNothing);
  });

  testWidgets('backgrounding after release cancels a stopping voice capture', (
    tester,
  ) async {
    final session = _RekaVoiceSession();
    final sent = <String>[];
    final voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _RekaVoiceService(session)),
      sendFlash: (text, _) async => sent.add(text),
      haptic: () {},
    );
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await voice.close();
      voice.dispose();
    });
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: _ImmediateRepository(TodayData.empty),
          rekaVoiceCoordinator: voice,
          rekaBuilder: (_, _, _, _, _, _, _) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(TodayRekaScene.rekaTargetKey)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await tester.pump();
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(voice.state, RekaVoiceCaptureState.stopping);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() => pumpEventQueue());
    session.emit(
      const VoiceTranscriptEvent(
        kind: VoiceTranscriptKind.finalTranscript,
        sequence: 1,
        text: '不应该发送',
      ),
    );
    await tester.runAsync(() => pumpEventQueue());

    expect(session.cancelCount, 1);
    expect(sent, isEmpty);
    expect(voice.state, RekaVoiceCaptureState.idle);
  });

  testWidgets('voice error does not mask hardware cue and hides in agenda', (
    tester,
  ) async {
    final capture = CaptureActivityCoordinator();
    final voice = RekaVoiceCaptureCoordinator(
      coordinator: VoiceInputCoordinator(service: _FailingRekaVoiceService()),
      sendFlash: (_, _) async {},
      haptic: () {},
    );
    addTearDown(() async {
      capture.dispose();
      await voice.close();
      voice.dispose();
    });
    await voice.begin();
    expect(voice.state, RekaVoiceCaptureState.error);
    capture.apply(
      CaptureActivityEvent(
        aliases: const {'capture-after-voice-error'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.understanding,
        occurredAt: DateTime.utc(2026, 8, 20),
        isRealtime: true,
      ),
    );
    var cue = const TodayRekaCaptureCue.idle();
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: _ImmediateRepository(TodayData.empty),
          captureActivityCoordinator: capture,
          rekaVoiceCoordinator: voice,
          rekaBuilder: (_, _, _, _, _, _, captureCue) {
            cue = captureCue;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(cue.action, TodayRekaCaptureAction.understanding);
    expect(find.text('语音输入失败，请再试一次'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeAgendaPanel), findsOneWidget);
    expect(find.text('语音输入失败，请再试一次'), findsNothing);
  });

  testWidgets('capture coordinator updates the mounted Reka cue in place', (
    tester,
  ) async {
    final coordinator = CaptureActivityCoordinator();
    addTearDown(coordinator.dispose);
    var cue = const TodayRekaCaptureCue.idle();

    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: _ImmediateRepository(TodayData.empty),
          captureActivityCoordinator: coordinator,
          rekaBuilder:
              (
                context,
                pose,
                active,
                reduceMotion,
                refreshSignal,
                outputCue,
                captureCue,
              ) {
                cue = captureCue;
                return const SizedBox.expand();
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sceneBefore = tester.element(find.byType(TodayRekaScene));

    coordinator.apply(
      CaptureActivityEvent(
        aliases: const {'client:home-capture'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.understanding,
        occurredAt: DateTime.utc(2026, 8, 15),
        isRealtime: true,
      ),
    );
    await tester.pump();

    expect(cue.action, TodayRekaCaptureAction.understanding);
    expect(tester.element(find.byType(TodayRekaScene)), same(sceneBefore));
  });

  testWidgets('initial data composes header, signal band and asset chamber', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 14, 10);
    final data = TodayData(
      chain: [
        ChainItem(
          kind: 'event',
          id: 'event-1',
          title: '产品评审',
          at: DateTime(2026, 8, 14, 14),
          timed: true,
        ),
      ],
      noTimeTodos: const [],
      pool: [
        PoolAsset(
          id: 'asset-1',
          type: 'notes',
          domain: '',
          title: '会议草稿',
          payload: const {'title': '会议草稿'},
          createdAt: now,
        ),
      ],
      poolTrueCount: 1,
      flashCount: 0,
      rekaQueue: [
        TodayRekaItem(
          id: 'signal-1',
          type: 'rhythm_gap',
          title: '跑步还没有记录',
          body: '可以现在补上一笔',
          link: '',
          createdAt: now,
          targetType: 'skill',
          targetId: 'running',
        ),
      ],
    );
    final repository = _ImmediateRepository(data);

    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(repository: repository, now: now),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.loadCount, 1);
    expect(find.text('产品评审'), findsOneWidget);
    expect(find.text('跑步还没有记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-signal-band')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-asset-chamber')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-next-schedule')), findsOneWidget);
    final signalHeight = tester
        .getSize(find.byKey(const ValueKey('today-signal-band')))
        .height;
    final assetHeight = tester
        .getSize(find.byKey(const ValueKey('today-asset-chamber')))
        .height;
    expect(assetHeight / signalHeight, closeTo(2, .2));
    expect(find.byKey(TodayRekaScene.rekaRenderKey), findsOneWidget);
  });

  testWidgets('header keeps an empty next capsule when the day has none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: _ImmediateRepository(TodayData.empty),
          now: DateTime(2026, 8, 14),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-next-schedule')), findsOneWidget);
    expect(find.text('今天暂无安排'), findsOneWidget);
    expect(find.text('今日'), findsNothing);
    expect(find.text('8月14日 · 周五'), findsOneWidget);
  });

  testWidgets(
    'agenda opens locally, hides Reka, and reuses loaded Today data',
    (tester) async {
      final now = DateTime(2026, 8, 14, 9);
      final repository = _ImmediateRepository(
        TodayData(
          chain: [
            ChainItem(
              kind: 'event',
              id: 'event',
              title: '周会',
              at: DateTime(2026, 8, 14, 10, 30),
              timed: true,
            ),
            ChainItem(
              kind: 'todo',
              id: 'todo',
              title: '提交方案',
              at: DateTime(2026, 8, 14, 10, 30),
              timed: true,
            ),
          ],
          noTimeTodos: const [],
          pool: const [],
          poolTrueCount: 0,
          flashCount: 0,
        ),
      );
      await tester.pumpWidget(
        _Host(
          child: TodayDotExperimentPage(repository: repository, now: now),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeAgendaPanel), findsOneWidget);
      expect(find.byType(TodayLivingSurface), findsNothing);
      expect(find.byKey(TodayRekaScene.rekaRenderKey), findsNothing);
      expect(find.text('周会'), findsOneWidget);
      expect(find.text('提交方案'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('theme-v2-agenda-item-event-event')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('theme-v2-agenda-item-todo-todo')),
        findsOneWidget,
      );
      expect(repository.loadCount, 1);

      await tester.tap(find.bySemanticsLabel('收起日程'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayLivingSurface), findsOneWidget);
      expect(find.byKey(TodayRekaScene.rekaRenderKey), findsOneWidget);
      expect(repository.loadCount, 1);
    },
  );

  testWidgets('immersive Reka stays above content without a local field', (
    tester,
  ) async {
    final controller = TodayRekaMotionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: _ImmediateRepository(TodayData.empty),
          rekaController: controller,
          extendUnderChrome: true,
          rekaBuilder:
              (
                context,
                pose,
                active,
                reduceMotion,
                refreshSignal,
                cue,
                captureCue,
              ) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today-local-dither-field')),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(TodayRekaScene.rekaRenderKey),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );

    final before = tester.getCenter(find.byKey(TodayRekaScene.rekaRenderKey));
    await tester.drag(
      find.byKey(TodayRekaScene.rekaTargetKey),
      const Offset(96, 120),
    );
    await tester.pump();

    expect(
      tester.getCenter(find.byKey(TodayRekaScene.rekaRenderKey)),
      isNot(before),
    );
  });

  testWidgets('live data revision gives each new output one visual owner', (
    tester,
  ) async {
    final initial = Completer<TodayData>();
    final update = Completer<TodayData>();
    final repository = _QueueRepository([initial, update]);
    final now = DateTime(2026, 8, 14, 10);
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(repository: repository, now: now),
      ),
    );
    await tester.pump();
    initial.complete(TodayData.empty);
    await tester.pumpAndSettle();

    bumpData();
    await tester.pump();
    expect(repository.loadCount, 2);
    update.complete(
      TodayData(
        chain: const [],
        noTimeTodos: const [],
        pool: const [],
        poolTrueCount: 0,
        flashCount: 0,
        rekaQueue: [
          TodayRekaItem(
            id: 'signal-new',
            type: 'report',
            title: '新报告发现',
            body: '可以生成报告方案',
            link: '',
            createdAt: now,
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final living = tester.widget<TodayLivingSurface>(
      find.byType(TodayLivingSurface),
    );
    expect(living.data.rekaQueue.single.id, 'signal-new');
    expect(living.suppressProduction, isFalse);
    expect(living.outputCoordinator?.producing?.id, 'signal-new');

    expect(
      find.byKey(const ValueKey('today-output-signal-signal-new')),
      findsNothing,
    );
    expect(find.text('新报告发现'), findsNothing);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(find.text('新报告发现'), findsOneWidget);
    expect(living.outputCoordinator?.producing, isNull);
    expect(
      find.byKey(const ValueKey('today-output-signal-signal-new')),
      findsNothing,
    );
  });

  testWidgets('quick actions invoke only the selected callback', (
    tester,
  ) async {
    final counts = <TodayRekaAction, int>{
      for (final action in TodayRekaAction.values) action: 0,
    };

    for (final selected in TodayRekaAction.values) {
      await tester.pumpWidget(
        _Host(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTodayRekaQuickActions(
                context,
                anchor: const Rect.fromLTWH(32, 420, 200, 200),
                onManualRecord: () => counts[TodayRekaAction.manualRecord] =
                    counts[TodayRekaAction.manualRecord]! + 1,
                onCreateReport: () => counts[TodayRekaAction.createReport] =
                    counts[TodayRekaAction.createReport]! + 1,
                onStartChat: () => counts[TodayRekaAction.startChat] =
                    counts[TodayRekaAction.startChat]! + 1,
              ),
              child: const Text('打开菜单'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();
      expect(find.text('手动记录'), findsOneWidget);
      expect(find.text('创建报告'), findsOneWidget);
      expect(find.text('开始新聊天'), findsOneWidget);

      await tester.tap(find.text(selected.label));
      await tester.pumpAndSettle();

      for (final action in TodayRekaAction.values) {
        expect(counts[action], action == selected ? 1 : 0);
      }
      counts[selected] = 0;
    }
  });

  testWidgets('empty scene refreshes once and emits one Reka pulse', (
    tester,
  ) async {
    final response = Completer<TodayData>();
    final repository = _QueueRepository([response]);
    final semantics = tester.ensureSemantics();
    var latestRefreshSignal = 0;
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: repository,
          rekaBuilder:
              (
                context,
                pose,
                active,
                reduceMotion,
                refreshSignal,
                cue,
                captureCue,
              ) {
                latestRefreshSignal = refreshSignal;
                return const SizedBox.expand();
              },
        ),
      ),
    );

    final refreshIndicator = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(refreshIndicator.show());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.loadCount, 1);
    expect(latestRefreshSignal, 1);
    expect(find.bySemanticsLabel('正在刷新今日'), findsOneWidget);
    expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(TodayDotExperimentPage.scrollKey),
          )
          .physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );

    refreshIndicator.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.loadCount, 1);
    expect(latestRefreshSignal, 1);

    response.complete(TodayData.empty);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('正在刷新今日'), findsNothing);
    expect(find.text('今天很安静，我在这里。'), findsNothing);
    semantics.dispose();
  });

  testWidgets('refresh failure preserves the scene and retries', (
    tester,
  ) async {
    final first = Completer<TodayData>();
    final retry = Completer<TodayData>();
    final repository = _QueueRepository([first, retry]);
    var latestRefreshSignal = 0;
    await tester.pumpWidget(
      _Host(
        child: TodayDotExperimentPage(
          repository: repository,
          rekaBuilder:
              (
                context,
                pose,
                active,
                reduceMotion,
                refreshSignal,
                cue,
                captureCue,
              ) {
                latestRefreshSignal = refreshSignal;
                return const SizedBox.expand();
              },
        ),
      ),
    );

    final refreshIndicator = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(refreshIndicator.show());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    first.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(latestRefreshSignal, 1);
    expect(find.byKey(TodayRekaScene.backgroundKey), findsOneWidget);
    expect(find.text('刷新失败，已保留当前场景'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(repository.loadCount, 2);
    expect(latestRefreshSignal, 2);

    retry.complete(TodayData.empty);
    await tester.pumpAndSettle();
    expect(find.text('刷新失败，已保留当前场景'), findsNothing);
  });
}

class _QueueRepository implements ThemeV2HomeRepository {
  _QueueRepository(this.responses);

  final List<Completer<TodayData>> responses;
  int loadCount = 0;

  @override
  Future<TodayData> load() {
    final response = responses[loadCount];
    loadCount++;
    return response.future;
  }
}

class _ImmediateRepository implements ThemeV2HomeRepository {
  _ImmediateRepository(this.data);

  final TodayData data;
  int loadCount = 0;

  @override
  Future<TodayData> load() async {
    loadCount++;
    return data;
  }
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildThemeV2Theme(Brightness.light),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(411, 860),
        devicePixelRatio: 1,
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: Scaffold(body: child),
    ),
  );
}

class _RekaVoiceService implements VoiceInputServiceClient {
  _RekaVoiceService(this.session);

  final _RekaVoiceSession session;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async {
    session.modeValue = mode;
    return session;
  }
}

class _FailingRekaVoiceService implements VoiceInputServiceClient {
  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) {
    throw const VoiceInputException(
      VoiceInputErrorCode.connectionFailed,
      retryable: true,
    );
  }
}

class _RekaVoiceSession implements VoiceInputSessionHandle {
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>.broadcast();
  VoiceInputMode modeValue = VoiceInputMode.ordinary;
  int stopCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;

  void emit(VoiceInputEvent event) => _events.add(event);

  @override
  String get voiceSessionId => 'reka-page-session';

  @override
  VoiceInputMode get mode => modeValue;

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> cancel() async => cancelCount++;

  @override
  Future<void> dispose() async => disposeCount++;
}
