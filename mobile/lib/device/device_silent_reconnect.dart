import 'dart:async';
import 'dart:io';

import 'package:br_flutter_plugin_ble/br_bluetooth_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'device_controller.dart';

/// 登录后一次性的静默重连任务。
///
/// 这个类不依赖配对页的扫描/连接状态机，直接调用绑定查询接口和 BLE 插件。
/// 所有失败都吞掉，确保不会阻塞登录后的其他任务，也不会弹 UI。
class DeviceSilentReconnect {
  DeviceSilentReconnect({
    DeviceSilentReconnectApi? api,
    DeviceSilentReconnectBle? ble,
    DeviceController? controller,
    this.scanTimeout = const Duration(seconds: 20),
  }) : _api = api ?? _ApiClientReconnectApi(ApiClient()),
       _ble = ble ?? _BrPluginReconnectBle(BrBluetoothPlugin.instance),
       _controller = controller ?? DeviceController.instance;

  static final DeviceSilentReconnect instance = DeviceSilentReconnect();
  static const _logTag = 'Auto Reconnect Ble';

  final DeviceSilentReconnectApi _api;
  final DeviceSilentReconnectBle _ble;
  final DeviceController _controller;
  final Duration scanTimeout;

  Object? _lastSessionKey;
  int _runId = 0;
  bool _running = false;
  bool _connecting = false;
  Timer? _timeoutTimer;
  Completer<_MatchedCard?>? _scanCompleter;
  StreamSubscription<Map<String, dynamic>>? _scanSub;

  void _log(String message) => debugPrint('[$_logTag] $message');

  Future<void> tryReconnect({Object? sessionKey}) async {
    _log(
      'tryReconnect requested sessionKey=${sessionKey ?? "-"} '
      'lastSessionKey=${_lastSessionKey ?? "-"} running=$_running '
      'connecting=$_connecting',
    );
    if (sessionKey != null && _lastSessionKey == sessionKey) {
      _log('skip reconnect: same sessionKey=$sessionKey');
      return;
    }
    _lastSessionKey = sessionKey;

    await stop();
    final runId = ++_runId;
    _running = true;
    _log('run#$runId start scanTimeout=${scanTimeout.inSeconds}s');

    try {
      final bindings = await _loadBindings();
      _log('run#$runId bindings loaded count=${bindings.length}');
      if (!_isActive(runId)) {
        _log('run#$runId stop after bindings: inactive');
        return;
      }
      if (bindings.isEmpty) {
        _log('run#$runId stop: no bound cards');
        return;
      }

      final ready = await _isBluetoothReady();
      _log('run#$runId bluetooth ready=$ready');
      if (!_isActive(runId)) {
        _log('run#$runId stop after bluetooth check: inactive');
        return;
      }
      if (!ready) {
        _log('run#$runId stop: bluetooth not ready');
        return;
      }

      final match = await _scanForMatch(bindings, runId);
      if (!_isActive(runId)) {
        _log('run#$runId stop after scan: inactive');
        return;
      }
      if (match == null) {
        _log('run#$runId stop: no matched card within timeout');
        return;
      }

      _connecting = true;
      _log(
        'run#$runId connect start sn=${match.binding.serial} '
        'cardMac=${_mask(match.discovered.cardMac)} '
        'bleIdentifier=${_mask(match.discovered.bleIdentifier)}',
      );
      try {
        final connected = await _connect(match);
        if (!_isActive(runId)) {
          _log('run#$runId connect finished after stop; disconnect quietly');
          await _disconnectQuietly();
          return;
        }
        _commitConnectedDevice(connected);
        _log(
          'run#$runId connect success sn=${connected.serial} '
          'bindingId=${connected.bindingId}',
        );
      } finally {
        _connecting = false;
      }
    } catch (e, st) {
      _log('run#$runId error=$e stack=$st');
      // 静默任务不能影响登录后链路。
    } finally {
      if (_runId == runId) _running = false;
      await _stopScan();
      _log('run#$runId finish active=${_runId == runId}');
    }
  }

  Future<void> stop() async {
    _log(
      'stop requested currentRun=$_runId running=$_running '
      'connecting=$_connecting',
    );
    _runId++;
    _running = false;
    await _stopScan();
    if (_connecting) {
      _log('stop: disconnect in-flight connection');
      await _disconnectQuietly();
    }
  }

  Future<List<_BoundCard>> _loadBindings() async {
    _log('load bindings start');
    try {
      final res = await _api.getJson('/api/cards/bindings');
      final rows = (res is Map ? res['bindings'] as List? : null) ?? const [];
      final bindings = [
        for (final row in rows)
          if (row is Map) _BoundCard.fromJson(row.cast<String, dynamic>()),
      ].where((card) => card.serial.isNotEmpty).toList();
      _log(
        'load bindings success rawCount=${rows.length} '
        'usableCount=${bindings.length}',
      );
      return bindings;
    } catch (e) {
      _log('load bindings failed error=$e');
      return const [];
    }
  }

  Future<bool> _isBluetoothReady() async {
    _log('bluetooth check start platform=${Platform.operatingSystem}');
    try {
      if (Platform.isAndroid) {
        final hasPermission = await _ble.checkBluetoothPermissions();
        _log('bluetooth android permission=$hasPermission');
        if (hasPermission != true) return false;
        final inited = await _ble.initNativeBluetoothSdk();
        _log('bluetooth android init=$inited');
        if (inited != true) return false;
        final status = await _ble.getBluetoothStatus();
        _log('bluetooth android status=$status');
        return status == 'poweredOn';
      }

      if (Platform.isIOS) {
        final status = await _ble.getBluetoothStatus();
        _log('bluetooth ios status=$status');
        if (status != 'poweredOn') return false;
        final inited = await _ble.initNativeBluetoothSdk();
        _log('bluetooth ios init=$inited');
        return inited == true;
      }
      final inited = await _ble.initNativeBluetoothSdk();
      _log('bluetooth other init=$inited');
      if (inited != true) return false;
      final status = await _ble.getBluetoothStatus();
      _log('bluetooth other status=$status');
      return status == 'poweredOn';
    } on PlatformException catch (e) {
      _log(
        'bluetooth check platform exception code=${e.code} message=${e.message}',
      );
      return false;
    } catch (e) {
      _log('bluetooth check failed error=$e');
      return false;
    }
  }

  Future<_MatchedCard?> _scanForMatch(List<_BoundCard> bindings, int runId) {
    _log('run#$runId scan prepare bindings=${bindings.length}');
    final completer = Completer<_MatchedCard?>();
    _scanCompleter = completer;

    void complete(_MatchedCard? match) {
      if (!completer.isCompleted) {
        _log(
          'run#$runId scan complete matched=${match != null} '
          'sn=${match?.binding.serial ?? "-"}',
        );
        completer.complete(match);
      }
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(scanTimeout, () {
      _log('run#$runId scan timeout after ${scanTimeout.inSeconds}s');
      complete(null);
    });
    _scanSub?.cancel();
    _scanSub = _ble.devicesDiscoveredStream.listen(
      (event) {
        if (!_isActive(runId)) {
          _log('run#$runId scan event ignored: inactive');
          complete(null);
          return;
        }
        final discovered = _parseDiscoveredDevices(event);
        _log(
          'run#$runId scan event devices=${discovered.length} '
          'rawKeys=${event.keys.join(",")}',
        );
        final match = _findMatch(bindings, discovered);
        if (match != null) complete(match);
      },
      onError: (e) {
        _log('run#$runId scan stream error=$e');
        complete(null);
      },
      onDone: () {
        _log('run#$runId scan stream done');
        complete(null);
      },
    );

    Future<void>(() async {
      try {
        _log('run#$runId startBindScanning call');
        await _ble.startBindScanning();
        _log('run#$runId startBindScanning success');
      } catch (e) {
        _log('run#$runId startBindScanning failed error=$e');
        complete(null);
      }
    });

    return completer.future.whenComplete(() {
      if (_scanCompleter == completer) _scanCompleter = null;
      return _stopScan();
    });
  }

  Future<DeviceInfo> _connect(_MatchedCard match) async {
    final binding = match.binding;
    final discovered = match.discovered;
    final cardMac = discovered.cardMac.isNotEmpty
        ? discovered.cardMac
        : binding.cardMac;
    _log(
      'ble connect call sn=${binding.serial} appUuid=${_mask(binding.appUuid)} '
      'deviceUuid=${_mask(binding.deviceUuid)} cardMac=${_mask(cardMac)}',
    );
    final raw = await _ble.connect(
      appUUID: binding.appUuid.isNotEmpty ? binding.appUuid : null,
      deviceUUID: binding.deviceUuid.isNotEmpty ? binding.deviceUuid : null,
      sn: binding.serial,
      cardMac: cardMac.isNotEmpty ? cardMac : null,
      bleIdentifier: discovered.bleIdentifier.isNotEmpty
          ? discovered.bleIdentifier
          : null,
    );
    final connectedMap = raw is Map ? Map<String, dynamic>.from(raw) : null;
    _log('ble connect returned keys=${connectedMap?.keys.join(",") ?? "-"}');
    final connected = binding.toDeviceInfo(
      discovered: discovered,
      connectedMap: connectedMap,
    );
    await _setNativeBindInfo(connected);
    return connected;
  }

  Future<void> _setNativeBindInfo(DeviceInfo device) async {
    if (device.serial.isEmpty ||
        device.cardDeviceUuid.isEmpty ||
        device.cardAppUuid.isEmpty) {
      _log('setBindInfo skipped: missing required fields sn=${device.serial}');
      return;
    }
    try {
      _log(
        'setBindInfo start sn=${device.serial} '
        'deviceUuid=${_mask(device.cardDeviceUuid)} '
        'appUuid=${_mask(device.cardAppUuid)}',
      );
      await _ble.setBindInfo(
        deviceName: device.name,
        deviceSN: device.serial,
        deviceUUID: device.cardDeviceUuid,
        appUUID: device.cardAppUuid,
        cardMac: device.cardMac,
      );
      _log('setBindInfo success sn=${device.serial}');
    } catch (e) {
      _log('setBindInfo ignored error=$e');
    }
  }

  void _commitConnectedDevice(DeviceInfo connected) {
    _log('commit controller state sn=${connected.serial}');
    _controller
      ..device = connected
      ..discovered = const []
      ..error = null
      ..state = DeviceConnState.connected;
    unawaited(_controller.refreshBoundDevice());
  }

  Future<void> _stopScan() async {
    _log('stop scan start hasSub=${_scanSub != null}');
    final completer = _scanCompleter;
    if (completer != null && !completer.isCompleted) {
      _log('stop scan completes pending scan future');
      completer.complete(null);
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final sub = _scanSub;
    _scanSub = null;
    await sub?.cancel();
    try {
      await _ble.stopBindScanning();
      _log('stopBindScanning success');
    } catch (e) {
      _log('stopBindScanning ignored error=$e');
    }
  }

  Future<void> _disconnectQuietly() async {
    _log('disconnect quietly start');
    try {
      await _ble.closeBLESync();
      _log('closeBLESync success');
    } catch (e) {
      _log('closeBLESync ignored error=$e');
    }
    try {
      await _ble.disconnect();
      _log('disconnect success');
    } catch (e) {
      _log('disconnect ignored error=$e');
    }
  }

  _MatchedCard? _findMatch(
    List<_BoundCard> bindings,
    List<_DiscoveredCard> discoveredCards,
  ) {
    for (final discovered in discoveredCards) {
      for (final binding in bindings) {
        if (_sameNonEmpty(discovered.serial, binding.serial) ||
            _sameNonEmpty(discovered.cardMac, binding.cardMac) ||
            _sameNonEmpty(discovered.bleIdentifier, binding.deviceUuid)) {
          _log(
            'match found bindingSn=${binding.serial} '
            'discoveredSn=${discovered.serial} '
            'cardMac=${_mask(discovered.cardMac)}',
          );
          return _MatchedCard(binding, discovered);
        }
      }
    }
    return null;
  }

  List<_DiscoveredCard> _parseDiscoveredDevices(Map<String, dynamic> event) {
    final raw = event['devices'];
    if (raw is! List) {
      _log('parse discovered ignored: devices is ${raw.runtimeType}');
      return const [];
    }
    final seen = <String>{};
    final out = <_DiscoveredCard>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final serial = _firstString(map, const [
        'sn',
        'SN',
        'deviceSN',
        'device_sn',
      ]);
      if (serial.isEmpty) {
        _log(
          'parse discovered skipped: empty serial keys=${map.keys.join(",")}',
        );
        continue;
      }
      if (!seen.add(serial)) {
        _log('parse discovered skipped duplicate sn=$serial');
        continue;
      }
      out.add(
        _DiscoveredCard(
          name: _firstString(map, const [
            'name',
            'device_name',
            'cardName',
          ], fallback: 'W2(BLE)'),
          serial: serial,
          cardMac: _firstString(map, const ['cardMac', 'address', 'mac']),
          bleIdentifier: _firstString(map, const [
            'bleIdentifier',
            'identifier',
          ]),
        ),
      );
    }
    return out;
  }

  bool _sameNonEmpty(String a, String b) {
    final left = _normalize(a);
    final right = _normalize(b);
    return left.isNotEmpty && left == right;
  }

  bool _isActive(int runId) => _running && _runId == runId;

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s:._-]+'), '');

  static String _mask(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '-';
    if (normalized.length <= 6) return normalized;
    return '${normalized.substring(0, 3)}...${normalized.substring(normalized.length - 3)}';
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
}

abstract class DeviceSilentReconnectApi {
  Future<dynamic> getJson(String path);
}

abstract class DeviceSilentReconnectBle {
  Stream<Map<String, dynamic>> get devicesDiscoveredStream;

  Future<bool?> checkBluetoothPermissions();

  Future<bool?> initNativeBluetoothSdk();

  Future<String?> getBluetoothStatus();

  Future<dynamic> startBindScanning();

  Future<dynamic> stopBindScanning();

  Future<dynamic> connect({
    String? appUUID,
    String? deviceUUID,
    String? sn,
    String? cardMac,
    String? bleIdentifier,
  });

  Future<dynamic> setBindInfo({
    required String deviceName,
    required String deviceSN,
    required String deviceUUID,
    required String appUUID,
    required String cardMac,
  });

  Future<dynamic> closeBLESync();

  Future<dynamic> disconnect();
}

class _ApiClientReconnectApi implements DeviceSilentReconnectApi {
  _ApiClientReconnectApi(this._api);

  final ApiClient _api;

  @override
  Future<dynamic> getJson(String path) => _api.getJson(path);
}

class _BrPluginReconnectBle implements DeviceSilentReconnectBle {
  _BrPluginReconnectBle(this._ble);

  final BrBluetoothPlugin _ble;

  @override
  Stream<Map<String, dynamic>> get devicesDiscoveredStream =>
      _ble.devicesDiscoveredStream;

  @override
  Future<bool?> checkBluetoothPermissions() => _ble.checkBluetoothPermissions();

  @override
  Future<bool?> initNativeBluetoothSdk() => _ble.initNativeBluetoothSdk();

  @override
  Future<String?> getBluetoothStatus() => _ble.getBluetoothStatus();

  @override
  Future<dynamic> startBindScanning() => _ble.startBindScanning();

  @override
  Future<dynamic> stopBindScanning() => _ble.stopBindScanning();

  @override
  Future<dynamic> connect({
    String? appUUID,
    String? deviceUUID,
    String? sn,
    String? cardMac,
    String? bleIdentifier,
  }) => _ble.connect(
    appUUID: appUUID,
    deviceUUID: deviceUUID,
    sn: sn,
    cardMac: cardMac,
    bleIdentifier: bleIdentifier,
  );

  @override
  Future<dynamic> setBindInfo({
    required String deviceName,
    required String deviceSN,
    required String deviceUUID,
    required String appUUID,
    required String cardMac,
  }) => _ble.setBindInfo(
    deviceName: deviceName,
    deviceSN: deviceSN,
    deviceUUID: deviceUUID,
    appUUID: appUUID,
    cardMac: cardMac,
  );

  @override
  Future<dynamic> closeBLESync() => _ble.closeBLESync();

  @override
  Future<dynamic> disconnect() => _ble.disconnect();
}

class _BoundCard {
  final String id;
  final String bindingId;
  final String name;
  final String serial;
  final String deviceUuid;
  final String appUuid;
  final String cardMac;

  const _BoundCard({
    required this.id,
    required this.bindingId,
    required this.name,
    required this.serial,
    required this.deviceUuid,
    required this.appUuid,
    required this.cardMac,
  });

  factory _BoundCard.fromJson(Map<String, dynamic> json) {
    final nick = _string(json['card_nick']);
    final name = nick.isNotEmpty ? nick : _string(json['card_name']);
    return _BoundCard(
      id: _string(json['card_id']),
      bindingId: _string(json['binding_id']),
      name: name.isEmpty ? 'UReka 录音卡' : name,
      serial: _string(json['card_sn']),
      deviceUuid: _string(json['card_device_uuid']),
      appUuid: _string(json['card_app_uuid']),
      cardMac: _string(json['card_mac']),
    );
  }

  DeviceInfo toDeviceInfo({
    required _DiscoveredCard discovered,
    Map<String, dynamic>? connectedMap,
  }) {
    final resolvedSerial = DeviceSilentReconnect._firstString(
      connectedMap,
      const ['SN', 'sn', 'device_sn', 'deviceSN'],
      fallback: serial,
    );
    final resolvedDeviceUuid = DeviceSilentReconnect._firstString(
      connectedMap,
      const ['uuid', 'device_uuid', 'deviceUUID'],
      fallback: deviceUuid,
    );
    final resolvedAppUuid = DeviceSilentReconnect._firstString(
      connectedMap,
      const ['app_uuid', 'appUUID'],
      fallback: appUuid,
    );
    final resolvedCardMac = DeviceSilentReconnect._firstString(
      connectedMap,
      const ['cardMac', 'card_mac', 'address', 'mac'],
      fallback: discovered.cardMac.isNotEmpty ? discovered.cardMac : cardMac,
    );
    return DeviceInfo(
      id: id.isNotEmpty ? id : resolvedSerial,
      bindingId: bindingId,
      name: name,
      serial: resolvedSerial,
      cardDeviceUuid: resolvedDeviceUuid,
      cardAppUuid: resolvedAppUuid,
      cardMac: resolvedCardMac,
    );
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';
}

class _DiscoveredCard {
  final String name;
  final String serial;
  final String cardMac;
  final String bleIdentifier;

  const _DiscoveredCard({
    required this.name,
    required this.serial,
    required this.cardMac,
    required this.bleIdentifier,
  });
}

class _MatchedCard {
  final _BoundCard binding;
  final _DiscoveredCard discovered;

  const _MatchedCard(this.binding, this.discovered);
}
