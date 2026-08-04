import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/device/device_controller.dart';

void main() {
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
