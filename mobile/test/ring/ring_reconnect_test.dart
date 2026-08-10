import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:eureka/ring/ring_reconnect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forget invalidates a delayed resume MAC read', () async {
    final gateway = _FakeGateway();
    final store = _DeferredStore();
    final reconnect = RingReconnect(gateway: gateway, bindingStore: store);
    addTearDown(reconnect.dispose);

    reconnect.resume();
    await store.readStarted.future;
    reconnect.forget();
    store.complete('AA:BB');
    await Future<void>.delayed(Duration.zero);

    expect(gateway.startScanCalls, 0);
    expect(gateway.connectCalls, isEmpty);
  });

  test('forget invalidates a delayed refreshMac read', () async {
    final gateway = _FakeGateway();
    final store = _DeferredStore();
    final reconnect = RingReconnect(gateway: gateway, bindingStore: store);
    addTearDown(reconnect.dispose);

    final refresh = reconnect.refreshMac();
    await store.readStarted.future;
    reconnect.forget();
    store.complete('CC:DD');
    await refresh;

    expect(gateway.startScanCalls, 0);
    expect(gateway.connectCalls, isEmpty);
  });

  test(
    'forget disconnects a connect that completes after invalidation',
    () async {
      final gateway = _DeferredConnectGateway();
      final reconnect = RingReconnect(
        gateway: gateway,
        bindingStore: const _ImmediateStore('AA:BB'),
      );
      addTearDown(reconnect.dispose);

      await reconnect.start();
      gateway.emit(_scanningState('AA:BB'));
      await gateway.connectStarted.future;

      reconnect.forget();
      gateway.completeConnect();
      await gateway.disconnectCompleted.future;

      gateway.emit(_scanningState('AA:BB'));
      await Future<void>.delayed(Duration.zero);

      expect(gateway.disconnectCalls, 1);
      expect(gateway.connectCalls, ['AA:BB']);
      expect(gateway.startScanCalls, 1);
    },
  );

  test(
    'normal reconnect success does not disconnect or restart scanning',
    () async {
      final gateway = _FakeGateway();
      final reconnect = RingReconnect(
        gateway: gateway,
        bindingStore: const _ImmediateStore('AA:BB'),
      );
      addTearDown(reconnect.dispose);

      await reconnect.start();
      gateway.emit(_scanningState('AA:BB'));
      await Future<void>.delayed(Duration.zero);
      gateway.emit(
        const RingState(conn: RingConnState.connected, devices: <RingDevice>[]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(gateway.connectCalls, ['AA:BB']);
      expect(gateway.disconnectCalls, 0);
      expect(gateway.startScanCalls, 1);
    },
  );

  test(
    'onConnected fires once per disconnected to connected transition',
    () async {
      final gateway = _FakeGateway();
      var connectedCount = 0;
      final reconnect = RingReconnect(
        gateway: gateway,
        bindingStore: const _ImmediateStore('AA:BB'),
        onConnected: () async => connectedCount += 1,
      );
      addTearDown(reconnect.dispose);
      await reconnect.start();

      gateway.emit(
        const RingState(conn: RingConnState.connected, devices: <RingDevice>[]),
      );
      gateway.emit(
        const RingState(conn: RingConnState.connected, devices: <RingDevice>[]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(connectedCount, 1);

      gateway.emit(
        const RingState(
          conn: RingConnState.disconnected,
          devices: <RingDevice>[],
        ),
      );
      gateway.emit(
        const RingState(conn: RingConnState.connected, devices: <RingDevice>[]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(connectedCount, 2);
    },
  );
}

RingState _scanningState(String mac) => RingState(
  conn: RingConnState.scanning,
  devices: [RingDevice(id: mac, name: 'Ring', rssi: -40)],
);

class _FakeGateway implements RingReconnectGateway {
  final stateController = StreamController<RingState>.broadcast();
  var startScanCalls = 0;
  var stopScanCalls = 0;
  var disconnectCalls = 0;
  final List<String> connectCalls = [];

  void emit(RingState state) => stateController.add(state);

  @override
  Stream<RingState> get state => stateController.stream;

  @override
  Future<void> connect(String id) async => connectCalls.add(id);

  @override
  Future<void> disconnect() async => disconnectCalls += 1;

  @override
  Future<void> startScan() async => startScanCalls += 1;

  @override
  Future<void> stopScan() async => stopScanCalls += 1;
}

class _DeferredConnectGateway extends _FakeGateway {
  final connectStarted = Completer<void>();
  final disconnectCompleted = Completer<void>();
  final _connect = Completer<void>();

  void completeConnect() => _connect.complete();

  @override
  Future<void> connect(String id) async {
    connectCalls.add(id);
    connectStarted.complete();
    await _connect.future;
  }

  @override
  Future<void> disconnect() async {
    await super.disconnect();
    disconnectCompleted.complete();
  }
}

class _ImmediateStore implements RingReconnectBindingStore {
  const _ImmediateStore(this.mac);

  final String? mac;

  @override
  Future<String?> readMac() async => mac;
}

class _DeferredStore implements RingReconnectBindingStore {
  final readStarted = Completer<void>();
  final _mac = Completer<String?>();

  void complete(String? mac) => _mac.complete(mac);

  @override
  Future<String?> readMac() {
    if (!readStarted.isCompleted) readStarted.complete();
    return _mac.future;
  }
}
