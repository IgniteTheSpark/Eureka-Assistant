export 'src/models.dart';
export 'src/wav_writer.dart';

import 'src/models.dart';
import 'src/ring_platform.dart';

class ChipletRing {
  ChipletRing({RingPlatform? platform}) : _p = platform ?? RingPlatform();
  final RingPlatform _p;

  Stream<RingState> get state => _p.states();

  /// Ring gesture/button events. Codes: 0=long-press, 1=single, 2=double,
  /// 3=triple, 4=up, 5=down, 6=left, 7=right.
  Stream<int> get keyEvents => _p.keyEvents();

  Future<void> startScan() => _p.startScan();
  Future<void> stopScan() => _p.stopScan();
  Future<void> connect(String deviceId) => _p.connect(deviceId);
  Future<void> disconnect() => _p.disconnect();

  /// Passive stream of decoded 16-bit PCM frames. Subscribing does NOT start the
  /// hardware — frames only flow between [startRecording] and [stopRecording].
  Stream<RingAudioFrame> get audioFrames => _p.audioFrames();

  /// Start the ring streaming audio (CONTROL_AUDIO_ADPCM on). Frames arrive on [audioFrames].
  Future<void> startRecording() => _p.startRecording();
  Future<void> stopRecording() => _p.stopRecording();

  // ---- On-device (local) recording + file management ----
  /// Tell the ring to record locally to its own storage (green-LED mode).
  Future<void> startLocalRecording({int total = 1200, int slice = 600}) =>
      _p.startLocalRecording(total: total, slice: slice);
  Future<void> stopLocalRecording() => _p.stopLocalRecording();

  /// Request the on-device file list. Results stream on [fileEvents] as {kind:'item',...}.
  Future<void> getFileList() => _p.getFileList();

  /// Download a file; audio bytes arrive on [fileEvents] as {kind:'audio', pcm:[...]}.
  /// [type] is the file's type (last `_`-segment of its name); [id] is its identifier bytes.
  Future<void> downloadFile(int type, List<int> id) => _p.downloadFile(type, id);

  /// Delete one file by its identifier bytes.
  Future<void> deleteFile(List<int> id) => _p.deleteFile(id);

  /// Format the ring filesystem (deletes ALL local files).
  Future<void> formatFiles() => _p.formatFiles();

  /// File-op event stream: {kind: item|audio|text|done|deleted|formatted|memory|memoryFull, ...}.
  Stream<Map> get fileEvents => _p.fileEvents();

  // ---- Keep-alive / auto-reconnect ----
  /// Set the MAC to reconnect to (call before [reconnect] on launch).
  Future<void> setSavedMac(String mac) => _p.setSavedMac(mac);
  /// Reconnect to the last/saved device (BLEUtils.reconnectionLockByBLE).
  Future<void> reconnect() => _p.reconnect();
  Future<bool> isConnected() => _p.isConnected();
}
