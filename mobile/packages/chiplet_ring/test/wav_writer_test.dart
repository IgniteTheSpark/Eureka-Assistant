import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/src/wav_writer.dart';

void main() {
  test('wraps PCM into a valid 16-bit WAV header', () {
    final pcm = Uint8List.fromList(List.filled(8, 0));
    final wav = pcmToWav(pcm, sampleRate: 16000, channels: 1);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.length, 44 + pcm.length);
    expect(wav[34], 16);
    expect(wav[35], 0);
  });
}
