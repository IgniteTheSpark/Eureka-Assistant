import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_asr.dart';

void main() {
  test('transcribePcm writes wav and returns recognized text', () async {
    String? seenPath;
    final asr = RingAsr(
      recognize: (File f) async {
        seenPath = f.path;
        return '你好世界';
      },
    );
    final pcm = Uint8List.fromList(List.filled(1600, 0));
    final text = await asr.transcribePcm(pcm, sampleRate: 8000, channels: 1);
    expect(text, '你好世界');
    expect(seenPath, isNotNull);
    expect(File(seenPath!).existsSync(), isTrue);
    expect(seenPath!.endsWith('.wav'), isTrue);
  });

  test('transcribePcm resamples 8k ring PCM to a 16k WAV for ASR', () async {
    Uint8List? wavBytes;
    final asr = RingAsr(
      recognize: (file) async {
        wavBytes = await file.readAsBytes();
        return '识别成功';
      },
    );
    final samples = Int16List.fromList([0, 1000, -1000, 500]);
    final pcm = Uint8List.view(
      samples.buffer,
      samples.offsetInBytes,
      samples.lengthInBytes,
    );

    await asr.transcribePcm(pcm, sampleRate: 8000, channels: 1);

    final wav = ByteData.sublistView(wavBytes!);
    expect(wav.getUint32(24, Endian.little), 16000);
    expect(wav.getUint32(40, Endian.little), 16);
  });
}
