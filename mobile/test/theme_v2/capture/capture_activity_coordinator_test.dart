import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CaptureActivityEvent event({
    required Set<String> aliases,
    required CaptureActivitySource source,
    required CaptureActivityPhase phase,
    bool isRealtime = false,
    String? sessionId,
    String? inputTurnId,
    int? resultCount,
    DateTime? occurredAt,
  }) => CaptureActivityEvent(
    aliases: aliases,
    source: source,
    phase: phase,
    isRealtime: isRealtime,
    sessionId: sessionId,
    inputTurnId: inputTurnId,
    resultCount: resultCount,
    occurredAt: occurredAt ?? DateTime.utc(2026, 8, 7, 1),
  );

  test('merges aliases and never regresses a capture phase', () {
    final coordinator = CaptureActivityCoordinator();
    addTearDown(coordinator.dispose);

    coordinator.apply(
      event(
        aliases: {'local:ring-1'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.listening,
        isRealtime: true,
      ),
    );
    coordinator.apply(
      event(
        aliases: {'local:ring-1', 'client:ring-task-1'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.transcribing,
        isRealtime: true,
      ),
    );
    coordinator.apply(
      event(
        aliases: {'client:ring-task-1', 'recording:recording-1'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.understanding,
        isRealtime: true,
        sessionId: 'session-1',
        inputTurnId: 'turn-1',
      ),
    );
    coordinator.apply(
      event(
        aliases: {'recording:recording-1'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.receiving,
      ),
    );

    final active = coordinator.snapshot.active!;
    expect(active.phase, CaptureActivityPhase.understanding);
    expect(
      active.aliases,
      containsAll(<String>{
        'local:ring-1',
        'client:ring-task-1',
        'recording:recording-1',
      }),
    );
    expect(active.sessionId, 'session-1');
    expect(active.inputTurnId, 'turn-1');
    expect(coordinator.snapshot.canOpenSession, isTrue);
  });

  test(
    'realtime activity preempts offline work and selection stays stable',
    () {
      final coordinator = CaptureActivityCoordinator();
      addTearDown(coordinator.dispose);

      coordinator.apply(
        event(
          aliases: {'client:offline-1'},
          source: CaptureActivitySource.card,
          phase: CaptureActivityPhase.receiving,
          occurredAt: DateTime.utc(2026, 8, 7, 0),
        ),
      );
      coordinator.apply(
        event(
          aliases: {'client:ring-1'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.listening,
          isRealtime: true,
          occurredAt: DateTime.utc(2026, 8, 7, 1),
        ),
      );
      coordinator.apply(
        event(
          aliases: {'client:card-live-2'},
          source: CaptureActivitySource.card,
          phase: CaptureActivityPhase.listening,
          isRealtime: true,
          occurredAt: DateTime.utc(2026, 8, 7, 2),
        ),
      );

      expect(coordinator.snapshot.active!.aliases, contains('client:ring-1'));
      expect(coordinator.snapshot.queuedCount, 2);
    },
  );

  test('terminal states use approved dwell and then advance the queue', () {
    final scheduled = <Duration, void Function()>{};
    final coordinator = CaptureActivityCoordinator(
      schedule: (duration, callback) => scheduled[duration] = callback,
    );
    addTearDown(coordinator.dispose);

    coordinator.apply(
      event(
        aliases: {'client:first'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.understanding,
        isRealtime: true,
      ),
    );
    coordinator.apply(
      event(
        aliases: {'client:second'},
        source: CaptureActivitySource.card,
        phase: CaptureActivityPhase.receiving,
      ),
    );
    coordinator.apply(
      event(
        aliases: {'client:first'},
        source: CaptureActivitySource.ring,
        phase: CaptureActivityPhase.done,
        isRealtime: true,
        resultCount: 3,
      ),
    );

    expect(coordinator.snapshot.active!.phase, CaptureActivityPhase.done);
    expect(coordinator.snapshot.active!.resultCount, 3);
    expect(scheduled, contains(const Duration(milliseconds: 1500)));

    scheduled[const Duration(milliseconds: 1500)]!();
    expect(coordinator.snapshot.active!.aliases, contains('client:second'));
  });

  test('failure and empty use three and two second dwell', () {
    final durations = <Duration>[];
    final failed = CaptureActivityCoordinator(
      schedule: (duration, _) => durations.add(duration),
    );
    final empty = CaptureActivityCoordinator(
      schedule: (duration, _) => durations.add(duration),
    );
    addTearDown(failed.dispose);
    addTearDown(empty.dispose);

    failed.apply(
      event(
        aliases: {'recording:failed'},
        source: CaptureActivitySource.card,
        phase: CaptureActivityPhase.failed,
      ),
    );
    empty.apply(
      event(
        aliases: {'recording:empty'},
        source: CaptureActivitySource.audioUpload,
        phase: CaptureActivityPhase.empty,
      ),
    );

    expect(
      durations,
      containsAll(<Duration>[
        const Duration(seconds: 3),
        const Duration(seconds: 2),
      ]),
    );
  });

  test('recovered upload remains display-only until a real turn exists', () {
    final coordinator = CaptureActivityCoordinator();
    addTearDown(coordinator.dispose);

    coordinator.apply(
      event(
        aliases: {'local:restored-upload'},
        source: CaptureActivitySource.audioUpload,
        phase: CaptureActivityPhase.receiving,
      ),
    );
    expect(coordinator.snapshot.canOpenSession, isFalse);

    coordinator.apply(
      event(
        aliases: {'local:restored-upload', 'recording:restored-recording'},
        source: CaptureActivitySource.audioUpload,
        phase: CaptureActivityPhase.understanding,
        sessionId: 'session-restored',
        inputTurnId: 'turn-restored',
      ),
    );
    expect(coordinator.snapshot.canOpenSession, isTrue);
  });

  test(
    'server ring recovery respects is_realtime and device capture alias',
    () {
      final recovered = CaptureActivityEvent.fromServerPayload({
        'display_phase': 'receiving',
        'source': 'ring',
        'is_realtime': false,
        'client_task_id': 'ring-file-1',
        'device_capture_key': 'ring:stable',
        'device_file_name': 'R1.bin',
        'recording_id': 'recording-1',
      });

      expect(recovered, isNotNull);
      expect(recovered!.isRealtime, isFalse);
      expect(
        recovered.aliases,
        containsAll({
          'client:ring-file-1',
          'device-capture:ring:stable',
          'device-file:R1.bin',
          'recording:recording-1',
        }),
      );
    },
  );
}
