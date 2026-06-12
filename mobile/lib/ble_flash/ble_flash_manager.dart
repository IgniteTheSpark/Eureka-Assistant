import 'dart:async';

import 'package:br_flutter_plugin_ble/br_bluetooth_plugin.dart';
import 'package:flutter/foundation.dart';

/// App-wide BLE flash-memo event manager.
///
/// This layer only owns hardware events and shared flash state. Feature-specific
/// persistence/transcription will be added above it later.
class BleFlashManager {
  BleFlashManager._({BrBluetoothPlugin? ble})
    : _ble = ble ?? BrBluetoothPlugin.instance;

  static final BleFlashManager instance = BleFlashManager._();

  final BrBluetoothPlugin _ble;
  final ValueNotifier<bool> isFlashing = ValueNotifier<bool>(false);

  final List<StreamSubscription<Map<String, dynamic>>> _subscriptions = [];

  bool _started = false;
  int _audioFrameCount = 0;
  Map<String, dynamic>? _lastStartEvent;
  Map<String, dynamic>? _lastEndEvent;

  int get audioFrameCount => _audioFrameCount;
  Map<String, dynamic>? get lastStartEvent => _lastStartEvent;
  Map<String, dynamic>? get lastEndEvent => _lastEndEvent;

  void start() {
    if (_started) return;
    _started = true;
    _subscriptions
      ..add(_ble.flashIdeaStartStream.listen(_handleStart, onError: _ignore))
      ..add(_ble.flashIdeaDataStream.listen(_handleData, onError: _ignore))
      ..add(_ble.flashIdeaEndStream.listen(_handleEnd, onError: _ignore));
  }

  Future<void> stop() async {
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
    if (!isFlashing.value) {
      isFlashing.value = true;
    }
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
  }

  void _ignore(Object error, StackTrace stackTrace) {}
}
