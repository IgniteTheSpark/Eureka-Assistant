import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ring_connection.dart';
import 'ring_reconnect.dart';

@immutable
class RingDeviceInfo {
  const RingDeviceInfo({
    required this.mac,
    this.batteryPct,
    this.firmwareVersion,
    this.hardwareVersion,
  });

  final String? mac;
  final int? batteryPct;
  final String? firmwareVersion;
  final String? hardwareVersion;
}

@immutable
class RingUnbindResult {
  const RingUnbindResult({this.warning});

  final String? warning;
  bool get hasWarning => warning != null;
}

abstract interface class RingDeviceGateway {
  Future<int?> getBattery();
  Future<Map?> getVersion();
  Future<void> disconnect();
}

abstract interface class RingBindingStore {
  Future<String?> readMac();
  Future<void> clearMac();
}

class RingDeviceService {
  RingDeviceService({
    required this.gateway,
    required this.bindingStore,
    required this.forgetReconnect,
    required this.markUnbound,
  });

  factory RingDeviceService.production() => RingDeviceService(
    gateway: _ChipletRingDeviceGateway(ChipletRing()),
    bindingStore: const _SharedPreferencesRingBindingStore(),
    forgetReconnect: RingReconnect.instance.forget,
    markUnbound: RingConnection.instance.markUnbound,
  );

  final RingDeviceGateway gateway;
  final RingBindingStore bindingStore;
  final VoidCallback forgetReconnect;
  final VoidCallback markUnbound;

  Future<RingDeviceInfo> loadInfo() async {
    final mac = await bindingStore.readMac();
    int? batteryPct;
    String? firmwareVersion;
    String? hardwareVersion;

    try {
      batteryPct = await gateway.getBattery();
    } catch (_) {}

    try {
      final version = await gateway.getVersion();
      firmwareVersion = version?['fw'] as String?;
      hardwareVersion = version?['hw'] as String?;
    } catch (_) {}

    return RingDeviceInfo(
      mac: mac,
      batteryPct: batteryPct,
      firmwareVersion: firmwareVersion,
      hardwareVersion: hardwareVersion,
    );
  }

  Future<RingUnbindResult> unbind() async {
    forgetReconnect();
    Object? disconnectError;
    try {
      await gateway.disconnect();
    } catch (error) {
      disconnectError = error;
    }
    await bindingStore.clearMac();
    markUnbound();

    return disconnectError == null
        ? const RingUnbindResult()
        : const RingUnbindResult(warning: '本地绑定已解除，蓝牙断开可能未完成');
  }
}

class _ChipletRingDeviceGateway implements RingDeviceGateway {
  const _ChipletRingDeviceGateway(this._ring);

  final ChipletRing _ring;

  @override
  Future<int?> getBattery() => _ring.getBattery();

  @override
  Future<Map?> getVersion() => _ring.getVersion();

  @override
  Future<void> disconnect() => _ring.disconnect();
}

class _SharedPreferencesRingBindingStore implements RingBindingStore {
  const _SharedPreferencesRingBindingStore();

  @override
  Future<void> clearMac() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('ring_mac');
  }

  @override
  Future<String?> readMac() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('ring_mac');
  }
}
