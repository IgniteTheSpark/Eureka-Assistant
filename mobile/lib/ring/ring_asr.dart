import 'dart:io';
import 'dart:typed_data';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:path_provider/path_provider.dart';

/// Recognize callback — injectable for tests. Real impl wraps TencentAsrS3Client.recognizeFile.
typedef RecognizeFn = Future<String> Function(File wav);

class RingAsr {
  RingAsr({required RecognizeFn recognize, Future<Directory> Function()? getTempDir})
      : _recognize = recognize,
        _getTempDir = getTempDir ?? _defaultTempDir;

  final RecognizeFn _recognize;
  final Future<Directory> Function() _getTempDir;

  static Future<Directory> _defaultTempDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      // Fallback for pure-Dart test environments where the platform channel
      // is not available.
      return Directory.systemTemp;
    }
  }

  /// PCM -> WAV (temp file) -> recognize -> text.
  Future<String> transcribePcm(Uint8List pcm,
      {required int sampleRate, required int channels}) async {
    final wav = pcmToWav(pcm, sampleRate: sampleRate, channels: channels);
    final dir = await _getTempDir();
    final path = '${dir.path}/ring_capture_${pcm.length}.wav';
    final file = await File(path).writeAsBytes(wav);
    return _recognize(file);
  }
}
