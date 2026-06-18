import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_capture_controller.dart';

void main() {
  test('double-click starts capture; second stops -> transcribe -> card', () async {
    final keys = StreamController<int>.broadcast();
    final audio = StreamController<List<int>>.broadcast();
    final cards = <String>[];

    var startCmds = 0, stopCmds = 0;
    final c = RingCaptureController(
      keyEvents: keys.stream,
      audioFrames: audio.stream.map((b) => RingFrame(pcm: Uint8List.fromList(b), channels: 1)),
      startRecording: () async { startCmds++; },
      stopRecording: () async { stopCmds++; },
      transcribe: (pcm, sr, ch) async => 'hello ${pcm.length}',
      createCard: (text) async { cards.add(text); },
      stopDrain: Duration.zero,  // no tail drain → deterministic timing in test
    );
    c.start();

    keys.add(2);                 // start
    await Future<void>.delayed(Duration.zero);
    audio.add(List.filled(800, 1));
    audio.add(List.filled(800, 2));
    await Future<void>.delayed(Duration.zero);
    keys.add(2);                 // stop -> transcribe -> card
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(startCmds, 1);        // start command sent on first double-click
    expect(stopCmds, 1);         // stop command sent on second
    expect(cards.length, 1);
    expect(cards.first, 'hello 1600');
    await c.dispose();
  });

  test('stop drain keeps the in-flight BLE tail (not clipped)', () async {
    final keys = StreamController<int>.broadcast();
    final audio = StreamController<List<int>>.broadcast();
    final cards = <String>[];

    final c = RingCaptureController(
      keyEvents: keys.stream,
      audioFrames: audio.stream.map((b) => RingFrame(pcm: Uint8List.fromList(b), channels: 1)),
      startRecording: () async {},
      stopRecording: () async {},
      transcribe: (pcm, sr, ch) async => 'len ${pcm.length}',
      createCard: (text) async { cards.add(text); },
      stopDrain: const Duration(milliseconds: 50),
    );
    c.start();

    keys.add(2);                 // start
    await Future<void>.delayed(Duration.zero);
    audio.add(List.filled(800, 1));
    await Future<void>.delayed(Duration.zero);
    keys.add(2);                 // stop — but a frame is still in the BLE pipe
    await Future<void>.delayed(const Duration(milliseconds: 10));
    audio.add(List.filled(800, 2));   // arrives during the drain window
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Both frames captured (1600), not just the pre-stop 800.
    expect(cards.single, 'len 1600');
    await c.dispose();
  });
}
