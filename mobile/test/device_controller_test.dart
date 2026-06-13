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
}
