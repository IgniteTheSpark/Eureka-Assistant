import 'dart:async';

import 'package:flutter/foundation.dart';

/// Hardware-connection layer for the EurekaMind 录音卡 (W1/W2 BLE card).
///
/// The UI talks only to [DeviceController], which talks to a [DeviceTransport].
/// Today the transport is [MockDeviceTransport] (simulated scan/connect) so the
/// pairing + device screens can be built and verified without hardware. The
/// real iOS implementation (ported from FlashType's Swift BLE + Opus code,
/// exposed over a MethodChannel/EventChannel) drops in behind this same
/// interface — no UI changes needed.

enum DeviceConnState { idle, scanning, connecting, connected, error }

/// A device surfaced during a scan (before connecting).
@immutable
class DiscoveredDevice {
  final String id;
  final String name; // e.g. "W2(BLE)"
  final String serial; // SN printed on the device screen
  const DiscoveredDevice({required this.id, required this.name, required this.serial});
}

/// A connected/bound device's live info.
@immutable
class DeviceInfo {
  final String id;
  final String name; // e.g. "EurekaMind 录音卡"
  final String serial;
  final int batteryPct;
  final double storageUsedGb;
  final double storageTotalGb;
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.serial,
    required this.batteryPct,
    required this.storageUsedGb,
    required this.storageTotalGb,
  });
}

/// The seam the real BLE plugin will implement. Keep it tiny + transport-only;
/// all state/UX lives in [DeviceController].
abstract class DeviceTransport {
  /// Emits the growing list of discovered devices while scanning.
  Stream<List<DiscoveredDevice>> scan();

  /// Connect + bind to a discovered device, returning its live info.
  Future<DeviceInfo> connect(DiscoveredDevice device);

  /// Unbind. [deleteData] also wipes the on-device recordings.
  Future<void> unbind({required bool deleteData});
}

/// Simulated transport so the pairing/device UI works with no hardware. Mirrors
/// the real flow's timing so the screens feel right (search → discover →
/// connect → info). Replace with the iOS BLE plugin behind [DeviceTransport].
class MockDeviceTransport implements DeviceTransport {
  static const _device = DiscoveredDevice(
    id: 'w2-ble-mock',
    name: 'W2(BLE)',
    serial: '474204126010000003',
  );

  @override
  Stream<List<DiscoveredDevice>> scan() async* {
    yield const [];
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    yield const [_device];
  }

  @override
  Future<DeviceInfo> connect(DiscoveredDevice device) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return DeviceInfo(
      id: device.id,
      name: 'EurekaMind 录音卡',
      serial: device.serial,
      batteryPct: 50,
      storageUsedGb: 3.3,
      storageTotalGb: 64,
    );
  }

  @override
  Future<void> unbind({required bool deleteData}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

/// App-wide hardware connection state. Singleton so the bound device survives
/// re-opening the device screens (the header routes on [isBound]).
class DeviceController extends ChangeNotifier {
  DeviceController(this._transport);

  final DeviceTransport _transport;

  /// Swap the constructor arg to the real plugin transport when it lands.
  static final DeviceController instance = DeviceController(MockDeviceTransport());

  DeviceConnState state = DeviceConnState.idle;
  List<DiscoveredDevice> discovered = const [];
  DeviceInfo? device; // non-null once bound/connected
  Object? error;

  StreamSubscription<List<DiscoveredDevice>>? _scanSub;

  bool get isBound => device != null;

  void startScan() {
    _scanSub?.cancel();
    state = DeviceConnState.scanning;
    discovered = const [];
    error = null;
    notifyListeners();
    _scanSub = _transport.scan().listen(
      (devices) {
        discovered = devices;
        notifyListeners();
      },
      onError: (Object e) {
        error = e;
        state = DeviceConnState.error;
        notifyListeners();
      },
    );
  }

  void stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    if (state == DeviceConnState.scanning) {
      state = DeviceConnState.idle;
      notifyListeners();
    }
  }

  Future<void> connect(DiscoveredDevice d) async {
    _scanSub?.cancel();
    state = DeviceConnState.connecting;
    error = null;
    notifyListeners();
    try {
      device = await _transport.connect(d);
      state = DeviceConnState.connected;
    } catch (e) {
      error = e;
      state = DeviceConnState.error;
    }
    notifyListeners();
  }

  Future<void> unbind({required bool deleteData}) async {
    try {
      await _transport.unbind(deleteData: deleteData);
    } finally {
      device = null;
      discovered = const [];
      state = DeviceConnState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }
}
