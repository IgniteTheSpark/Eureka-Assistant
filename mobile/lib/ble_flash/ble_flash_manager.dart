import 'dart:async';

import 'package:br_flutter_plugin_ble/br_bluetooth_plugin.dart';
import 'package:flutter/foundation.dart';

import '../capture_activity/capture_activity_bus.dart';
import '../capture_activity/capture_activity_event.dart';
import 'flash_file_task.dart';
import 'flash_file_workflow.dart';

/// App-wide BLE flash-memo event manager.
///
/// This layer only owns hardware events and shared flash state. Feature-specific
/// persistence/transcription will be added above it later.
class BleFlashManager {
  BleFlashManager._({BrBluetoothPlugin? ble})
    : _ble = ble ?? BrBluetoothPlugin.instance;

  static final BleFlashManager instance = BleFlashManager._();
  static const _logTag = '[FlashFile]';

  final BrBluetoothPlugin _ble;
  final ValueNotifier<bool> isFlashing = ValueNotifier<bool>(false);

  final List<StreamSubscription<Map<String, dynamic>>> _subscriptions = [];

  bool _started = false;
  int _audioFrameCount = 0;
  Map<String, dynamic>? _lastStartEvent;
  Map<String, dynamic>? _lastEndEvent;
  String? _activeActivityId;
  int _activitySequence = 0;

  int get audioFrameCount => _audioFrameCount;
  Map<String, dynamic>? get lastStartEvent => _lastStartEvent;
  Map<String, dynamic>? get lastEndEvent => _lastEndEvent;

  void _log(String message) => debugPrint('$_logTag BLE $message');

  void start() {
    if (_started) {
      _log('manager already started');
      return;
    }
    _started = true;
    _log('manager start: subscribe flash streams');
    _subscriptions
      ..add(_ble.flashIdeaStartStream.listen(_handleStart, onError: _ignore))
      ..add(_ble.flashIdeaDataStream.listen(_handleData, onError: _ignore))
      ..add(_ble.flashIdeaEndStream.listen(_handleEnd, onError: _ignore))
      ..add(
        _ble.connectionStateChangedStream.listen(
          _handleConnectionState,
          onError: _ignore,
        ),
      );
  }

  Future<void> stop() async {
    _log('manager stop: cancel subscriptions count=${_subscriptions.length}');
    _started = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (isFlashing.value) {
      isFlashing.value = false;
    }
  }

  @visibleForTesting
  void debugSetFlashing(bool value) {
    isFlashing.value = value;
  }

  void _handleStart(Map<String, dynamic> event) {
    _lastStartEvent = Map<String, dynamic>.from(event);
    _lastEndEvent = null;
    _audioFrameCount = 0;
    _activeActivityId =
        'card-${DateTime.now().microsecondsSinceEpoch}-${_activitySequence++}';
    _log('flash start event=$event');
    if (!isFlashing.value) {
      isFlashing.value = true;
    }
    CaptureActivityBus.instance.publish(
      CaptureActivityEvent(
        aliases: {captureActivityAlias('local', _activeActivityId)},
        source: CaptureActivitySource.card,
        phase: CaptureActivityPhase.listening,
        isRealtime: true,
        occurredAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _handleData(Map<String, dynamic> event) {
    if (!isFlashing.value) {
      isFlashing.value = true;
    }
    _audioFrameCount += 1;
  }

  void _handleEnd(Map<String, dynamic> event) {
    _lastEndEvent = Map<String, dynamic>.from(event);
    if (isFlashing.value) {
      isFlashing.value = false;
    }
    final info = (event['info'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fileName = (info['file'] ?? info['fileName'] ?? event['file'] ?? '')
        .toString();
    _log(
      'flash end code=${event['code']} file=$fileName '
      'frames=$_audioFrameCount info=$info',
    );
    if ((event['code'] == 0 || event['code'] == null) &&
        isFlashFileName(fileName)) {
      FlashFileWorkflow.instance.upsertRealtime(
        fileName: fileName,
        localActivityId: _activeActivityId,
        createTime: _asInt(info['createTime']),
        endTime: _asInt(info['endTime']),
        crc: _asInt(event['crc'] ?? info['crc']),
        deviceSizeBytes: _asInt(event['size'] ?? info['size']),
      );
    } else {
      _log('flash end ignored code=${event['code']} file=$fileName');
      final activityId = _activeActivityId;
      if (activityId != null) {
        CaptureActivityBus.instance.publish(
          CaptureActivityEvent(
            aliases: {captureActivityAlias('local', activityId)},
            source: CaptureActivitySource.card,
            phase: CaptureActivityPhase.failed,
            isRealtime: true,
            occurredAt: DateTime.now().toUtc(),
          ),
        );
      }
    }
    _activeActivityId = null;
  }

  void _handleConnectionState(Map<String, dynamic> event) {
    final connected =
        event['isConnected'] == true ||
        event['connected'] == true ||
        event['state']?.toString().toLowerCase() == 'connected';
    _log('connection state event=$event connected=$connected');
    FlashFileWorkflow.instance.handleConnectionChanged(connected);
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _ignore(Object error, StackTrace stackTrace) {
    _log('stream error=$error');
  }
}
