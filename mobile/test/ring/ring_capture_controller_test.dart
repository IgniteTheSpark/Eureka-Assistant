import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_capture_controller.dart';

void main() {
  test(
    'double-click starts capture; second stops -> transcribe -> card',
    () async {
      final keys = StreamController<int>.broadcast();
      final audio = StreamController<List<int>>.broadcast();
      final cards = <String>[];
      final taskIds = <String>[];
      final activityTaskIds = <String>[];

      var startCmds = 0, stopCmds = 0;
      final c = RingCaptureController(
        keyEvents: keys.stream,
        audioFrames: audio.stream.map(
          (b) => RingFrame(pcm: Uint8List.fromList(b), channels: 1),
        ),
        startRecording: () async {
          startCmds++;
        },
        stopRecording: () async {
          stopCmds++;
        },
        transcribe: (pcm, sr, ch) async => 'hello ${pcm.length}',
        createCard: (text, taskId) async {
          cards.add(text);
          taskIds.add(taskId);
        },
        createTaskId: () => 'ring-task-1',
        onActivityPhase: (_, taskId) => activityTaskIds.add(taskId),
        stopDrain:
            Duration.zero, // no tail drain → deterministic timing in test
      );
      c.start();

      keys.add(2); // start
      await Future<void>.delayed(Duration.zero);
      audio.add(List.filled(800, 1));
      audio.add(List.filled(800, 2));
      await Future<void>.delayed(Duration.zero);
      keys.add(2); // stop -> transcribe -> card
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(startCmds, 1); // start command sent on first double-click
      expect(stopCmds, 1); // stop command sent on second
      expect(cards.length, 1);
      expect(cards.first, 'hello 1600');
      expect(taskIds.single, 'ring-task-1');
      expect(activityTaskIds, isNotEmpty);
      expect(activityTaskIds.toSet(), {'ring-task-1'});
      await c.dispose();
    },
  );

  test('stop drain keeps the in-flight BLE tail (not clipped)', () async {
    final keys = StreamController<int>.broadcast();
    final audio = StreamController<List<int>>.broadcast();
    final cards = <String>[];

    final c = RingCaptureController(
      keyEvents: keys.stream,
      audioFrames: audio.stream.map(
        (b) => RingFrame(pcm: Uint8List.fromList(b), channels: 1),
      ),
      startRecording: () async {},
      stopRecording: () async {},
      transcribe: (pcm, sr, ch) async => 'len ${pcm.length}',
      createCard: (text, _) async {
        cards.add(text);
      },
      stopDrain: const Duration(milliseconds: 50),
    );
    c.start();

    keys.add(2); // start
    await Future<void>.delayed(Duration.zero);
    audio.add(List.filled(800, 1));
    await Future<void>.delayed(Duration.zero);
    keys.add(2); // stop — but a frame is still in the BLE pipe
    await Future<void>.delayed(const Duration(milliseconds: 10));
    audio.add(List.filled(800, 2)); // arrives during the drain window
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Both frames captured (1600), not just the pre-stop 800.
    expect(cards.single, 'len 1600');
    await c.dispose();
  });

  test(
    'transcription failures are surfaced without breaking later captures',
    () async {
      final keys = StreamController<int>.broadcast();
      final audio = StreamController<RingFrame>.broadcast();
      final errors = <Object>[];
      final c = RingCaptureController(
        keyEvents: keys.stream,
        audioFrames: audio.stream,
        startRecording: () async {},
        stopRecording: () async {},
        transcribe: (_, _, _) async => throw StateError('asr rejected audio'),
        createCard: (_, _) async {},
        onError: errors.add,
        stopDrain: Duration.zero,
      )..start();

      keys.add(2);
      await Future<void>.delayed(Duration.zero);
      audio.add(RingFrame(pcm: Uint8List(16), channels: 1));
      await Future<void>.delayed(Duration.zero);
      keys.add(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(errors.single, isA<StateError>());
      await c.dispose();
    },
  );
}
