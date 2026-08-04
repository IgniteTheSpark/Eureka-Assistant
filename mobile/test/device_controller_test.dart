import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/device/card_unbind_sync.dart';
import 'package:eureka/device/device_controller.dart';

void main() {
  test('successful unbind wins over an older bound-device refresh', () async {
    final transport = _DeferredRefreshTransport();
    final controller = DeviceController(transport)
      ..device = _boundDevice
      ..state = DeviceConnState.connected;

    final refresh = controller.refreshBoundDevice();
    await transport.loadStarted.future;

    final result = await controller.unbind(deleteData: false);
    transport.completeRefresh(_boundDevice);
    await refresh;

    expect(result, isNotNull);
    expect(controller.device, isNull);
    expect(controller.state, DeviceConnState.idle);

    controller.dispose();
  });

  test(
    'successful unbind also wins over a refresh started while unbinding',
    () async {
      final transport = _DeferredUnbindTransport();
      final controller = DeviceController(transport)
        ..device = _boundDevice
        ..state = DeviceConnState.connected;

      final unbind = controller.unbind(deleteData: false);
      await transport.unbindStarted.future;

      await controller.refreshBoundDevice();
      transport.completeUnbind();
      final result = await unbind;

      expect(result, isNotNull);
      expect(controller.device, isNull);
      expect(controller.state, DeviceConnState.idle);

      controller.dispose();
    },
  );

  test('logout wins over an older bound-device refresh', () async {
    final transport = _DeferredRefreshTransport();
    final controller = DeviceController(transport)
      ..device = _boundDevice
      ..state = DeviceConnState.connected;

    final refresh = controller.refreshBoundDevice();
    await transport.loadStarted.future;

    await controller.disconnectForLogout();
    transport.completeRefresh(_boundDevice);
    await refresh;

    expect(controller.device, isNull);
    expect(controller.state, DeviceConnState.idle);

    controller.dispose();
  });

  test('disconnect event wins over an older bound-device refresh', () async {
    final transport = _DeferredRefreshTransport();
    final controller = DeviceController(transport)
      ..device = _boundDevice
      ..state = DeviceConnState.connected;

    final refresh = controller.refreshBoundDevice();
    await transport.loadStarted.future;

    transport.emitConnectionState(false);
    await Future<void>.delayed(Duration.zero);
    transport.completeRefresh(_boundDevice);
    await refresh;

    expect(controller.device, isNull);
    expect(controller.state, DeviceConnState.idle);

    controller.dispose();
  });

  test('new connect wins over an older bound-device refresh', () async {
    final transport = _DeferredRefreshTransport();
    final controller = DeviceController(transport)
      ..device = _boundDevice
      ..state = DeviceConnState.connected;

    final refresh = controller.refreshBoundDevice();
    await transport.loadStarted.future;

    await controller.connect(
      const DiscoveredDevice(id: 'new-device', name: 'W2(BLE)', serial: 'SN2'),
    );
    transport.completeRefresh(_boundDevice);
    await refresh;

    expect(controller.device?.serial, 'SN2');
    expect(controller.state, DeviceConnState.connected);

    controller.dispose();
  });

  test(
    'BLE unbind returns after durable enqueue while bounded sync runs in background',
    () async {
      final store = _UnbindSyncStore();
      final coordinator = CardUnbindSyncCoordinator(
        store: store,
        api: _NeverUnbindApi(),
        requestTimeout: const Duration(milliseconds: 10),
      );
      final hardware = _FakeCardUnbindHardware();
      final transport = BleDeviceTransport(
        unbindSync: coordinator,
        unbindHardware: hardware,
      );

      final result = await transport
          .unbind(_boundDevice, deleteData: false)
          .timeout(const Duration(milliseconds: 100));

      expect(hardware.operations, ['unbind:false', 'clear-bind-info']);
      expect(result.serverSynced, isFalse);
      expect(result.serverSync, isNotNull);
      expect(store.values, {_boundDevice.bindingId: isA<PendingCardUnbind>()});

      final serverSync = await result.serverSync!;
      expect(serverSync.serverSynced, isFalse);
      expect(store.values.keys, {_boundDevice.bindingId});
    },
  );

  test(
    'controller clears locally before background sync reports failure',
    () async {
      final serverSync = Completer<CardUnbindSyncResult>();
      final transport = _BackgroundUnbindTransport(serverSync.future);
      final controller = DeviceController(transport)
        ..device = _boundDevice
        ..state = DeviceConnState.connected;

      final result = await controller.unbind(deleteData: false);

      expect(result, isNotNull);
      expect(controller.device, isNull);
      expect(controller.state, DeviceConnState.idle);
      expect(controller.errorMessage, isNull);

      serverSync.complete(const CardUnbindSyncResult.pending('binding-1'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.device, isNull);
      expect(controller.state, DeviceConnState.idle);
      expect(controller.errorMessage, cardUnbindSyncPendingWarning);

      controller.dispose();
    },
  );

  test(
    'background sync warning survives a disconnected state refresh',
    () async {
      final serverSync = Completer<CardUnbindSyncResult>();
      final transport = _BackgroundUnbindTransport(serverSync.future);
      final controller = DeviceController(transport)
        ..device = _boundDevice
        ..state = DeviceConnState.connected;

      await controller.unbind(deleteData: false);
      await controller.refreshBoundDevice();
      serverSync.complete(const CardUnbindSyncResult.pending('binding-1'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.device, isNull);
      expect(controller.state, DeviceConnState.idle);
      expect(controller.errorMessage, cardUnbindSyncPendingWarning);

      controller.dispose();
    },
  );

  test('device disconnect event clears connected state', () async {
    final transport = MockDeviceTransport();
    final controller = DeviceController(transport);
    final device = await transport.connect(
      const DiscoveredDevice(
        id: 'device-id',
        name: 'W2(BLE)',
        serial: 'SN1',
        cardMac: 'MAC1',
      ),
    );
    controller
      ..device = device
      ..discovered = const [
        DiscoveredDevice(id: 'device-id', name: 'W2(BLE)', serial: 'SN1'),
      ]
      ..state = DeviceConnState.connected;

    transport.emitConnectionState(false);
    await Future<void>.delayed(Duration.zero);

    expect(controller.device, isNull);
    expect(controller.discovered, isEmpty);
    expect(controller.state, DeviceConnState.idle);

    controller.dispose();
  });

  test('disconnectForLogout disconnects without unbinding', () async {
    final transport = MockDeviceTransport();
    final controller = DeviceController(transport);
    final device = await transport.connect(
      const DiscoveredDevice(
        id: 'device-id',
        name: 'W2(BLE)',
        serial: 'SN1',
        cardMac: 'MAC1',
      ),
    );
    controller
      ..device = device
      ..discovered = const [
        DiscoveredDevice(id: 'device-id', name: 'W2(BLE)', serial: 'SN1'),
      ]
      ..state = DeviceConnState.connected;

    await controller.disconnectForLogout();

    expect(transport.disconnectCalls, 1);
    expect(transport.unbindCalls, 0);
    expect(controller.device, isNull);
    expect(controller.discovered, isEmpty);
    expect(controller.state, DeviceConnState.idle);
    expect(transport.deviceConnected, isFalse);

    controller.dispose();
  });

  test(
    'local unbind success clears device when server sync is pending',
    () async {
      final transport = _UnbindTransport(
        result: const DeviceUnbindResult(
          serverSynced: false,
          message: '设备已解绑，服务端同步待重试',
        ),
      );
      final controller = DeviceController(transport)
        ..device = _boundDevice
        ..discovered = const [
          DiscoveredDevice(id: 'device-id', name: 'W2(BLE)', serial: 'SN1'),
        ]
        ..state = DeviceConnState.connected;

      final result = await controller.unbind(deleteData: false);

      expect(result?.serverSynced, isFalse);
      expect(controller.device, isNull);
      expect(controller.discovered, isEmpty);
      expect(controller.state, DeviceConnState.idle);
      expect(controller.errorMessage, '设备已解绑，服务端同步待重试');

      controller.dispose();
    },
  );

  test('hardware unbind failure retains the bound device', () async {
    final transport = _UnbindTransport(
      error: const DeviceOperationException('硬件解绑失败'),
      emitDisconnectBeforeError: true,
    );
    final controller = DeviceController(transport)
      ..device = _boundDevice
      ..state = DeviceConnState.connected;

    final result = await controller.unbind(deleteData: false);
    await Future<void>.delayed(Duration.zero);

    expect(result, isNull);
    expect(controller.device, same(_boundDevice));
    expect(controller.state, DeviceConnState.error);
    expect(controller.errorMessage, '硬件解绑失败');

    controller.dispose();
  });
}

const _boundDevice = DeviceInfo(
  id: 'device-id',
  bindingId: 'binding-1',
  name: 'UReka 录音卡',
  serial: 'SN1',
  cardDeviceUuid: 'device-uuid',
  cardAppUuid: 'app-uuid',
  cardMac: 'AA:BB',
);

class _UnbindTransport extends MockDeviceTransport {
  _UnbindTransport({
    this.result,
    this.error,
    this.emitDisconnectBeforeError = false,
  });

  final DeviceUnbindResult? result;
  final DeviceOperationException? error;
  final bool emitDisconnectBeforeError;

  @override
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  }) async {
    final failure = error;
    if (failure != null) {
      if (emitDisconnectBeforeError) emitConnectionState(false);
      throw failure;
    }
    return result ?? const DeviceUnbindResult.complete();
  }
}

class _DeferredRefreshTransport extends _UnbindTransport {
  _DeferredRefreshTransport() : super();

  final loadStarted = Completer<void>();
  final _loaded = Completer<DeviceInfo?>();

  void completeRefresh(DeviceInfo? device) => _loaded.complete(device);

  @override
  Future<bool> isDeviceConnected() async => true;

  @override
  Future<DeviceInfo?> loadBoundDevice() {
    if (!loadStarted.isCompleted) loadStarted.complete();
    return _loaded.future;
  }

  @override
  Future<DeviceInfo> connect(DiscoveredDevice device) async => DeviceInfo(
    id: device.id,
    bindingId: 'binding-2',
    name: 'UReka 录音卡',
    serial: device.serial,
    cardDeviceUuid: 'device-uuid-2',
    cardAppUuid: 'app-uuid-2',
    cardMac: device.cardMac,
  );
}

class _DeferredUnbindTransport extends _UnbindTransport {
  _DeferredUnbindTransport() : super();

  final unbindStarted = Completer<void>();
  final _unbind = Completer<void>();

  void completeUnbind() => _unbind.complete();

  @override
  Future<bool> isDeviceConnected() async => true;

  @override
  Future<DeviceInfo?> loadBoundDevice() async => _boundDevice;

  @override
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  }) async {
    unbindStarted.complete();
    await _unbind.future;
    return const DeviceUnbindResult.complete();
  }
}

class _BackgroundUnbindTransport extends _UnbindTransport {
  _BackgroundUnbindTransport(this.serverSync) : super();

  final Future<CardUnbindSyncResult> serverSync;

  @override
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  }) async => DeviceUnbindResult.pending(serverSync: serverSync);
}

class _FakeCardUnbindHardware implements CardUnbindHardware {
  final List<String> operations = [];

  @override
  Future<void> clearBindInfo() async => operations.add('clear-bind-info');

  @override
  Future<void> unbind({required bool deleteData}) async {
    operations.add('unbind:$deleteData');
  }
}

class _UnbindSyncStore implements CardUnbindSyncStore {
  final Map<String, PendingCardUnbind> values = {};

  @override
  Future<void> clear({
    String? accountScope,
    required PendingCardUnbind expectedRequest,
  }) async {
    if (values[expectedRequest.bindingId] == expectedRequest) {
      values.remove(expectedRequest.bindingId);
    }
  }

  @override
  Future<Map<String, PendingCardUnbind>> readAll({
    String? accountScope,
  }) async => Map.unmodifiable(values);

  @override
  Future<void> write(PendingCardUnbind request, {String? accountScope}) async {
    values[request.bindingId] = request;
  }
}

class _NeverUnbindApi implements CardUnbindSyncApi {
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) =>
      Completer<dynamic>().future;
}
