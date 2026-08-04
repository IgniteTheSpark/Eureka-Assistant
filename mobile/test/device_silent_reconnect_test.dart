import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/device/card_unbind_sync.dart';
import 'package:eureka/device/device_controller.dart';
import 'package:eureka/device/device_silent_reconnect.dart';

void main() {
  test('tryReconnect does nothing when user has no bound card', () async {
    final ble = _FakeBle();
    final controller = DeviceController(MockDeviceTransport());
    final reconnect = DeviceSilentReconnect(
      api: _FakeApi(const []),
      ble: ble,
      controller: controller,
      scanTimeout: const Duration(milliseconds: 20),
    );

    await reconnect.tryReconnect(sessionKey: 1);

    expect(ble.startScanCalls, 0);
    expect(ble.connectCalls, 0);
    expect(controller.device, isNull);

    controller.dispose();
  });

  test(
    'tryReconnect connects the first scanned device matching a binding',
    () async {
      final ble = _FakeBle()
        ..scanEvents = [_scanEvent(serial: 'SN1', cardMac: 'AA:BB')];
      final controller = DeviceController(MockDeviceTransport());
      final reconnect = DeviceSilentReconnect(
        api: _FakeApi([_binding()]),
        ble: ble,
        controller: controller,
        scanTimeout: const Duration(milliseconds: 100),
      );

      await reconnect.tryReconnect(sessionKey: 1);

      expect(ble.startScanCalls, 1);
      expect(ble.stopScanCalls, greaterThanOrEqualTo(1));
      expect(ble.connectCalls, 1);
      expect(ble.setBindInfoCalls, 1);

      controller.dispose();
    },
  );

  test(
    'tryReconnect stops scanning after timeout when no binding matches',
    () async {
      final ble = _FakeBle()
        ..scanEvents = [_scanEvent(serial: 'OTHER', cardMac: 'CC:DD')];
      final controller = DeviceController(MockDeviceTransport());
      final reconnect = DeviceSilentReconnect(
        api: _FakeApi([_binding()]),
        ble: ble,
        controller: controller,
        scanTimeout: const Duration(milliseconds: 20),
      );

      await reconnect.tryReconnect(sessionKey: 1);

      expect(ble.connectCalls, 0);
      expect(ble.stopScanCalls, greaterThanOrEqualTo(1));
      expect(controller.device, isNull);

      controller.dispose();
    },
  );

  test(
    'stop disconnects an in-flight silent reconnect without committing it',
    () async {
      final ble = _FakeBle()
        ..scanEvents = [_scanEvent(serial: 'SN1', cardMac: 'AA:BB')]
        ..connectCompleter = Completer<dynamic>();
      final controller = DeviceController(MockDeviceTransport());
      final reconnect = DeviceSilentReconnect(
        api: _FakeApi([_binding()]),
        ble: ble,
        controller: controller,
        scanTimeout: const Duration(milliseconds: 100),
      );

      final task = reconnect.tryReconnect(sessionKey: 1);
      await _waitUntil(() => ble.connectCalls == 1);
      await reconnect.stop();

      ble.connectCompleter!.complete(_connectedDevice());
      await task;

      expect(ble.disconnectCalls, greaterThanOrEqualTo(1));
      expect(controller.device, isNull);

      controller.dispose();
    },
  );

  test('pending unbind blocks reconnect when server retry fails', () async {
    final ble = _FakeBle()
      ..scanEvents = [_scanEvent(serial: 'SN1', cardMac: 'AA:BB')];
    final sync = _FakeUnbindSync()
      ..pendingIds = {'binding-1'}
      ..retrySucceeds = false;
    final controller = DeviceController(MockDeviceTransport());
    final reconnect = DeviceSilentReconnect(
      api: _FakeApi([_binding()]),
      ble: ble,
      controller: controller,
      unbindSync: sync,
      scanTimeout: const Duration(milliseconds: 100),
    );

    await reconnect.tryReconnect(sessionKey: 1);

    expect(sync.retryCalls, 1);
    expect(ble.startScanCalls, 0);
    expect(ble.connectCalls, 0);
    expect(controller.device, isNull);

    controller.dispose();
  });

  test(
    'successful pending retry allows the active binding to reconnect',
    () async {
      final ble = _FakeBle()
        ..scanEvents = [_scanEvent(serial: 'SN1', cardMac: 'AA:BB')];
      final sync = _FakeUnbindSync()
        ..pendingIds = {'binding-1'}
        ..retrySucceeds = true;
      final controller = DeviceController(MockDeviceTransport());
      final reconnect = DeviceSilentReconnect(
        api: _FakeApi([_binding()]),
        ble: ble,
        controller: controller,
        unbindSync: sync,
        scanTimeout: const Duration(milliseconds: 100),
      );

      await reconnect.tryReconnect(sessionKey: 1);

      expect(sync.retryCalls, 1);
      expect(sync.pendingIds, isEmpty);
      expect(ble.startScanCalls, 1);
      expect(ble.connectCalls, 1);

      controller.dispose();
    },
  );
}

Map<String, dynamic> _binding() => const {
  'card_id': 'card-1',
  'binding_id': 'binding-1',
  'card_nick': 'UReka 录音卡',
  'card_sn': 'SN1',
  'card_device_uuid': 'device-uuid',
  'card_app_uuid': 'app-uuid',
  'card_mac': 'AA:BB',
};

Map<String, dynamic> _scanEvent({
  required String serial,
  required String cardMac,
}) => {
  'devices': [
    {
      'name': 'W2(BLE)',
      'sn': serial,
      'cardMac': cardMac,
      'bleIdentifier': 'ble-$serial',
    },
  ],
};

Map<String, dynamic> _connectedDevice() => const {
  'SN': 'SN1',
  'uuid': 'device-uuid',
  'app_uuid': 'app-uuid',
  'cardMac': 'AA:BB',
};

class _FakeApi implements DeviceSilentReconnectApi {
  _FakeApi(this.bindings);

  final List<Map<String, dynamic>> bindings;

  @override
  Future<dynamic> getJson(String path) async {
    expect(path, '/api/cards/bindings');
    return {'bindings': bindings};
  }
}

class _FakeBle implements DeviceSilentReconnectBle {
  final _scanController = StreamController<Map<String, dynamic>>.broadcast();
  List<Map<String, dynamic>> scanEvents = const [];
  Completer<dynamic>? connectCompleter;
  int startScanCalls = 0;
  int stopScanCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int setBindInfoCalls = 0;

  @override
  Stream<Map<String, dynamic>> get devicesDiscoveredStream =>
      _scanController.stream;

  @override
  Future<bool?> checkBluetoothPermissions() async => true;

  @override
  Future<bool?> initNativeBluetoothSdk() async => true;

  @override
  Future<String?> getBluetoothStatus() async => 'poweredOn';

  @override
  Future<dynamic> startBindScanning() async {
    startScanCalls += 1;
    Future<void>(() async {
      for (final event in scanEvents) {
        if (_scanController.isClosed) return;
        _scanController.add(event);
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  @override
  Future<dynamic> stopBindScanning() async {
    stopScanCalls += 1;
  }

  @override
  Future<dynamic> connect({
    String? appUUID,
    String? deviceUUID,
    String? sn,
    String? cardMac,
    String? bleIdentifier,
  }) async {
    connectCalls += 1;
    final completer = connectCompleter;
    if (completer != null) return completer.future;
    return _connectedDevice();
  }

  @override
  Future<dynamic> setBindInfo({
    required String deviceName,
    required String deviceSN,
    required String deviceUUID,
    required String appUUID,
    required String cardMac,
  }) async {
    setBindInfoCalls += 1;
  }

  @override
  Future<dynamic> closeBLESync() async {}

  @override
  Future<dynamic> disconnect() async {
    disconnectCalls += 1;
  }
}

class _FakeUnbindSync extends CardUnbindSyncCoordinator {
  _FakeUnbindSync() : super(store: _UnusedStore(), api: _UnusedUnbindApi());

  Set<String> pendingIds = {};
  bool retrySucceeds = true;
  int retryCalls = 0;

  @override
  Future<Set<String>> pendingBindingIds() async => pendingIds;

  @override
  Future<bool> retryPending() async {
    retryCalls += 1;
    if (retrySucceeds) pendingIds = {};
    return retrySucceeds;
  }
}

class _UnusedStore implements CardUnbindSyncStore {
  @override
  Future<void> clear() async {}

  @override
  Future<PendingCardUnbind?> read() async => null;

  @override
  Future<void> write(PendingCardUnbind request) async {}
}

class _UnusedUnbindApi implements CardUnbindSyncApi {
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    throw StateError('unexpected unbind API call');
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
