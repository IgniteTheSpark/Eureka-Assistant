import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:br_flutter_plugin_ble/br_bluetooth_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'card_unbind_sync.dart';

/// Hardware-connection layer for the UReka 录音卡 (W1/W2 BLE card).
///
/// The UI talks only to [DeviceController]. The transport below owns the real
/// BLE plugin calls plus the server binding handshake.

enum DeviceConnState { idle, scanning, connecting, connected, error }

@immutable
class DiscoveredDevice {
  final String id;
  final String name;
  final String serial;
  final String cardMac;
  final String bleIdentifier;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.serial,
    this.cardMac = '',
    this.bleIdentifier = '',
  });
}

@immutable
class DeviceInfo {
  final String id;
  final String bindingId;
  final String name;
  final String serial;
  final String cardDeviceUuid;
  final String cardAppUuid;
  final String cardMac;
  final int? batteryPct;
  final double? storageUsedGb;
  final double? storageTotalGb;

  const DeviceInfo({
    required this.id,
    required this.bindingId,
    required this.name,
    required this.serial,
    required this.cardDeviceUuid,
    required this.cardAppUuid,
    required this.cardMac,
    this.batteryPct,
    this.storageUsedGb,
    this.storageTotalGb,
  });
}

class DeviceOperationException implements Exception {
  final String message;
  const DeviceOperationException(this.message);

  @override
  String toString() => message;
}

@immutable
class DeviceUnbindResult {
  const DeviceUnbindResult({
    required this.serverSynced,
    this.message,
    this.serverSync,
  });

  const DeviceUnbindResult.complete()
    : serverSynced = true,
      message = null,
      serverSync = null;

  const DeviceUnbindResult.pending({required this.serverSync})
    : serverSynced = false,
      message = null;

  final bool serverSynced;
  final String? message;
  final Future<CardUnbindSyncResult>? serverSync;
}

abstract interface class CardUnbindHardware {
  Future<void> unbind({required bool deleteData});

  Future<void> clearBindInfo();
}

abstract class DeviceTransport {
  Stream<String> get bluetoothStateStream;

  Stream<bool> get connectionStateStream;

  Future<bool> isBluetoothPoweredOn();

  Future<bool> isDeviceConnected();

  Future<void> ensurePermissionReady();

  Stream<List<DiscoveredDevice>> scan();

  Future<DeviceInfo> connect(DiscoveredDevice device);

  Future<DeviceInfo?> loadBoundDevice();

  Future<void> disconnect();

  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  });
}

class BleDeviceTransport implements DeviceTransport {
  BleDeviceTransport({
    BrBluetoothPlugin? ble,
    ApiClient? api,
    CardUnbindSyncCoordinator? unbindSync,
    CardUnbindHardware? unbindHardware,
  }) : _ble = ble ?? BrBluetoothPlugin.instance,
       _api = api ?? ApiClient(),
       _unbindSync = unbindSync ?? CardUnbindSyncCoordinator.production(),
       _injectedUnbindHardware = unbindHardware;

  final BrBluetoothPlugin _ble;
  final ApiClient _api;
  final CardUnbindSyncCoordinator _unbindSync;
  final CardUnbindHardware? _injectedUnbindHardware;
  late final CardUnbindHardware _unbindHardware =
      _injectedUnbindHardware ?? _BrCardUnbindHardware(_ble);

  @override
  Stream<String> get bluetoothStateStream => _ble.bluetoothStateChangedStream
      .map((event) => event['state']?.toString().trim() ?? '')
      .where((state) => state.isNotEmpty);

  @override
  Stream<bool> get connectionStateStream => _ble.rawEventStream
      .map((event) {
        final eventName = event['event']?.toString();
        if (eventName == 'deviceDisconnected') return false;
        if (eventName != 'connectionStateChanged') return null;
        return event['isConnected'] == true ||
            event['connected'] == true ||
            event['state']?.toString().toLowerCase() == 'connected';
      })
      .where((connected) => connected != null)
      .cast<bool>()
      .distinct();

  @override
  Future<bool> isBluetoothPoweredOn() async {
    if (Platform.isIOS) {
      final inited = await _ble.initNativeBluetoothSdk();
      if (inited != true) {
        throw const DeviceOperationException('蓝牙初始化失败，请稍后重试');
      }
    } else if (Platform.isAndroid) {
      final hasPermission = await _ble.checkBluetoothPermissions();
      if (hasPermission != true) {
        final granted = await _ble.initNativeBluetoothSdk();
        if (granted != true) {
          throw const DeviceOperationException('请开启蓝牙权限后重试');
        }
      } else {
        final inited = await _ble.initNativeBluetoothSdk();
        if (inited != true) {
          throw const DeviceOperationException('蓝牙初始化失败，请稍后重试');
        }
      }
    }
    final status = await _ble.getBluetoothStatus();
    return status == 'poweredOn';
  }

  @override
  Future<bool> isDeviceConnected() async {
    try {
      return await _ble.isConnected() == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensurePermissionReady() => _ensureBluetoothReady();

  @override
  Stream<List<DiscoveredDevice>> scan() {
    final controller = StreamController<List<DiscoveredDevice>>();
    StreamSubscription<Map<String, dynamic>>? sub;

    Future<void>(() async {
      try {
        controller.add(const []);
        sub = _ble.devicesDiscoveredStream.listen(
          (event) => controller.add(_parseDiscoveredDevices(event)),
          onError: controller.addError,
        );
        await _ble.startBindScanning();
      } catch (e, st) {
        controller.addError(_toDeviceError(e), st);
      }
    });

    controller.onCancel = () async {
      await sub?.cancel();
      try {
        await _ble.stopBindScanning();
      } catch (_) {
        // Best effort: leaving the page should not surface a stale scan error.
      }
    };

    return controller.stream;
  }

  @override
  Future<DeviceInfo> connect(DiscoveredDevice device) async {
    final cardSn = device.serial.trim();
    if (cardSn.isEmpty) {
      throw const DeviceOperationException('设备 SN 为空，无法绑定');
    }

    final info = await _bindingInfo(cardSn);
    final state = _string(info['state']);
    if (state == 'bound_by_other' || info['bindable'] == false) {
      throw const DeviceOperationException('该设备已被其他账号绑定');
    }

    final hint = (info['connect_hint'] as Map?)?.cast<String, dynamic>();
    final cardAppUuid = _string(hint?['card_app_uuid']).isNotEmpty
        ? _string(hint?['card_app_uuid'])
        : _uuidV4();
    final hintDeviceUuid = _string(hint?['card_device_uuid']);

    Map<String, dynamic> deviceInfo;
    try {
      final result = await _ble.connect(
        appUUID: cardAppUuid,
        deviceUUID: hintDeviceUuid.isNotEmpty ? hintDeviceUuid : null,
        sn: cardSn,
        cardMac: device.cardMac.isNotEmpty ? device.cardMac : null,
        bleIdentifier: device.bleIdentifier.isNotEmpty
            ? device.bleIdentifier
            : null,
      );
      deviceInfo = _mapOrEmpty(result);
    } catch (e) {
      throw _toDeviceError(e);
    }

    final resolvedSn = _firstString(deviceInfo, const [
      'SN',
      'sn',
      'device_sn',
      'deviceSN',
    ], fallback: cardSn);
    final resolvedName = _firstString(deviceInfo, const [
      'name',
      'device_name',
    ], fallback: device.name);
    final resolvedDeviceUuid = _firstString(deviceInfo, const [
      'uuid',
      'device_uuid',
      'deviceUUID',
    ], fallback: hintDeviceUuid);
    final resolvedCardMac = _firstString(deviceInfo, const [
      'cardMac',
      'card_mac',
      'address',
      'mac',
    ], fallback: device.cardMac);
    final resolvedAppUuid = _firstString(deviceInfo, const [
      'app_uuid',
      'appUUID',
    ], fallback: cardAppUuid);

    try {
      final res = await _api.postJson('/api/cards/bindings', {
        'card_sn': resolvedSn,
        'card_device_uuid': resolvedDeviceUuid,
        'card_mac': resolvedCardMac.isEmpty ? null : resolvedCardMac,
        'card_mac_from': _platformName,
        'card_name': resolvedName.isEmpty ? device.name : resolvedName,
        'card_nick': 'UReka 录音卡',
        'card_app_uuid': resolvedAppUuid,
      });
      final binding = ((res as Map)['binding'] as Map).cast<String, dynamic>();
      await _refreshNativeBindInfo(binding);
      return await _deviceInfoFromBinding(binding, connectedMap: deviceInfo);
    } on ApiException catch (e) {
      await _rollbackHardwareBinding();
      if (e.statusCode == 409) {
        throw const DeviceOperationException('该设备已被其他账号绑定');
      }
      throw const DeviceOperationException('服务端绑定失败，请重试');
    } catch (_) {
      await _rollbackHardwareBinding();
      throw const DeviceOperationException('服务端绑定失败，请重试');
    }
  }

  @override
  Future<DeviceInfo?> loadBoundDevice() async {
    try {
      final res = await _api.getJson('/api/cards/bindings');
      final rows = ((res as Map)['bindings'] as List? ?? const []);
      if (rows.isEmpty) return null;
      final binding = (rows.first as Map).cast<String, dynamic>();
      Map<String, dynamic>? connectedMap;
      try {
        final raw = await _ble.getConnectedDeviceInfo();
        connectedMap = raw == null ? null : Map<String, dynamic>.from(raw);
      } catch (_) {
        connectedMap = null;
      }
      return _deviceInfoFromBinding(binding, connectedMap: connectedMap);
    } on ApiException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _ble.closeBLESync();
    } catch (_) {
      // Best effort: logout should not fail because sync mode was not open.
    }
    try {
      await _ble.disconnect();
    } catch (e) {
      throw _toDeviceError(e);
    }
  }

  @override
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  }) async {
    try {
      await _bluetoothUnbindWithRetry(deleteData: deleteData);
      await _unbindHardware.clearBindInfo();
    } catch (e) {
      throw _toDeviceError(e);
    }

    if (device.bindingId.isEmpty) return const DeviceUnbindResult.complete();
    try {
      final ticket = await _unbindSync.enqueue(
        PendingCardUnbind(bindingId: device.bindingId, deleteData: deleteData),
      );
      return DeviceUnbindResult.pending(serverSync: _unbindSync.flush(ticket));
    } catch (_) {
      return const DeviceUnbindResult(
        serverSynced: false,
        message: cardUnbindSyncPendingWarning,
      );
    }
  }

  Future<void> _ensureBluetoothReady() async {
    if (Platform.isIOS) {
      final inited = await _ble.initNativeBluetoothSdk();
      if (inited != true) {
        throw const DeviceOperationException('蓝牙初始化失败，请稍后重试');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final status = await _ble.getBluetoothStatus();
      if (status != 'poweredOn') {
        if (status == 'unauthorized') {
          throw const DeviceOperationException('请开启蓝牙权限后重试');
        }
        if (status == 'poweredOff') {
          throw const DeviceOperationException('请开启手机蓝牙后重试');
        }
        throw const DeviceOperationException('蓝牙初始化失败，请稍后重试');
      }
      return;
    }

    final hasPermission = await _ble.checkBluetoothPermissions();
    if (hasPermission != true) {
      final granted = await _ble.initNativeBluetoothSdk();
      if (granted == true) return;
      throw const DeviceOperationException('请开启蓝牙权限后重试');
    }
    final inited = await _ble.initNativeBluetoothSdk();
    if (inited != true) {
      throw const DeviceOperationException('蓝牙初始化失败，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> _bindingInfo(String cardSn) async {
    final res = await _api.postJson('/api/cards/binding-info', {
      'card_sn': cardSn,
    });
    return (res as Map).cast<String, dynamic>();
  }

  Future<DeviceInfo> _deviceInfoFromBinding(
    Map<String, dynamic> binding, {
    Map<String, dynamic>? connectedMap,
  }) async {
    final battery = await _readBattery();
    final storage = await _readStorage();
    final cardName = _string(binding['card_nick']).isNotEmpty
        ? _string(binding['card_nick'])
        : _string(binding['card_name']);
    final serial = _firstString(connectedMap, const [
      'SN',
      'sn',
      'device_sn',
    ], fallback: _string(binding['card_sn']));
    final deviceUuid = _firstString(connectedMap, const [
      'uuid',
      'device_uuid',
      'deviceUUID',
    ], fallback: _string(binding['card_device_uuid']));
    final appUuid = _firstString(connectedMap, const [
      'app_uuid',
      'appUUID',
    ], fallback: _string(binding['card_app_uuid']));
    final cardMac = _firstString(connectedMap, const [
      'cardMac',
      'card_mac',
    ], fallback: _string(binding['card_mac']));

    return DeviceInfo(
      id: _string(binding['card_id']).isNotEmpty
          ? _string(binding['card_id'])
          : serial,
      bindingId: _string(binding['binding_id']),
      name: cardName.isEmpty ? 'UReka 录音卡' : cardName,
      serial: serial,
      cardDeviceUuid: deviceUuid,
      cardAppUuid: appUuid,
      cardMac: cardMac,
      batteryPct: battery,
      storageUsedGb: storage.usedGb,
      storageTotalGb: storage.totalGb,
    );
  }

  Future<void> _refreshNativeBindInfo(Map<String, dynamic> binding) async {
    final deviceName = _string(binding['card_name']).isNotEmpty
        ? _string(binding['card_name'])
        : 'UReka 录音卡';
    final deviceSn = _string(binding['card_sn']);
    final deviceUuid = _string(binding['card_device_uuid']);
    final appUuid = _string(binding['card_app_uuid']);
    if (deviceSn.isEmpty || deviceUuid.isEmpty || appUuid.isEmpty) return;
    try {
      await _ble.setBindInfo(
        deviceName: deviceName,
        deviceSN: deviceSn,
        deviceUUID: deviceUuid,
        appUUID: appUuid,
        cardMac: _string(binding['card_mac']),
      );
    } catch (_) {
      // Native connect usually persists this already; setBindInfo is best-effort.
    }
  }

  Future<int?> _readBattery() async {
    try {
      final result = await _ble.getBatteryLevel();
      if (result is int) return result;
      if (result is num) return result.toInt();
    } catch (_) {}
    return null;
  }

  Future<({double? usedGb, double? totalGb})> _readStorage() async {
    try {
      final storage = await _ble.getStorage();
      if (storage == null) return (usedGb: null, totalGb: null);
      final free = storage['FreeCapacity'];
      final total = storage['TotalCapacity'];
      final totalGb = total is num ? _capacityToGb(total) : 64.0;
      final freeGb = free is num ? _capacityToGb(free) : null;
      final usedGb = freeGb == null
          ? null
          : (totalGb - freeGb).clamp(0.0, totalGb);
      return (usedGb: usedGb, totalGb: totalGb);
    } catch (_) {
      return (usedGb: null, totalGb: null);
    }
  }

  Future<void> _bluetoothUnbindWithRetry({required bool deleteData}) async {
    for (var i = 0; i < 3; i++) {
      try {
        await _unbindHardware.unbind(deleteData: deleteData);
        return;
      } catch (_) {
        if (i == 2) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _rollbackHardwareBinding() async {
    try {
      await _unbindHardware.unbind(deleteData: false);
    } catch (_) {}
  }

  List<DiscoveredDevice> _parseDiscoveredDevices(Map<String, dynamic> event) {
    final raw = event['devices'];
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <DiscoveredDevice>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final sn = _firstString(map, const ['sn', 'SN', 'deviceSN', 'device_sn']);
      if (sn.isEmpty || !seen.add(sn)) continue;
      final cardMac = _firstString(map, const ['cardMac', 'address', 'mac']);
      final bleIdentifier = _firstString(map, const [
        'bleIdentifier',
        'identifier',
      ]);
      final name = _firstString(map, const [
        'name',
        'device_name',
        'cardName',
      ], fallback: 'W2(BLE)');
      out.add(
        DiscoveredDevice(
          id: bleIdentifier.isNotEmpty
              ? bleIdentifier
              : (cardMac.isNotEmpty ? cardMac : sn),
          name: name,
          serial: sn,
          cardMac: cardMac,
          bleIdentifier: bleIdentifier,
        ),
      );
    }
    return out;
  }

  DeviceOperationException _toDeviceError(Object e) {
    if (e is DeviceOperationException) return e;
    if (e is PlatformException) {
      final code = int.tryParse(e.code);
      return DeviceOperationException(switch (code) {
        1009 => '请开启蓝牙权限后重试',
        1002 || 1008 => '请开启手机蓝牙后重试',
        1007 => '该设备已被其他账号绑定',
        1012 => '设备地址无效，请重新扫描',
        _ => '连接失败，请稍后重试',
      });
    }
    if (e is ApiException && e.statusCode == 401) {
      return const DeviceOperationException('登录已过期，请重新登录');
    }
    return const DeviceOperationException('连接失败，请稍后重试');
  }

  static Map<String, dynamic> _mapOrEmpty(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _firstString(
    Map<String, dynamic>? map,
    List<String> keys, {
    String fallback = '',
  }) {
    if (map == null) return fallback;
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static double _capacityToGb(num value) => value / (1000 * 1000);

  static String get _platformName {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class _BrCardUnbindHardware implements CardUnbindHardware {
  const _BrCardUnbindHardware(this._ble);

  final BrBluetoothPlugin _ble;

  @override
  Future<void> clearBindInfo() async {
    await _ble.clearBindInfo();
  }

  @override
  Future<void> unbind({required bool deleteData}) async {
    await _ble.unbind(deleteAudio: deleteData);
  }
}

/// Simulated transport kept for widget tests or hardware-free local debugging.
class MockDeviceTransport implements DeviceTransport {
  static const _device = DiscoveredDevice(
    id: 'w2-ble-mock',
    name: 'W2(BLE)',
    serial: '474204126010000003',
    cardMac: 'mock-card-mac',
  );
  DeviceInfo? _boundDevice;
  int disconnectCalls = 0;
  int unbindCalls = 0;

  @override
  Stream<String> get bluetoothStateStream => Stream<String>.empty();

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  void emitConnectionState(bool connected) {
    deviceConnected = connected;
    _connectionStateController.add(connected);
  }

  @override
  Future<bool> isBluetoothPoweredOn() async => true;

  @override
  Future<bool> isDeviceConnected() async => deviceConnected;

  bool deviceConnected = false;

  @override
  Future<void> ensurePermissionReady() async {}

  @override
  Stream<List<DiscoveredDevice>> scan() async* {
    yield const [];
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    yield const [_device];
  }

  @override
  Future<DeviceInfo> connect(DiscoveredDevice device) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    deviceConnected = true;
    _boundDevice = DeviceInfo(
      id: device.id,
      bindingId: 'mock-binding',
      name: 'UReka 录音卡',
      serial: device.serial,
      cardDeviceUuid: 'mock-device-uuid',
      cardAppUuid: 'mock-app-uuid',
      cardMac: device.cardMac,
      batteryPct: 50,
      storageUsedGb: 3.3,
      storageTotalGb: 64,
    );
    return _boundDevice!;
  }

  @override
  Future<DeviceInfo?> loadBoundDevice() async => _boundDevice;

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    deviceConnected = false;
  }

  @override
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  }) async {
    unbindCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    deviceConnected = false;
    _boundDevice = null;
    return const DeviceUnbindResult.complete();
  }
}

enum DeviceEntryTarget { pairing, myDevice }

class DeviceController extends ChangeNotifier {
  DeviceController(this._transport) {
    _bluetoothSub = _transport.bluetoothStateStream.listen(
      _handleBluetoothState,
      onError: (_) {},
    );
    _connectionSub = _transport.connectionStateStream.listen(
      _handleConnectionState,
      onError: (_) {},
    );
  }

  final DeviceTransport _transport;

  static final DeviceController instance = DeviceController(
    BleDeviceTransport(),
  );

  DeviceConnState state = DeviceConnState.idle;
  List<DiscoveredDevice> discovered = const [];
  DeviceInfo? device;
  Object? error;

  StreamSubscription<List<DiscoveredDevice>>? _scanSub;
  StreamSubscription<String>? _bluetoothSub;
  StreamSubscription<bool>? _connectionSub;
  bool _scanRequested = false;
  bool _startingScan = false;
  bool _unbinding = false;
  bool _preserveDeviceAfterUnbindFailure = false;
  int _operationRevision = 0;
  String? _cardUnbindSyncWarning;

  bool get isBound => device != null;

  String? get errorMessage {
    final e = error;
    if (e is DeviceOperationException) return e.message;
    if (e != null) return e.toString();
    return _cardUnbindSyncWarning;
  }

  Future<void> refreshBoundDevice() async {
    if (_unbinding) return;
    final revision = _operationRevision;
    try {
      final connected = await _transport.isDeviceConnected();
      if (revision != _operationRevision) return;
      if (connected) {
        final loaded = await _transport.loadBoundDevice();
        if (revision != _operationRevision) return;
        device = loaded;
      } else {
        device = null;
      }
      state = connected && device != null
          ? DeviceConnState.connected
          : DeviceConnState.idle;
      error = null;
      notifyListeners();
    } catch (e) {
      if (revision != _operationRevision) return;
      device = null;
      state = DeviceConnState.idle;
      error = e;
      notifyListeners();
    }
  }

  Future<DeviceEntryTarget> resolveEntryTarget() async {
    final revision = ++_operationRevision;
    _cardUnbindSyncWarning = null;
    error = null;
    final poweredOn = await _transport.isBluetoothPoweredOn();
    if (revision != _operationRevision) return DeviceEntryTarget.pairing;
    if (!poweredOn) {
      device = null;
      state = DeviceConnState.idle;
      notifyListeners();
      throw const DeviceOperationException('请先开启手机蓝牙');
    }

    final connected = await _transport.isDeviceConnected();
    if (revision != _operationRevision) return DeviceEntryTarget.pairing;
    if (!connected) {
      device = null;
      state = DeviceConnState.idle;
      notifyListeners();
      return DeviceEntryTarget.pairing;
    }

    final loaded = await _transport.loadBoundDevice();
    if (revision != _operationRevision) return DeviceEntryTarget.pairing;
    if (loaded == null) {
      device = null;
      state = DeviceConnState.idle;
      notifyListeners();
      return DeviceEntryTarget.pairing;
    }

    device = loaded;
    state = DeviceConnState.connected;
    notifyListeners();
    return DeviceEntryTarget.myDevice;
  }

  Future<void> ensurePermissionAndStartScan() async {
    if (device != null) return;
    _cardUnbindSyncWarning = null;
    _scanRequested = true;
    if (_startingScan) return;
    _startingScan = true;
    discovered = const [];
    error = null;
    notifyListeners();

    try {
      await _transport.ensurePermissionReady();
      if (!_scanRequested || device != null) return;
      _startScanAfterPermission();
    } catch (e) {
      if (!_scanRequested) return;
      error = e;
      state = DeviceConnState.error;
      notifyListeners();
    } finally {
      _startingScan = false;
    }
  }

  void startScan() {
    unawaited(ensurePermissionAndStartScan());
  }

  void _startScanAfterPermission() {
    _scanSub?.cancel();
    state = DeviceConnState.scanning;
    discovered = const [];
    error = null;
    notifyListeners();
    _scanSub = _transport.scan().listen(
      (devices) {
        discovered = _mergeDiscoveredDevices(discovered, devices);
        notifyListeners();
      },
      onError: (Object e) {
        error = e;
        state = DeviceConnState.error;
        notifyListeners();
      },
    );
  }

  void stopScan({bool keepRequest = false, bool clearDiscovered = false}) {
    if (!keepRequest) {
      _scanRequested = false;
    }
    _scanSub?.cancel();
    _scanSub = null;
    if (clearDiscovered) {
      discovered = const [];
    }
    if (state == DeviceConnState.scanning || clearDiscovered) {
      state = DeviceConnState.idle;
      notifyListeners();
    }
  }

  List<DiscoveredDevice> _mergeDiscoveredDevices(
    List<DiscoveredDevice> current,
    List<DiscoveredDevice> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final mergedBySn = <String, DiscoveredDevice>{
      for (final device in current)
        if (device.serial.trim().isNotEmpty) device.serial.trim(): device,
    };
    final newDevices = <DiscoveredDevice>[];
    for (final device in incoming) {
      final serial = device.serial.trim();
      if (serial.isEmpty) continue;
      if (mergedBySn.containsKey(serial)) {
        mergedBySn[serial] = device;
      } else {
        mergedBySn[serial] = device;
        newDevices.add(device);
      }
    }
    return [
      for (final device in current)
        if (mergedBySn.containsKey(device.serial.trim()))
          mergedBySn[device.serial.trim()]!,
      ...newDevices,
    ];
  }

  Future<void> connect(DiscoveredDevice d) async {
    final revision = ++_operationRevision;
    _cardUnbindSyncWarning = null;
    _preserveDeviceAfterUnbindFailure = false;
    _scanRequested = false;
    await _scanSub?.cancel();
    _scanSub = null;
    state = DeviceConnState.connecting;
    error = null;
    notifyListeners();
    try {
      final connected = await _transport.connect(d);
      if (revision != _operationRevision) return;
      device = connected;
      state = DeviceConnState.connected;
    } catch (e) {
      if (revision != _operationRevision) return;
      error = e;
      state = DeviceConnState.error;
    }
    if (revision == _operationRevision) notifyListeners();
  }

  void _handleBluetoothState(String bluetoothState) {
    switch (bluetoothState) {
      case 'poweredOn':
        if (_scanRequested && !isBound) {
          unawaited(ensurePermissionAndStartScan());
        }
      case 'poweredOff':
        if (!_scanRequested) return;
        error = const DeviceOperationException('请开启手机蓝牙后重试');
        stopScan(keepRequest: true);
        state = DeviceConnState.error;
        notifyListeners();
      case 'unauthorized':
        if (!_scanRequested) return;
        error = const DeviceOperationException('请开启蓝牙权限后重试');
        stopScan(keepRequest: true);
        state = DeviceConnState.error;
        notifyListeners();
    }
  }

  void _handleConnectionState(bool connected) {
    if (!connected) {
      if (_unbinding || _preserveDeviceAfterUnbindFailure) return;
      if (state != DeviceConnState.connected && device == null) return;
      _operationRevision++;
      device = null;
      discovered = const [];
      error = null;
      state = DeviceConnState.idle;
      notifyListeners();
      return;
    }

    _preserveDeviceAfterUnbindFailure = false;

    if (state == DeviceConnState.connecting ||
        state == DeviceConnState.scanning ||
        isBound) {
      return;
    }
    unawaited(refreshBoundDevice());
  }

  Future<DeviceUnbindResult?> unbind({required bool deleteData}) async {
    final current = device;
    if (current == null) return null;
    final revision = ++_operationRevision;
    _cardUnbindSyncWarning = null;
    state = DeviceConnState.connecting;
    error = null;
    _unbinding = true;
    _preserveDeviceAfterUnbindFailure = false;
    notifyListeners();
    try {
      final result = await _transport.unbind(current, deleteData: deleteData);
      if (revision != _operationRevision) return result;
      device = null;
      discovered = const [];
      state = DeviceConnState.idle;
      _cardUnbindSyncWarning = result.serverSynced ? null : result.message;
      error = _cardUnbindSyncWarning == null
          ? null
          : DeviceOperationException(_cardUnbindSyncWarning!);
      _unbinding = false;
      notifyListeners();
      _observeServerSync(result, revision: revision);
      return result;
    } catch (e) {
      if (revision != _operationRevision) return null;
      _unbinding = false;
      _preserveDeviceAfterUnbindFailure = true;
      error = e;
      state = DeviceConnState.error;
      notifyListeners();
      return null;
    }
  }

  void _observeServerSync(DeviceUnbindResult result, {required int revision}) {
    final serverSync = result.serverSync;
    if (serverSync == null) return;
    unawaited(
      serverSync.then(
        (syncResult) {
          if (revision != _operationRevision || syncResult.serverSynced) return;
          _cardUnbindSyncWarning =
              syncResult.message ?? cardUnbindSyncPendingWarning;
          error = DeviceOperationException(_cardUnbindSyncWarning!);
          notifyListeners();
        },
        onError: (_) {
          if (revision != _operationRevision) return;
          _cardUnbindSyncWarning = cardUnbindSyncPendingWarning;
          error = const DeviceOperationException(cardUnbindSyncPendingWarning);
          notifyListeners();
        },
      ),
    );
  }

  Future<void> disconnectForLogout() async {
    _operationRevision++;
    _cardUnbindSyncWarning = null;
    _unbinding = false;
    _preserveDeviceAfterUnbindFailure = false;
    _scanRequested = false;
    _startingScan = false;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _transport.disconnect();
    } catch (_) {
      // Logout cleanup is best-effort. It must never turn into an unbind.
    }
    device = null;
    discovered = const [];
    error = null;
    state = DeviceConnState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _operationRevision++;
    _scanSub?.cancel();
    _bluetoothSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }
}
