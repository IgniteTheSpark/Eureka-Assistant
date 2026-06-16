import 'package:flutter/services.dart';
import 'models.dart';

class RingPlatform {
  static const _methods = MethodChannel('chiplet_ring/methods');
  static const _audio = EventChannel('chiplet_ring/audio');
  static const _state = EventChannel('chiplet_ring/state');

  Future<void> startScan() => _methods.invokeMethod('startScan');
  Future<void> stopScan() => _methods.invokeMethod('stopScan');
  Future<void> connect(String id) => _methods.invokeMethod('connect', {'id': id});
  Future<void> disconnect() => _methods.invokeMethod('disconnect');
  Future<void> startRecording() => _methods.invokeMethod('startRecording');
  Future<void> stopRecording() => _methods.invokeMethod('stopRecording');

  Stream<RingAudioFrame> audioFrames() =>
      _audio.receiveBroadcastStream().map((e) => RingAudioFrame.fromMap(e as Map));

  Stream<RingState> states() => _state.receiveBroadcastStream().map((e) {
        final m = e as Map;
        return RingState(
          conn: RingConnState.values.asNameMap()[m['conn'] as String?] ?? RingConnState.error,
          devices: ((m['devices'] as List?) ?? [])
              .map((d) => RingDevice.fromMap(d as Map))
              .toList(),
        );
      });
}
