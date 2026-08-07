import 'dart:async';
import 'dart:typed_data';

/// Minimal frame shape so the controller is testable without the plugin types.
class RingFrame {
  RingFrame({required this.pcm, required this.channels, this.seq = 0});
  final Uint8List pcm;
  final int channels;

  /// Plugin frame sequence number. Gaps ⇒ BLE frames were dropped in transit
  /// (the main cause of「收音不完整」), which we'd otherwise never notice.
  final int seq;
}

typedef RecCmdFn = Future<void> Function();
typedef TranscribeFn =
    Future<String> Function(Uint8List pcm, int sampleRate, int channels);
typedef CreateCardFn = Future<void> Function(String text, String clientTaskId);
typedef CreateTaskIdFn = String Function();

/// Lifecycle phase of a ring capture, surfaced so the UI can mirror the card's
/// progressive「正在…」status instead of one static line.
enum RingCapturePhase { recording, transcribing, filing, done, empty, error }

typedef PhaseFn = void Function(RingCapturePhase phase);
typedef ActivityPhaseFn =
    void Function(RingCapturePhase phase, String clientTaskId);
typedef CaptureErrorFn = void Function(Object error);

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
    this.onPhase,
    this.onActivityPhase,
    this.onError,
    CreateTaskIdFn? createTaskId,
    this.sampleRate = 8000,
    this.stopDrain = const Duration(milliseconds: 400),
  }) : _keyEvents = keyEvents,
       _audioFrames = audioFrames,
       _startRecording = startRecording,
       _stopRecording = stopRecording,
       _transcribe = transcribe,
       _createCard = createCard,
       _createTaskId = createTaskId ?? _defaultTaskId;

  final Stream<int> _keyEvents;
  final Stream<RingFrame> _audioFrames;
  final RecCmdFn _startRecording;
  final RecCmdFn _stopRecording;
  final TranscribeFn _transcribe;
  final CreateCardFn _createCard;
  final CreateTaskIdFn _createTaskId;

  /// Capture lifecycle hook so the UI can mirror the card's progressive status.
  final PhaseFn? onPhase;
  final ActivityPhaseFn? onActivityPhase;
  final CaptureErrorFn? onError;
  final int sampleRate;

  /// After the stop command, keep buffering for this long so the in-flight BLE
  /// tail (audio already spoken but still arriving) isn't clipped off the end.
  final Duration stopDrain;

  StreamSubscription<int>? _keySub;
  StreamSubscription<RingFrame>? _audioSub;
  final BytesBuilder _buf = BytesBuilder();
  int _channels = 1;
  bool _recording = false;
  bool _finishing = false; // true across the stop→transcribe→file handshake
  String? _activeTaskId;
  static int _taskSequence = 0;

  static String _defaultTaskId() =>
      'ring-${DateTime.now().microsecondsSinceEpoch}-${_taskSequence++}';

  void _emitPhase(RingCapturePhase phase) {
    onPhase?.call(phase);
    final taskId = _activeTaskId;
    if (taskId != null) onActivityPhase?.call(phase, taskId);
  }

  void start() {
    _keySub ??= _keyEvents.listen((k) {
      if (k == 2) _toggle();
    });
    // Subscribe to the passive frame stream eagerly; only buffer while recording.
    _audioSub ??= _audioFrames.listen((f) {
      if (!_recording) return;
      _channels = f.channels;
      _buf.add(f.pcm);
    });
  }

  void _toggle() {
    if (_finishing) return; // ignore clicks during the stop handshake
    if (_recording) {
      _stop();
    } else {
      _beginRecording();
    }
  }

  void _beginRecording() {
    _buf.clear();
    _activeTaskId = _createTaskId();
    _recording = true;
    _emitPhase(RingCapturePhase.recording);
    // Fire-and-forget the start command; never let it throw into the key handler.
    _startRecording().catchError((_) {});
  }

  Future<void> _stop() async {
    _finishing = true;
    try {
      // Stop the hardware first, then keep buffering for a short drain so the
      // audio still in the BLE pipe (the tail of what was just said) lands —
      // previously we flipped `_recording=false` immediately and clipped it.
      try {
        await _stopRecording(); // CONTROL_AUDIO_ADPCM off
      } catch (_) {}
      if (stopDrain > Duration.zero) {
        await Future<void>.delayed(stopDrain);
      }
      _recording = false;
      final pcm = _buf.toBytes();
      if (pcm.isEmpty) {
        _emitPhase(RingCapturePhase.empty);
        return;
      }
      _emitPhase(RingCapturePhase.transcribing);
      final text = await _transcribe(pcm, sampleRate, _channels);
      if (text.trim().isEmpty) {
        _emitPhase(RingCapturePhase.empty);
        return;
      }
      _emitPhase(RingCapturePhase.filing);
      await _createCard(text, _activeTaskId!);
      _emitPhase(RingCapturePhase.done);
    } catch (error) {
      // swallow — a transcription/network failure must not break future captures
      onError?.call(error);
      _emitPhase(RingCapturePhase.error);
    } finally {
      _recording = false;
      _finishing = false;
      _activeTaskId = null;
    }
  }

  Future<void> dispose() async {
    await _keySub?.cancel();
    await _audioSub?.cancel();
  }
}
