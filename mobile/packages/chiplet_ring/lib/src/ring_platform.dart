import 'package:flutter/services.dart';
import 'models.dart';

class RingPlatform {
  static const _methods = MethodChannel('chiplet_ring/methods');
  static const _audio = EventChannel('chiplet_ring/audio');
  static const _state = EventChannel('chiplet_ring/state');
  static const _key = EventChannel('chiplet_ring/key');
  static const _file = EventChannel('chiplet_ring/file');

  // Cache one broadcast stream per channel. Each EventChannel has a SINGLE native
  // sink; calling receiveBroadcastStream() again would re-trigger native onListen
  // and overwrite that sink, so only the last subscriber would get events. Sharing
  // one cached broadcast stream means a single native listen, fanned out in Dart —
  // so RingConnection, the pairing page, the reconnector, etc. all receive events.
  static final Stream<dynamic> _audioRaw = _audio.receiveBroadcastStream();
  static final Stream<dynamic> _stateRaw = _state.receiveBroadcastStream();
  static final Stream<dynamic> _keyRaw = _key.receiveBroadcastStream();
  static final Stream<dynamic> _fileRaw = _file.receiveBroadcastStream();

  Future<void> startScan() => _methods.invokeMethod('startScan');
  Future<void> stopScan() => _methods.invokeMethod('stopScan');
  Future<void> connect(String id) => _methods.invokeMethod('connect', {'id': id});
  Future<void> disconnect() => _methods.invokeMethod('disconnect');
  Future<void> startRecording() => _methods.invokeMethod('startRecording');
  Future<void> stopRecording() => _methods.invokeMethod('stopRecording');

  Stream<RingAudioFrame> audioFrames() =>
      _audioRaw.map((e) => RingAudioFrame.fromMap(e as Map));

  /// Ring gesture/key codes: 0=long-press 1=single 2=double 3=triple 4..7=swipes.
  Stream<int> keyEvents() =>
      _keyRaw.map((e) => (e as num).toInt());

  // ---- On-device (local) recording + file management ----
  Future<void> startLocalRecording({int total = 1200, int slice = 600}) =>
      _methods.invokeMethod('startLocalRecording', {'total': total, 'slice': slice});
  Future<void> stopLocalRecording() => _methods.invokeMethod('stopLocalRecording');
  Future<void> getFileList() => _methods.invokeMethod('getFileList');
  Future<void> downloadFile(int type, List<int> id) =>
      _methods.invokeMethod('downloadFile', {'type': type, 'id': id});
  Future<void> deleteFile(List<int> id) =>
      _methods.invokeMethod('deleteFile', {'id': id});
  Future<void> formatFiles() => _methods.invokeMethod('formatFiles');

  /// File-op events: {kind: item|audio|text|done|deleted|formatted|memory|memoryFull, ...}
  Stream<Map> fileEvents() =>
      _fileRaw.map((e) => e as Map);

  // ---- Keep-alive / auto-reconnect ----
  Future<void> setSavedMac(String mac) => _methods.invokeMethod('setSavedMac', {'mac': mac});
  Future<void> reconnect() => _methods.invokeMethod('reconnect');
  Future<bool> isConnected() async =>
      (await _methods.invokeMethod('isConnected')) == true;

  Stream<RingState> states() => _stateRaw.map((e) {
        final m = e as Map;
        return RingState(
          conn: RingConnState.values.asNameMap()[m['conn'] as String?] ?? RingConnState.error,
          devices: ((m['devices'] as List?) ?? [])
              .map((d) => RingDevice.fromMap(d as Map))
              .toList(),
        );
      });
}
