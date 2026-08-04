import 'package:flutter/foundation.dart';

import '../../device/device_controller.dart';
import '../../ring/ring_connection.dart';
import 'device_status_summary.dart';

@immutable
class ThemeV2DeviceStatusSnapshot {
  const ThemeV2DeviceStatusSnapshot({
    this.cardState = DeviceConnState.idle,
    this.cardIsBound = false,
    this.cardError,
    this.ringConnected = false,
  });

  final DeviceConnState cardState;
  final bool cardIsBound;
  final Object? cardError;
  final bool ringConnected;
}

/// Read-only bridge from the mature hardware controllers into Theme V2.
///
/// It owns no BLE or ring lifecycle. Production continues to start and manage
/// those services at the app boundary; this adapter only listens and maps their
/// current state into the shell's stable presentation contract.
class ThemeV2DeviceStatusAdapter extends ChangeNotifier
    implements ValueListenable<DeviceStatusSummary> {
  factory ThemeV2DeviceStatusAdapter({
    DeviceController? deviceController,
    RingConnection? ringConnection,
  }) {
    final card = deviceController ?? DeviceController.instance;
    final ring = ringConnection ?? RingConnection.instance;
    return ThemeV2DeviceStatusAdapter._(
      changes: Listenable.merge([card, ring]),
      readSnapshot: () => ThemeV2DeviceStatusSnapshot(
        cardState: card.state,
        cardIsBound: card.isBound,
        cardError: card.error,
        ringConnected: ring.isConnected,
      ),
    );
  }

  @visibleForTesting
  factory ThemeV2DeviceStatusAdapter.fromSnapshots(
    ValueListenable<ThemeV2DeviceStatusSnapshot> snapshots,
  ) {
    return ThemeV2DeviceStatusAdapter._(
      changes: snapshots,
      readSnapshot: () => snapshots.value,
    );
  }

  ThemeV2DeviceStatusAdapter._({
    required Listenable changes,
    required ThemeV2DeviceStatusSnapshot Function() readSnapshot,
  }) : _changes = changes,
       _readSnapshot = readSnapshot {
    _value = summarize(_readSnapshot());
    _changes.addListener(_handleChanges);
  }

  final Listenable _changes;
  final ThemeV2DeviceStatusSnapshot Function() _readSnapshot;
  late DeviceStatusSummary _value;

  @override
  DeviceStatusSummary get value => _value;

  static DeviceStatusSummary summarize(ThemeV2DeviceStatusSnapshot snapshot) {
    final presence = switch ((snapshot.cardIsBound, snapshot.ringConnected)) {
      (false, false) => ThemeV2DevicePresence.none,
      (true, false) => ThemeV2DevicePresence.card,
      (false, true) => ThemeV2DevicePresence.ring,
      (true, true) => ThemeV2DevicePresence.both,
    };
    final cardNeedsAttention =
        snapshot.cardIsBound &&
        (snapshot.cardState == DeviceConnState.error ||
            snapshot.cardError != null);
    if (cardNeedsAttention) {
      return DeviceStatusSummary.attention(
        presence: presence,
        label: '录音卡需要处理',
      );
    }

    final cardConnected =
        snapshot.cardState == DeviceConnState.connected && snapshot.cardIsBound;
    if (cardConnected && snapshot.ringConnected) {
      return const DeviceStatusSummary.connected(
        presence: ThemeV2DevicePresence.both,
        label: '双设备已连接',
      );
    }
    if (snapshot.ringConnected) {
      return const DeviceStatusSummary.connected(
        presence: ThemeV2DevicePresence.ring,
        label: '戒指已连接',
      );
    }
    if (cardConnected) {
      return const DeviceStatusSummary.connected(
        presence: ThemeV2DevicePresence.card,
        label: '录音卡已连接',
      );
    }
    return const DeviceStatusSummary.disconnected();
  }

  void _handleChanges() {
    final next = summarize(_readSnapshot());
    if (next.kind == _value.kind &&
        next.label == _value.label &&
        next.presence == _value.presence) {
      return;
    }
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _changes.removeListener(_handleChanges);
    super.dispose();
  }
}
