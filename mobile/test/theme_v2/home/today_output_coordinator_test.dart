import 'package:eureka/theme_v2/home/today_output_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first load is stable and never replays production', () {
    final coordinator = TodayOutputCoordinator();
    expect(coordinator.cue.phase, TodayOutputPhase.idle);
    coordinator.reconcile(
      assetIds: const ['asset-1'],
      signalIds: const ['signal-1'],
      rekaCenter: const Offset(80, 360),
    );

    expect(coordinator.producing, isNull);
    expect(coordinator.stableAssetIds(const ['asset-1']), ['asset-1']);
    expect(coordinator.stableSignalIds(const ['signal-1']), ['signal-1']);

    coordinator.reconcile(
      assetIds: const ['asset-1'],
      signalIds: const ['signal-1'],
      rekaCenter: const Offset(300, 500),
    );
    expect(coordinator.producing, isNull);
  });

  test('new IDs have one owner, preserve queue order and snapshot Reka', () {
    final coordinator = TodayOutputCoordinator();
    coordinator.reconcile(
      assetIds: const ['asset-1'],
      signalIds: const ['signal-1'],
      rekaCenter: const Offset(40, 300),
    );
    coordinator.reconcile(
      assetIds: const ['asset-1', 'asset-2'],
      signalIds: const ['signal-1', 'signal-2'],
      rekaCenter: const Offset(210, 420),
    );

    expect(coordinator.producing?.id, 'signal-2');
    expect(coordinator.producing?.source, const Offset(210, 420));
    expect(coordinator.cue.phase, TodayOutputPhase.charge);
    expect(coordinator.cue.kind, TodayOutputKind.signal);
    coordinator.updatePhase(TodayOutputPhase.emit);
    expect(coordinator.cue.phase, TodayOutputPhase.emit);
    expect(coordinator.queuedIds, ['asset-2']);
    expect(coordinator.stableSignalIds(const ['signal-1', 'signal-2']), [
      'signal-1',
    ]);
    expect(coordinator.stableAssetIds(const ['asset-1', 'asset-2']), [
      'asset-1',
    ]);

    coordinator.completeCurrent();
    expect(coordinator.producing?.id, 'asset-2');
    expect(coordinator.cue.phase, TodayOutputPhase.charge);
    coordinator.updatePhase(TodayOutputPhase.handoff);
    expect(coordinator.stableAssetIds(const ['asset-1', 'asset-2']), [
      'asset-1',
      'asset-2',
    ]);
    expect(coordinator.producing?.id, 'asset-2');
    coordinator.completeCurrent();
    expect(coordinator.producing, isNull);
    expect(coordinator.cue.phase, TodayOutputPhase.idle);
    expect(coordinator.lastCompletedSignalId, 'signal-2');
    expect(coordinator.stableAssetIds(const ['asset-1', 'asset-2']), [
      'asset-1',
      'asset-2',
    ]);
  });

  test('refresh, capacity fallback and cancellation release stable IDs', () {
    final coordinator = TodayOutputCoordinator();
    coordinator.reconcile(
      assetIds: const ['asset-1'],
      signalIds: const [],
      rekaCenter: Offset.zero,
    );
    coordinator.reconcile(
      assetIds: const ['asset-1', 'asset-2'],
      signalIds: const [],
      rekaCenter: const Offset(20, 20),
      suppressProduction: true,
    );
    expect(coordinator.producing, isNull);
    expect(coordinator.stableAssetIds(const ['asset-1', 'asset-2']), [
      'asset-1',
      'asset-2',
    ]);

    coordinator.reconcile(
      assetIds: const ['asset-1', 'asset-2', 'asset-3'],
      signalIds: const ['signal-1'],
      rekaCenter: const Offset(30, 30),
      capacityAvailable: false,
    );
    expect(coordinator.producing, isNull);
    expect(coordinator.stableSignalIds(const ['signal-1']), ['signal-1']);

    coordinator.reconcile(
      assetIds: const ['asset-1', 'asset-2', 'asset-3', 'asset-4'],
      signalIds: const ['signal-1', 'signal-2'],
      rekaCenter: const Offset(40, 40),
      reduceMotion: true,
    );
    expect(coordinator.producing?.reduceMotion, isTrue);
    coordinator.cancelAll();
    expect(coordinator.producing, isNull);
    expect(coordinator.queuedIds, isEmpty);
    expect(
      coordinator.stableAssetIds(const [
        'asset-1',
        'asset-2',
        'asset-3',
        'asset-4',
      ]),
      const ['asset-1', 'asset-2', 'asset-3', 'asset-4'],
    );
  });
}
