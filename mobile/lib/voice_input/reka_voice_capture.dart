import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_input_controller.dart';
import 'voice_input_models.dart';
import 'voice_input_service.dart';

enum RekaVoiceCaptureState {
  idle,
  connecting,
  listening,
  cancelArmed,
  stopping,
  sending,
  error,
}

typedef RekaVoiceFlashSender =
    Future<void> Function(String text, String voiceSessionId);

/// Owns the asynchronous boundary between REKA's press gesture, streaming ASR,
/// and creating exactly one text Flash. It deliberately stores no audio and
/// never retries either operation.
final class RekaVoiceCaptureCoordinator extends ChangeNotifier {
  RekaVoiceCaptureCoordinator({
    required VoiceInputServiceClient service,
    required VoiceInputLease lease,
    required RekaVoiceFlashSender sendFlash,
    required VoidCallback haptic,
    this.maximumDuration = const Duration(minutes: 1),
    this.warningDuration = const Duration(seconds: 30),
    this.finalTimeout = const Duration(seconds: 10),
    this.cancelThreshold = 72,
  }) : _service = service,
       _lease = lease,
       _sendFlash = sendFlash,
       _haptic = haptic;

  final VoiceInputServiceClient _service;
  final VoiceInputLease _lease;
  final RekaVoiceFlashSender _sendFlash;
  final VoidCallback _haptic;
  final Duration maximumDuration;
  final Duration warningDuration;
  final Duration finalTimeout;
  final double cancelThreshold;

  final Duration productionMaximumDuration = const Duration(minutes: 1);
  final Duration productionWarningAt = const Duration(seconds: 30);

  RekaVoiceCaptureState _state = RekaVoiceCaptureState.idle;
  VoiceInputErrorCode? _errorCode;
  VoiceInputSessionHandle? _session;
  StreamSubscription<VoiceInputEvent>? _subscription;
  Timer? _warningTimer;
  Timer? _durationTimer;
  Timer? _finalTimer;
  final List<String> _stableParts = <String>[];
  String _partial = '';
  String? _pendingFinal;
  int _lastSequence = 0;
  int _epoch = 0;
  bool _held = false;
  bool _releaseRequested = false;
  bool _cancelRequested = false;
  bool _terminal = false;
  bool _closed = false;
  bool _leaseHeld = false;
  bool _durationWarning = false;
  Future<void>? _terminalFuture;

  RekaVoiceCaptureState get state => _state;
  VoiceInputErrorCode? get errorCode => _errorCode;
  bool get isActive => switch (_state) {
    RekaVoiceCaptureState.idle || RekaVoiceCaptureState.error => false,
    _ => true,
  };
  bool get isDurationWarning => _durationWarning;
  String get transcript {
    if (_pendingFinal != null) return _pendingFinal!.trim();
    final stable = _stableParts.fold<String>('', _appendTranscript);
    return _appendTranscript(stable, _partial);
  }

  Future<bool> begin() async {
    if (_closed || isActive) return false;
    if (!_lease.acquire(this)) {
      _errorCode = VoiceInputErrorCode.busy;
      _state = RekaVoiceCaptureState.error;
      _notify();
      return false;
    }
    _leaseHeld = true;
    final epoch = ++_epoch;
    _resetCapture();
    _held = true;
    _state = RekaVoiceCaptureState.connecting;
    _haptic();
    _notify();

    try {
      final session = await _service.start(VoiceInputMode.reka);
      if (!_isCurrent(epoch) || _terminal) {
        await _quietly(session.cancel);
        return false;
      }
      _session = session;
      _subscription = session.events.listen(
        (event) => _onEvent(event, epoch),
        onError: (_) => _beginFailure(
          VoiceInputErrorCode.connectionLost,
          epoch,
          cancelSession: false,
        ),
        onDone: () {
          if (!_terminal && _pendingFinal == null && _isCurrent(epoch)) {
            _beginFailure(
              VoiceInputErrorCode.connectionLost,
              epoch,
              cancelSession: false,
            );
          }
        },
      );
      _scheduleDurationLimits(epoch);
      if (_cancelRequested) {
        await _cancel(epoch);
      } else if (_releaseRequested) {
        await _stop(epoch);
      } else {
        _state = RekaVoiceCaptureState.listening;
        _notify();
      }
      return true;
    } on VoiceInputException catch (error) {
      if (_isCurrent(epoch)) {
        await _fail(error.code, epoch, cancelSession: false);
      }
      return false;
    } catch (_) {
      if (_isCurrent(epoch)) {
        await _fail(
          VoiceInputErrorCode.connectionFailed,
          epoch,
          cancelSession: false,
        );
      }
      return false;
    }
  }

  void updateVerticalOffset(double offsetFromOriginDy) {
    if (!isActive || _terminal) return;
    if (_state == RekaVoiceCaptureState.stopping ||
        _state == RekaVoiceCaptureState.sending) {
      return;
    }
    final wasArmed = _cancelRequested;
    _cancelRequested = offsetFromOriginDy <= -cancelThreshold;
    if (_cancelRequested && !wasArmed) _haptic();
    final next = _cancelRequested
        ? RekaVoiceCaptureState.cancelArmed
        : (_session == null
              ? RekaVoiceCaptureState.connecting
              : RekaVoiceCaptureState.listening);
    if (_state != next) {
      _state = next;
      _notify();
    }
  }

  Future<void> release() async {
    if (!isActive || _terminal) return;
    _held = false;
    _releaseRequested = true;
    final epoch = _epoch;
    if (_cancelRequested || _state == RekaVoiceCaptureState.cancelArmed) {
      await _cancel(epoch);
      return;
    }
    if (_session != null) await _stop(epoch);
  }

  Future<void> cancelGesture() async {
    if (!isActive || _terminal) return;
    _held = false;
    _releaseRequested = true;
    _cancelRequested = true;
    await _cancel(_epoch);
  }

  void _onEvent(VoiceInputEvent event, int epoch) {
    if (!_isCurrent(epoch) || _terminal) return;
    if (event is VoiceInputFailure) {
      _beginFailure(event.code, epoch, cancelSession: false);
      return;
    }
    if (event is! VoiceTranscriptEvent || event.sequence <= _lastSequence) {
      return;
    }
    _lastSequence = event.sequence;
    switch (event.kind) {
      case VoiceTranscriptKind.partial:
        _partial = event.text;
        _notify();
      case VoiceTranscriptKind.stable:
        _stableParts.add(event.text);
        _partial = '';
        _notify();
      case VoiceTranscriptKind.finalTranscript:
        _pendingFinal = event.text;
        _partial = '';
        _notify();
        if (!_held || _releaseRequested) {
          _cancelDurationTimers();
          _beginSubmit(event.text, epoch);
        }
    }
  }

  Future<void> _stop(int epoch) async {
    if (!_isCurrent(epoch) || _terminal) return;
    final finalText = _pendingFinal;
    if (finalText != null) {
      _beginSubmit(finalText, epoch);
      await _terminalFuture;
      return;
    }
    if (_state == RekaVoiceCaptureState.stopping) return;
    final session = _session;
    if (session == null) return;
    _state = RekaVoiceCaptureState.stopping;
    _cancelDurationTimers();
    _notify();
    try {
      await session.stop();
      if (!_isCurrent(epoch) || _terminal) return;
      _finalTimer = Timer(finalTimeout, () {
        _beginFailure(
          VoiceInputErrorCode.connectionLost,
          epoch,
          cancelSession: true,
        );
      });
    } catch (_) {
      await _fail(
        VoiceInputErrorCode.connectionLost,
        epoch,
        cancelSession: true,
      );
    }
  }

  void _beginSubmit(String text, int epoch) {
    if (_terminalFuture != null || _terminal) return;
    _terminalFuture = _submit(text, epoch);
  }

  Future<void> _submit(String rawText, int epoch) async {
    if (!_isCurrent(epoch) || _terminal) return;
    _terminal = true;
    _cancelAllTimers();
    final text = rawText.trim();
    final sessionId = _session?.voiceSessionId ?? '';
    final session = _session;
    final subscription = _subscription;
    _session = null;
    _subscription = null;
    _state = text.isEmpty
        ? RekaVoiceCaptureState.idle
        : RekaVoiceCaptureState.sending;
    _notify();

    try {
      await _quietly(session?.dispose);
      await _cancelSubscription(subscription);
      if (text.isNotEmpty) await _sendFlash(text, sessionId);
      if (_isCurrent(epoch)) {
        _errorCode = null;
        _state = RekaVoiceCaptureState.idle;
      }
    } catch (_) {
      if (_isCurrent(epoch)) {
        _errorCode = VoiceInputErrorCode.serviceUnavailable;
        _state = RekaVoiceCaptureState.error;
      }
    } finally {
      _releaseLease();
      _terminalFuture = null;
      _notify();
    }
  }

  Future<void> _cancel(int epoch) async {
    if (!_isCurrent(epoch) || _terminal) return;
    _terminal = true;
    _cancelAllTimers();
    final session = _session;
    final subscription = _subscription;
    _session = null;
    _subscription = null;
    _state = RekaVoiceCaptureState.idle;
    _notify();
    await _quietly(session?.cancel);
    await _cancelSubscription(subscription);
    _releaseLease();
  }

  void _beginFailure(
    VoiceInputErrorCode code,
    int epoch, {
    required bool cancelSession,
  }) {
    if (_terminalFuture != null || _terminal) return;
    _terminalFuture = _fail(code, epoch, cancelSession: cancelSession);
  }

  Future<void> _fail(
    VoiceInputErrorCode code,
    int epoch, {
    required bool cancelSession,
  }) async {
    if (!_isCurrent(epoch) || _terminal) return;
    _terminal = true;
    _cancelAllTimers();
    final session = _session;
    final subscription = _subscription;
    _session = null;
    _subscription = null;
    _errorCode = code;
    _state = RekaVoiceCaptureState.error;
    _notify();
    if (cancelSession) {
      await _quietly(session?.cancel);
    } else {
      await _quietly(session?.dispose);
    }
    await _cancelSubscription(subscription);
    _releaseLease();
    _terminalFuture = null;
  }

  void _scheduleDurationLimits(int epoch) {
    final warningDelay = maximumDuration - warningDuration;
    _warningTimer = Timer(
      warningDelay.isNegative ? Duration.zero : warningDelay,
      () {
        if (!_isCurrent(epoch) || _terminal) return;
        _durationWarning = true;
        _notify();
      },
    );
    _durationTimer = Timer(maximumDuration, () {
      if (!_isCurrent(epoch) || _terminal) return;
      _held = false;
      _releaseRequested = true;
      _cancelRequested = false;
      unawaited(_stop(epoch));
    });
  }

  void _resetCapture() {
    _cancelAllTimers();
    _errorCode = null;
    _session = null;
    _subscription = null;
    _stableParts.clear();
    _partial = '';
    _pendingFinal = null;
    _lastSequence = 0;
    _held = false;
    _releaseRequested = false;
    _cancelRequested = false;
    _terminal = false;
    _durationWarning = false;
    _terminalFuture = null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final session = _session;
    final subscription = _subscription;
    _session = null;
    _subscription = null;
    final shouldCancel = isActive && !_terminal;
    _terminal = true;
    if (shouldCancel) await _quietly(session?.cancel);
    await _cancelSubscription(subscription);
    await _terminalFuture;
    _cancelAllTimers();
    _releaseLease();
  }

  void _releaseLease() {
    if (!_leaseHeld) return;
    _leaseHeld = false;
    _lease.release(this);
  }

  bool _isCurrent(int epoch) => !_closed && epoch == _epoch;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _cancelDurationTimers() {
    _warningTimer?.cancel();
    _warningTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _cancelAllTimers() {
    _cancelDurationTimers();
    _finalTimer?.cancel();
    _finalTimer = null;
  }

  Future<void> _cancelSubscription(
    StreamSubscription<VoiceInputEvent>? subscription,
  ) async {
    try {
      await subscription?.cancel();
    } catch (_) {}
  }

  Future<void> _quietly(Future<void> Function()? action) async {
    if (action == null) return;
    try {
      await action();
    } catch (_) {}
  }
}

String _appendTranscript(String left, String right) {
  final cleanLeft = left.trim();
  final cleanRight = right.trim();
  if (cleanLeft.isEmpty) return cleanRight;
  if (cleanRight.isEmpty) return cleanLeft;
  final leftCode = cleanLeft.codeUnitAt(cleanLeft.length - 1);
  final rightCode = cleanRight.codeUnitAt(0);
  final needsSpace = !_isCjk(leftCode) && !_isCjkOrPunctuation(rightCode);
  return needsSpace ? '$cleanLeft $cleanRight' : '$cleanLeft$cleanRight';
}

bool _isCjk(int code) => code >= 0x3400 && code <= 0x9fff;

bool _isCjkOrPunctuation(int code) {
  return _isCjk(code) || '，。！？；：、）】》'.codeUnits.contains(code);
}
