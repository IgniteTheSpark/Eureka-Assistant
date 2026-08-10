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
typedef PersistCaptureBeginFn =
    Future<void> Function(String clientTaskId, DateTime startedAt);
typedef CaptureStartFailedFn =
    Future<void> Function(String clientTaskId, Object error);

enum RingCaptureFinishOutcome { done, empty, failed }

class RingCaptureCancelledError implements Exception {
  const RingCaptureCancelledError();
}

class RingCapturePayload {
  const RingCapturePayload({
    required this.taskId,
    required this.pcm,
    required this.sampleRate,
    required this.channels,
    required this.frameGapCount,
    required this.startedAt,
    required this.endedAt,
  });

  final String taskId;
  final Uint8List pcm;
  final int sampleRate;
  final int channels;
  final int frameGapCount;
  final DateTime startedAt;
  final DateTime endedAt;
}

typedef FinishCaptureFn =
    Future<RingCaptureFinishOutcome> Function(RingCapturePayload payload);

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
    TranscribeFn? transcribe,
    CreateCardFn? createCard,
    this.persistBegin,
    this.onCaptureStartFailed,
    this.finishCapture,
    this.onPhase,
    this.onActivityPhase,
    this.onError,
    CreateTaskIdFn? createTaskId,
    this.sampleRate = 8000,
    this.stopDrain = const Duration(milliseconds: 400),
  }) : assert(
         finishCapture != null || (transcribe != null && createCard != null),
         'transcribe/createCard or finishCapture must be provided',
       ),
       _keyEvents = keyEvents,
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
  final TranscribeFn? _transcribe;
  final CreateCardFn? _createCard;
  final CreateTaskIdFn _createTaskId;

  /// Capture lifecycle hook so the UI can mirror the card's progressive status.
  final PhaseFn? onPhase;
  final ActivityPhaseFn? onActivityPhase;
  final CaptureErrorFn? onError;
  final PersistCaptureBeginFn? persistBegin;
  final CaptureStartFailedFn? onCaptureStartFailed;
  final FinishCaptureFn? finishCapture;
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
  DateTime? _startedAt;
  int? _lastFrameSeq;
  int _frameGapCount = 0;
  Future<void>? _lifecycleOperation;
  bool _disposed = false;
  static int _taskSequence = 0;

  static String _defaultTaskId() =>
      'ring-${DateTime.now().microsecondsSinceEpoch}-${_taskSequence++}';

  void _emitPhase(RingCapturePhase phase) {
    onPhase?.call(phase);
    final taskId = _activeTaskId;
    if (taskId != null) onActivityPhase?.call(phase, taskId);
  }

  void start() {
    if (_disposed) throw StateError('ring capture controller is disposed');
    _keySub ??= _keyEvents.listen((k) {
      if (k == 2) _toggle();
    });
    // Subscribe to the passive frame stream eagerly; only buffer while recording.
    _audioSub ??= _audioFrames.listen((f) {
      if (!_recording) return;
      _channels = f.channels;
      if (f.seq > 0) {
        final previous = _lastFrameSeq;
        if (previous != null && f.seq > previous + 1) {
          _frameGapCount += f.seq - previous - 1;
        }
        if (previous == null || f.seq > previous) _lastFrameSeq = f.seq;
      }
      _buf.add(f.pcm);
    });
  }

  void _toggle() {
    if (_finishing) return; // ignore clicks during the stop handshake
    if (_recording) {
      _track(_stop());
    } else {
      _track(_beginRecording());
    }
  }

  void _track(Future<void> operation) {
    _lifecycleOperation = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_lifecycleOperation, operation)) {
            _lifecycleOperation = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_lifecycleOperation, operation)) {
            _lifecycleOperation = null;
          }
        },
      ),
    );
  }

  Future<void> _beginRecording() async {
    _finishing = true;
    _buf.clear();
    _activeTaskId = _createTaskId();
    _startedAt = DateTime.now().toUtc();
    _lastFrameSeq = null;
    _frameGapCount = 0;
    var persisted = false;
    try {
      await persistBegin?.call(_activeTaskId!, _startedAt!);
      persisted = true;
      _recording = true;
      await _startRecording();
      _emitPhase(RingCapturePhase.recording);
    } catch (error) {
      _recording = false;
      if (persisted) {
        try {
          await onCaptureStartFailed?.call(_activeTaskId!, error);
        } catch (_) {}
      }
      onError?.call(error);
      _emitPhase(RingCapturePhase.error);
      _activeTaskId = null;
      _startedAt = null;
    } finally {
      _finishing = false;
    }
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
      final durableFinish = finishCapture;
      if (durableFinish != null) {
        if (pcm.isNotEmpty) _emitPhase(RingCapturePhase.transcribing);
        final outcome = await durableFinish(
          RingCapturePayload(
            taskId: _activeTaskId!,
            pcm: pcm,
            sampleRate: sampleRate,
            channels: _channels,
            frameGapCount: _frameGapCount,
            startedAt: _startedAt!,
            endedAt: DateTime.now().toUtc(),
          ),
        );
        _emitPhase(switch (outcome) {
          RingCaptureFinishOutcome.done => RingCapturePhase.done,
          RingCaptureFinishOutcome.empty => RingCapturePhase.empty,
          RingCaptureFinishOutcome.failed => RingCapturePhase.error,
        });
        return;
      }
      if (pcm.isEmpty) {
        _emitPhase(RingCapturePhase.empty);
        return;
      }
      _emitPhase(RingCapturePhase.transcribing);
      final text = await _transcribe!(pcm, sampleRate, _channels);
      if (text.trim().isEmpty) {
        _emitPhase(RingCapturePhase.empty);
        return;
      }
      _emitPhase(RingCapturePhase.filing);
      await _createCard!(text, _activeTaskId!);
      _emitPhase(RingCapturePhase.done);
    } catch (error) {
      // swallow — a transcription/network failure must not break future captures
      onError?.call(error);
      _emitPhase(RingCapturePhase.error);
    } finally {
      _recording = false;
      _finishing = false;
      _activeTaskId = null;
      _startedAt = null;
      _lastFrameSeq = null;
      _frameGapCount = 0;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _keySub?.cancel();
    await _audioSub?.cancel();
    final lifecycle = _lifecycleOperation;
    if (lifecycle != null) await lifecycle;
    if (_recording) {
      try {
        await _stopRecording();
      } on Object {
        // Continue local teardown even if the BLE stop command is unavailable.
      }
      _recording = false;
      final taskId = _activeTaskId;
      if (taskId != null) {
        try {
          await onCaptureStartFailed?.call(
            taskId,
            const RingCaptureCancelledError(),
          );
        } on Object {
          // Disposal must complete even if durable failure persistence fails.
        }
      }
    }
    _activeTaskId = null;
    _startedAt = null;
  }
}
