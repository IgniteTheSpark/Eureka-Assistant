import 'dart:async';
import 'dart:typed_data';

/// Minimal frame shape so the controller is testable without the plugin types.
class RingFrame {
  RingFrame({required this.pcm, required this.channels});
  final Uint8List pcm;
  final int channels;
}

typedef RecCmdFn = Future<void> Function();
typedef TranscribeFn = Future<String> Function(Uint8List pcm, int sampleRate, int channels);
typedef CreateCardFn = Future<void> Function(String text);

/// Double-click the ring to start a capture; double-click again to stop, which
/// transcribes the accumulated PCM and files it as a flash card.
///
/// [audioFrames] is the PASSIVE frame stream (subscribing has no hardware side
/// effect — frames only flow after [startRecording]). The start/stop COMMANDS are
/// separate so that double-click actually toggles the ring, and so that nothing is
/// recorded at app launch. Frames are buffered only while a capture is active.
class RingCaptureController {
  RingCaptureController({
    required Stream<int> keyEvents,
    required Stream<RingFrame> audioFrames,
    required RecCmdFn startRecording,
    required RecCmdFn stopRecording,
    required TranscribeFn transcribe,
    required CreateCardFn createCard,
    this.sampleRate = 8000,
  })  : _keyEvents = keyEvents,
        _audioFrames = audioFrames,
        _startRecording = startRecording,
        _stopRecording = stopRecording,
        _transcribe = transcribe,
        _createCard = createCard;

  final Stream<int> _keyEvents;
  final Stream<RingFrame> _audioFrames;
  final RecCmdFn _startRecording;
  final RecCmdFn _stopRecording;
  final TranscribeFn _transcribe;
  final CreateCardFn _createCard;
  final int sampleRate;

  StreamSubscription<int>? _keySub;
  StreamSubscription<RingFrame>? _audioSub;
  final BytesBuilder _buf = BytesBuilder();
  int _channels = 1;
  bool _recording = false;

  void start() {
    _keySub ??= _keyEvents.listen((k) {
      if (k == 2) _toggle();
    });
    // Subscribe to the passive frame stream eagerly; only buffer while recording.
    _audioSub ??= _audioFrames.listen((f) {
      if (_recording) {
        _channels = f.channels;
        _buf.add(f.pcm);
      }
    });
  }

  void _toggle() {
    if (_recording) {
      _stop();
    } else {
      _beginRecording();
    }
  }

  void _beginRecording() {
    _recording = true;
    _buf.clear();
    _startRecording(); // CONTROL_AUDIO_ADPCM on
  }

  Future<void> _stop() async {
    _recording = false;
    await _stopRecording(); // CONTROL_AUDIO_ADPCM off
    final pcm = _buf.toBytes();
    if (pcm.isEmpty) return;
    final text = await _transcribe(pcm, sampleRate, _channels);
    if (text.trim().isEmpty) return;
    await _createCard(text);
  }

  Future<void> dispose() async {
    await _keySub?.cancel();
    await _audioSub?.cancel();
  }
}
