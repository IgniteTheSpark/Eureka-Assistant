import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class VoiceAudioCapture {
  Future<bool> hasPermission();

  Future<Stream<Uint8List>> startPcm16();

  Future<void> stop();

  Future<void> dispose();
}

final class RecordVoiceAudioCapture implements VoiceAudioCapture {
  RecordVoiceAudioCapture({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  bool _stopped = false;
  bool _disposed = false;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startPcm16() {
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        streamBufferSize: 6400,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (_stopped || _disposed) return;
    _stopped = true;
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _recorder.dispose();
  }
}
