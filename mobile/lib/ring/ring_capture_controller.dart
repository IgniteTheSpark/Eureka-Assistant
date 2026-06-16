import 'dart:async';
import 'dart:typed_data';

/// Minimal frame shape so the controller is testable without the plugin types.
class RingFrame {
  RingFrame({required this.pcm, required this.channels});
  final Uint8List pcm;
  final int channels;
}

typedef StartAudioFn = Stream<RingFrame> Function();
typedef StopAudioFn = Future<void> Function();
typedef TranscribeFn = Future<String> Function(Uint8List pcm, int sampleRate, int channels);
typedef CreateCardFn = Future<void> Function(String text);

/// Double-click the ring to start a capture; double-click again to stop, which
/// transcribes the accumulated PCM and files it as a flash card.
class RingCaptureController {
  RingCaptureController({
    required Stream<int> keyEvents,
    required StartAudioFn startAudio,
    required StopAudioFn stopAudio,
    required TranscribeFn transcribe,
    required CreateCardFn createCard,
    this.sampleRate = 8000,
  })  : _keyEvents = keyEvents,
        _startAudio = startAudio,
        _stopAudio = stopAudio,
        _transcribe = transcribe,
        _createCard = createCard;

  final Stream<int> _keyEvents;
  final StartAudioFn _startAudio;
  final StopAudioFn _stopAudio;
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
    // Subscribe eagerly so no frames are dropped when recording begins.
    _audioSub ??= _startAudio().listen((f) {
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
  }

  Future<void> _stop() async {
    _recording = false;
    await _stopAudio();
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
