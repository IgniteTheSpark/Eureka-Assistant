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

  Stream<RingAudioFrame> startRecording() {
    final s = _p.audioFrames();
    _p.startRecording();
    return s;
  }

  Future<void> stopRecording() => _p.stopRecording();
}
