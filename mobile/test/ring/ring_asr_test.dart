import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_asr.dart';

void main() {
  test('transcribePcm writes wav and returns recognized text', () async {
    String? seenPath;
    final asr = RingAsr(
      recognize: (File f) async { seenPath = f.path; return '你好世界'; },
    );
    final pcm = Uint8List.fromList(List.filled(1600, 0));
    final text = await asr.transcribePcm(pcm, sampleRate: 8000, channels: 1);
    expect(text, '你好世界');
    expect(seenPath, isNotNull);
    expect(File(seenPath!).existsSync(), isTrue);
    expect(seenPath!.endsWith('.wav'), isTrue);
  });
}
