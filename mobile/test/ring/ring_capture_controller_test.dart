import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_capture_controller.dart';

void main() {
  test('double-click starts capture; second stops -> transcribe -> card', () async {
    final keys = StreamController<int>.broadcast();
    final audio = StreamController<List<int>>.broadcast();
    final cards = <String>[];

    final c = RingCaptureController(
      keyEvents: keys.stream,
      startAudio: () { return audio.stream.map((b) =>
          RingFrame(pcm: Uint8List.fromList(b), channels: 1)); },
      stopAudio: () async {},
      transcribe: (pcm, sr, ch) async => 'hello ${pcm.length}',
      createCard: (text) async { cards.add(text); },
    );
    c.start();

    keys.add(2);                 // start
    audio.add(List.filled(800, 1));
    audio.add(List.filled(800, 2));
    await Future<void>.delayed(Duration.zero);
    keys.add(2);                 // stop -> transcribe -> card
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(cards.length, 1);
    expect(cards.first, 'hello 1600');
    await c.dispose();
  });
}
