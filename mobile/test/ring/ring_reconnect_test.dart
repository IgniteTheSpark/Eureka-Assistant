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
}

class _FakeGateway implements RingReconnectGateway {
  final stateController = StreamController<RingState>.broadcast();
  var startScanCalls = 0;
  var stopScanCalls = 0;
  final List<String> connectCalls = [];

  @override
  Stream<RingState> get state => stateController.stream;

  @override
  Future<void> connect(String id) async => connectCalls.add(id);

  @override
  Future<void> startScan() async => startScanCalls += 1;

  @override
  Future<void> stopScan() async => stopScanCalls += 1;
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
