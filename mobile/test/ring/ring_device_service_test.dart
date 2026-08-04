import 'package:eureka/ring/ring_device_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unbind stops reconnect before disconnecting and clearing local binding',
    () async {
      final operations = <String>[];
      final service = RingDeviceService(
        gateway: _FakeRingGateway(operations),
        bindingStore: _FakeRingBindingStore(operations, mac: 'AA:BB'),
        forgetReconnect: () => operations.add('forget'),
        markUnbound: () => operations.add('mark-unbound'),
      );

      final result = await service.unbind();

      expect(result.hasWarning, isFalse);
      expect(operations, ['forget', 'disconnect', 'clear-mac', 'mark-unbound']);
    },
  );

  test('loadInfo maps the saved MAC and SDK version fields', () async {
    final service = RingDeviceService(
      gateway: _FakeRingGateway(
        <String>[],
        battery: 82,
        version: {'fw': '1.2', 'hw': 'A3'},
      ),
      bindingStore: _FakeRingBindingStore(<String>[], mac: 'AA:BB'),
      forgetReconnect: () {},
      markUnbound: () {},
    );

    final info = await service.loadInfo();

    expect(info.mac, 'AA:BB');
    expect(info.batteryPct, 82);
    expect(info.firmwareVersion, '1.2');
    expect(info.hardwareVersion, 'A3');
  });

  test('loadInfo tolerates missing battery and version values', () async {
    final service = RingDeviceService(
      gateway: _FakeRingGateway(<String>[]),
      bindingStore: _FakeRingBindingStore(<String>[]),
      forgetReconnect: () {},
      markUnbound: () {},
    );

    final info = await service.loadInfo();

    expect(info.mac, isNull);
    expect(info.batteryPct, isNull);
    expect(info.firmwareVersion, isNull);
    expect(info.hardwareVersion, isNull);
  });

  test(
    'unbind clears local binding and reports a warning if disconnect fails',
    () async {
      final operations = <String>[];
      final service = RingDeviceService(
        gateway: _FakeRingGateway(
          operations,
          disconnectError: StateError('lost'),
        ),
        bindingStore: _FakeRingBindingStore(operations, mac: 'AA:BB'),
        forgetReconnect: () => operations.add('forget'),
        markUnbound: () => operations.add('mark-unbound'),
      );

      final result = await service.unbind();

      expect(operations, ['forget', 'disconnect', 'clear-mac', 'mark-unbound']);
      expect(result.warning, '本地绑定已解除，蓝牙断开可能未完成');
      expect(result.hasWarning, isTrue);
    },
  );
}

class _FakeRingGateway implements RingDeviceGateway {
  _FakeRingGateway(
    this.operations, {
    this.battery,
    this.version,
    this.disconnectError,
  });

  final List<String> operations;
  final int? battery;
  final Map? version;
  final Object? disconnectError;

  @override
  Future<int?> getBattery() async => battery;

  @override
  Future<Map?> getVersion() async => version;

  @override
  Future<void> disconnect() async {
    operations.add('disconnect');
    if (disconnectError != null) throw disconnectError!;
  }
}

class _FakeRingBindingStore implements RingBindingStore {
  _FakeRingBindingStore(this.operations, {this.mac});

  final List<String> operations;
  String? mac;

  @override
  Future<void> clearMac() async {
    operations.add('clear-mac');
    mac = null;
  }

  @override
  Future<String?> readMac() async => mac;
}
