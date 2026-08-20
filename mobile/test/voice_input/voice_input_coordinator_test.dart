import 'dart:async';

import 'package:eureka/voice_input/voice_input_coordinator.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_scope.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latest target supersedes active target without a busy error', () async {
    final firstSession = _FakeSession('first');
    final secondSession = _FakeSession('second');
    final service = _QueueService([
      () async => firstSession,
      () async => secondSession,
    ]);
    final coordinator = VoiceInputCoordinator(service: service);
    final firstEvents = _TargetEvents();
    final secondEvents = _TargetEvents();
    final first = coordinator.bind(
      targetId: 'session',
      mode: VoiceInputMode.ordinary,
      callbacks: firstEvents.callbacks,
    );
    final second = coordinator.bind(
      targetId: 'report',
      mode: VoiceInputMode.ordinary,
      callbacks: secondEvents.callbacks,
    );

    expect(await first.start(), isTrue);
    firstSession.emit(_partial(1, 'temporary'));
    await pumpEventQueue();
    expect(firstEvents.transcripts.single.text, 'temporary');

    expect(await second.start(), isTrue);

    expect(firstEvents.cancelled, [VoiceInputCancelReason.superseded]);
    expect(firstEvents.failures, isEmpty);
    expect(firstSession.cancelCount, 1);
    expect(first.state, VoiceInputCoordinatorState.idle);
    expect(second.state, VoiceInputCoordinatorState.listening);

    firstSession.emit(_final(2, 'late old result'));
    secondSession.emit(_final(1, 'new result'));
    await pumpEventQueue();
    expect(firstEvents.transcripts.map((event) => event.text), ['temporary']);
    expect(secondEvents.transcripts.map((event) => event.text), ['new result']);
    expect(second.state, VoiceInputCoordinatorState.idle);
  });

  test(
    'switch during connecting interrupts old start and starts latest',
    () async {
      final firstStart = Completer<VoiceInputSessionHandle>();
      final secondSession = _FakeSession('second');
      late _QueueService service;
      service = _QueueService(
        [() => firstStart.future, () async => secondSession],
        onCancelActive: () {
          if (!firstStart.isCompleted) {
            firstStart.completeError(
              const VoiceInputException(VoiceInputErrorCode.connectionFailed),
            );
          }
        },
      );
      final coordinator = VoiceInputCoordinator(service: service);
      final firstEvents = _TargetEvents();
      final secondEvents = _TargetEvents();
      final first = coordinator.bind(
        targetId: 'session',
        mode: VoiceInputMode.ordinary,
        callbacks: firstEvents.callbacks,
      );
      final second = coordinator.bind(
        targetId: 'skill',
        mode: VoiceInputMode.ordinary,
        callbacks: secondEvents.callbacks,
      );

      final firstResult = first.start();
      await _waitUntil(() => service.startCount == 1);
      final secondResult = second.start();

      expect(await firstResult, isFalse);
      expect(await secondResult, isTrue);
      expect(firstEvents.cancelled, [VoiceInputCancelReason.superseded]);
      expect(firstEvents.failures, isEmpty);
      expect(service.cancelActiveCount, greaterThanOrEqualTo(1));
      expect(second.state, VoiceInputCoordinatorState.listening);
    },
  );

  test(
    'rapid requests serialize and only latest queued target starts',
    () async {
      final firstSession = _FakeSession('first');
      final latestSession = _FakeSession('latest');
      final service = _QueueService([
        () async => firstSession,
        () async => latestSession,
      ]);
      final coordinator = VoiceInputCoordinator(service: service);
      final firstEvents = _TargetEvents();
      final middleEvents = _TargetEvents();
      final latestEvents = _TargetEvents();
      final first = coordinator.bind(
        targetId: 'session',
        mode: VoiceInputMode.ordinary,
        callbacks: firstEvents.callbacks,
      );
      final middle = coordinator.bind(
        targetId: 'report',
        mode: VoiceInputMode.ordinary,
        callbacks: middleEvents.callbacks,
      );
      final latest = coordinator.bind(
        targetId: 'reka',
        mode: VoiceInputMode.reka,
        callbacks: latestEvents.callbacks,
      );
      await first.start();

      final middleResult = middle.start();
      final latestResult = latest.start();

      expect(await middleResult, isFalse);
      expect(await latestResult, isTrue);
      expect(service.startCount, 2);
      expect(service.startedModes, [
        VoiceInputMode.ordinary,
        VoiceInputMode.reka,
      ]);
      expect(middleEvents.cancelled, [VoiceInputCancelReason.superseded]);
      expect(middleEvents.failures, isEmpty);
      expect(latest.state, VoiceInputCoordinatorState.listening);
    },
  );

  test(
    'switch while finalizing cancels old target and ignores late final',
    () async {
      final firstSession = _FakeSession('first', blockStop: true);
      final secondSession = _FakeSession('second');
      final service = _QueueService([
        () async => firstSession,
        () async => secondSession,
      ]);
      final coordinator = VoiceInputCoordinator(service: service);
      final firstEvents = _TargetEvents();
      final secondEvents = _TargetEvents();
      final first = coordinator.bind(
        targetId: 'session',
        mode: VoiceInputMode.ordinary,
        callbacks: firstEvents.callbacks,
      );
      final second = coordinator.bind(
        targetId: 'report',
        mode: VoiceInputMode.ordinary,
        callbacks: secondEvents.callbacks,
      );
      await first.start();

      final stop = first.stop();
      await _waitUntil(() => firstSession.stopCount == 1);
      expect(first.state, VoiceInputCoordinatorState.finalizing);
      final startSecond = second.start();

      await stop;
      expect(await startSecond, isTrue);
      firstSession.emit(_final(1, 'must be ignored'));
      await pumpEventQueue();
      expect(firstEvents.cancelled, [VoiceInputCancelReason.superseded]);
      expect(firstEvents.transcripts, isEmpty);
      expect(second.state, VoiceInputCoordinatorState.listening);
    },
  );

  test(
    'lifecycle cancellation invalidates immediately and remains reusable',
    () async {
      final firstSession = _FakeSession('first');
      final secondSession = _FakeSession('second');
      final service = _QueueService([
        () async => firstSession,
        () async => secondSession,
      ]);
      final coordinator = VoiceInputCoordinator(service: service);
      final firstEvents = _TargetEvents();
      final secondEvents = _TargetEvents();
      final first = coordinator.bind(
        targetId: 'session',
        mode: VoiceInputMode.ordinary,
        callbacks: firstEvents.callbacks,
      );
      final second = coordinator.bind(
        targetId: 'session-again',
        mode: VoiceInputMode.ordinary,
        callbacks: secondEvents.callbacks,
      );
      await first.start();

      final cleanup = coordinator.cancelActive(
        VoiceInputCancelReason.appLifecycle,
      );
      expect(first.state, VoiceInputCoordinatorState.idle);
      expect(firstEvents.cancelled, [VoiceInputCancelReason.appLifecycle]);
      await cleanup;
      firstSession.emit(_final(1, 'late'));
      await pumpEventQueue();
      expect(firstEvents.transcripts, isEmpty);

      expect(await second.start(), isTrue);
      expect(second.state, VoiceInputCoordinatorState.listening);
    },
  );

  test('active failure is normalized and a later target can start', () async {
    final failedSession = _FakeSession('failed');
    final recoveredSession = _FakeSession('recovered');
    final service = _QueueService([
      () async => failedSession,
      () async => recoveredSession,
    ]);
    final coordinator = VoiceInputCoordinator(service: service);
    final failedEvents = _TargetEvents();
    final recoveredEvents = _TargetEvents();
    final failed = coordinator.bind(
      targetId: 'failed',
      mode: VoiceInputMode.ordinary,
      callbacks: failedEvents.callbacks,
    );
    final recovered = coordinator.bind(
      targetId: 'recovered',
      mode: VoiceInputMode.ordinary,
      callbacks: recoveredEvents.callbacks,
    );
    await failed.start();

    failedSession.emit(
      const VoiceInputFailure(
        code: VoiceInputErrorCode.serviceUnavailable,
        retryable: true,
      ),
    );
    await pumpEventQueue();

    expect(failedEvents.failures, [VoiceInputErrorCode.serviceUnavailable]);
    expect(failed.state, VoiceInputCoordinatorState.idle);
    expect(await recovered.start(), isTrue);
  });

  testWidgets('root host cancels on lifecycle and auth identity changes', (
    tester,
  ) async {
    final firstSession = _FakeSession('first');
    final secondSession = _FakeSession('second');
    final service = _QueueService([
      () async => firstSession,
      () async => secondSession,
    ]);
    final identity = _SessionIdentity();
    VoiceInputCoordinator? coordinator;

    await tester.pumpWidget(
      VoiceInputHost(
        service: service,
        sessionListenable: identity,
        sessionIdentity: () => identity.value,
        child: Builder(
          builder: (context) {
            coordinator = VoiceInputScope.of(context).coordinator;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final lifecycleEvents = _TargetEvents();
    final lifecycleBinding = coordinator!.bind(
      targetId: 'lifecycle',
      mode: VoiceInputMode.ordinary,
      callbacks: lifecycleEvents.callbacks,
    );
    await lifecycleBinding.start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(lifecycleEvents.cancelled, [VoiceInputCancelReason.appLifecycle]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(firstSession.cancelCount, 1);

    final authEvents = _TargetEvents();
    final authBinding = coordinator!.bind(
      targetId: 'auth',
      mode: VoiceInputMode.ordinary,
      callbacks: authEvents.callbacks,
    );
    await authBinding.start();
    identity.value += 1;
    identity.notifyListeners();
    await tester.pump();

    expect(authEvents.cancelled, [VoiceInputCancelReason.authentication]);
    await tester.pump();
    expect(secondSession.cancelCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

VoiceTranscriptEvent _partial(int sequence, String text) =>
    VoiceTranscriptEvent(
      kind: VoiceTranscriptKind.partial,
      sequence: sequence,
      text: text,
    );

VoiceTranscriptEvent _final(int sequence, String text) => VoiceTranscriptEvent(
  kind: VoiceTranscriptKind.finalTranscript,
  sequence: sequence,
  text: text,
  audioDurationMs: 100,
);

Future<void> _waitUntil(bool Function() predicate) async {
  for (var index = 0; index < 20; index++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('condition did not become true');
}

final class _TargetEvents {
  int activations = 0;
  final List<VoiceTranscriptEvent> transcripts = [];
  final List<VoiceInputCancelReason> cancelled = [];
  final List<VoiceInputErrorCode> failures = [];

  late final VoiceInputTargetCallbacks callbacks = VoiceInputTargetCallbacks(
    onActivated: () => activations += 1,
    onTranscript: transcripts.add,
    onCancelled: cancelled.add,
    onFailure: failures.add,
  );
}

final class _QueueService
    implements VoiceInputServiceClient, VoiceInputServiceCancellation {
  _QueueService(this._starts, {this.onCancelActive});

  final List<Future<VoiceInputSessionHandle> Function()> _starts;
  final void Function()? onCancelActive;
  final List<VoiceInputMode> startedModes = [];
  int startCount = 0;
  int cancelActiveCount = 0;
  _FakeSession? _active;

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) async {
    startedModes.add(mode);
    final value = await _starts[startCount++]();
    if (value is _FakeSession) _active = value;
    return value;
  }

  @override
  Future<void> cancelActive() async {
    cancelActiveCount += 1;
    onCancelActive?.call();
    final active = _active;
    _active = null;
    await active?.cancel();
  }
}

final class _FakeSession implements VoiceInputSessionHandle {
  _FakeSession(this.voiceSessionId, {this.blockStop = false});

  @override
  final String voiceSessionId;
  final bool blockStop;
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>();
  final Completer<void> _stopCompleter = Completer<void>();
  int stopCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;

  void emit(VoiceInputEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Stream<VoiceInputEvent> get events => _events.stream;

  @override
  VoiceInputMode get mode => VoiceInputMode.ordinary;

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (blockStop) await _stopCompleter.future;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    if (!_stopCompleter.isCompleted) _stopCompleter.complete();
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _SessionIdentity extends ChangeNotifier {
  int value = 0;
}
