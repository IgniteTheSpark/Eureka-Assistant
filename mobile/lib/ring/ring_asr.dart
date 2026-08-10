import 'dart:io';
import 'dart:typed_data';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:path_provider/path_provider.dart';

/// Recognize callback — injectable for tests. Real impl wraps TencentAsrS3Client.recognizeFile.
typedef RecognizeFn = Future<String> Function(File wav);

class RingAsr {
  RingAsr({
    required RecognizeFn recognize,
    Future<Directory> Function()? getTempDir,
  }) : _recognize = recognize,
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
  Future<String> transcribePcm(
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
    File? outputFile,
  }) async {
    final file = outputFile ?? await _temporaryWavFile(pcm.length);
    await writePcmWav(
      pcm,
      outputFile: file,
      sampleRate: sampleRate,
      channels: channels,
    );
    return transcribeWav(file);
  }

  Future<File> writePcmWav(
    Uint8List pcm, {
    required File outputFile,
    required int sampleRate,
    required int channels,
  }) async {
    const asrSampleRate = 16000;
    final normalizedPcm = sampleRate == asrSampleRate
        ? pcm
        : _resamplePcm16(
            pcm,
            sourceRate: sampleRate,
            targetRate: asrSampleRate,
            channels: channels,
          );
    final wav = pcmToWav(
      normalizedPcm,
      sampleRate: asrSampleRate,
      channels: channels,
    );
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(wav, flush: true);
    return outputFile;
  }

  Future<String> transcribeWav(File wav) => _recognize(wav);

  Future<File> _temporaryWavFile(int pcmLength) async {
    final directory = await _getTempDir();
    final sequence = DateTime.now().microsecondsSinceEpoch;
    return File('${directory.path}/ring_capture_${pcmLength}_$sequence.wav');
  }
}

Uint8List _resamplePcm16(
  Uint8List pcm, {
  required int sourceRate,
  required int targetRate,
  required int channels,
}) {
  if (pcm.isEmpty || sourceRate <= 0 || targetRate <= 0 || channels <= 0) {
    return pcm;
  }
  const bytesPerSample = 2;
  final frameBytes = channels * bytesPerSample;
  final sourceFrames = pcm.length ~/ frameBytes;
  if (sourceFrames == 0) return pcm;
  final targetFrames = (sourceFrames * targetRate / sourceRate).round();
  final source = ByteData.sublistView(pcm);
  final output = Uint8List(targetFrames * frameBytes);
  final target = ByteData.sublistView(output);
  for (var frame = 0; frame < targetFrames; frame++) {
    final sourcePosition = frame * sourceRate / targetRate;
    final leftFrame = sourcePosition.floor().clamp(0, sourceFrames - 1);
    final rightFrame = (leftFrame + 1).clamp(0, sourceFrames - 1);
    final fraction = sourcePosition - leftFrame;
    for (var channel = 0; channel < channels; channel++) {
      final leftOffset = (leftFrame * channels + channel) * bytesPerSample;
      final rightOffset = (rightFrame * channels + channel) * bytesPerSample;
      final left = source.getInt16(leftOffset, Endian.little);
      final right = source.getInt16(rightOffset, Endian.little);
      final sample = (left + (right - left) * fraction).round();
      final targetOffset = (frame * channels + channel) * bytesPerSample;
      target.setInt16(targetOffset, sample, Endian.little);
    }
  }
  return output;
}
