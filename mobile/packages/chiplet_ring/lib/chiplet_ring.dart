export 'src/models.dart';
export 'src/wav_writer.dart';

import 'src/models.dart';
import 'src/ring_platform.dart';

class ChipletRing {
  ChipletRing({RingPlatform? platform}) : _p = platform ?? RingPlatform();
  final RingPlatform _p;

  Stream<RingState> get state => _p.states();
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
