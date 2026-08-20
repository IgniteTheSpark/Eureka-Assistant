import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_input_coordinator.dart';
import 'voice_input_models.dart';

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

/// Presents REKA's press gesture over the App-owned voice coordinator.
///
/// This class owns gesture and submission state only. The root coordinator is
/// the sole owner of the microphone and streaming ASR session.
final class RekaVoiceCaptureCoordinator extends ChangeNotifier {
  RekaVoiceCaptureCoordinator({
    required VoiceInputCoordinator coordinator,
    required RekaVoiceFlashSender sendFlash,
    required VoidCallback haptic,
    this.maximumDuration = const Duration(minutes: 1),
    this.warningDuration = const Duration(seconds: 30),
    this.cancelThreshold = 72,
  }) : _sendFlash = sendFlash,
       _haptic = haptic {
    _binding = coordinator.bind(
      targetId: this,
      mode: VoiceInputMode.reka,
      callbacks: VoiceInputTargetCallbacks(
        onActivated: _onActivated,
        onTranscript: _onTranscript,
        onCancelled: _onCancelled,
        onFailure: _onFailure,
      ),
    )..addListener(_onBindingChanged);
  }

  late final VoiceInputTargetBinding _binding;
  final RekaVoiceFlashSender _sendFlash;
  final VoidCallback _haptic;
  final Duration maximumDuration;
  final Duration warningDuration;
  final double cancelThreshold;

  final Duration productionMaximumDuration = const Duration(minutes: 1);
  final Duration productionWarningAt = const Duration(seconds: 30);

  RekaVoiceCaptureState _state = RekaVoiceCaptureState.idle;
  VoiceInputErrorCode? _errorCode;
  Timer? _warningTimer;
  Timer? _durationTimer;
  final List<String> _stableParts = <String>[];
  String _partial = '';
  String? _pendingFinal;
  String _voiceSessionId = '';
  int _lastSequence = 0;
  int _epoch = 0;
  bool _held = false;
  bool _releaseRequested = false;
  bool _cancelRequested = false;
  bool _terminal = false;
  bool _closed = false;
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
    final epoch = ++_epoch;
    _resetCapture();
    _held = true;
    _state = RekaVoiceCaptureState.connecting;
    _haptic();
    _notify();

    final started = await _binding.start();
    if (!_isCurrent(epoch) || _terminal || !started) return false;
    if (_cancelRequested) {
      await _cancel(epoch);
    } else if (_releaseRequested &&
        _binding.state == VoiceInputCoordinatorState.listening) {
      await _stop(epoch);
    }
    return true;
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
        : (_binding.state == VoiceInputCoordinatorState.connecting
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
    final finalText = _pendingFinal;
    if (finalText != null) {
      _beginSubmit(finalText, epoch);
      await _terminalFuture;
      return;
    }
    if (_binding.state == VoiceInputCoordinatorState.listening) {
      await _stop(epoch);
    }
  }

  Future<void> cancelGesture() async {
    if (!isActive || _terminal) return;
    _held = false;
    _releaseRequested = true;
    _cancelRequested = true;
    await _cancel(_epoch);
  }

  void _onActivated() {
    if (_closed) return;
    _state = RekaVoiceCaptureState.connecting;
    _notify();
  }

  void _onBindingChanged() {
    if (_closed || _terminal) return;
    switch (_binding.state) {
      case VoiceInputCoordinatorState.connecting:
        if (!_cancelRequested) _state = RekaVoiceCaptureState.connecting;
      case VoiceInputCoordinatorState.listening:
        _scheduleDurationLimits(_epoch);
        if (_cancelRequested) {
          unawaited(_cancel(_epoch));
          return;
        }
        if (_releaseRequested) {
          unawaited(_stop(_epoch));
          return;
        }
        _state = RekaVoiceCaptureState.listening;
      case VoiceInputCoordinatorState.finalizing:
        _cancelDurationTimers();
        _state = RekaVoiceCaptureState.stopping;
      case VoiceInputCoordinatorState.idle:
        if (_pendingFinal != null && _held) {
          _state = RekaVoiceCaptureState.listening;
        }
    }
    _notify();
  }

  void _onTranscript(VoiceTranscriptEvent event) {
    if (_closed || _terminal || event.sequence <= _lastSequence) return;
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
        _voiceSessionId = _binding.voiceSessionId ?? _voiceSessionId;
        _pendingFinal = event.text;
        _partial = '';
        _cancelDurationTimers();
        _notify();
        if (!_held || _releaseRequested) {
          _beginSubmit(event.text, _epoch);
        }
    }
  }

  void _onCancelled(VoiceInputCancelReason reason) {
    if (_closed) return;
    _epoch += 1;
    _terminal = true;
    _cancelAllTimers();
    _stableParts.clear();
    _partial = '';
    _pendingFinal = null;
    _voiceSessionId = '';
    _errorCode = null;
    _durationWarning = false;
    _state = RekaVoiceCaptureState.idle;
    _notify();
  }

  void _onFailure(VoiceInputErrorCode code) {
    if (_closed || _terminal) return;
    _terminal = true;
    _cancelAllTimers();
    _errorCode = code;
    _state = RekaVoiceCaptureState.error;
    _notify();
  }

  Future<void> _stop(int epoch) async {
    if (!_isCurrent(epoch) || _terminal) return;
    final finalText = _pendingFinal;
    if (finalText != null) {
      _beginSubmit(finalText, epoch);
      await _terminalFuture;
      return;
    }
    if (_binding.state != VoiceInputCoordinatorState.listening) return;
    _state = RekaVoiceCaptureState.stopping;
    _cancelDurationTimers();
    _notify();
    await _binding.stop();
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
    final sessionId = _voiceSessionId;
    _state = text.isEmpty
        ? RekaVoiceCaptureState.idle
        : RekaVoiceCaptureState.sending;
    _notify();

    try {
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
      _terminalFuture = null;
      _notify();
    }
  }

  Future<void> _cancel(int epoch) async {
    if (!_isCurrent(epoch) || _terminal) return;
    _terminal = true;
    _cancelAllTimers();
    _state = RekaVoiceCaptureState.idle;
    _notify();
    await _binding.cancel();
  }

  void _scheduleDurationLimits(int epoch) {
    if (_warningTimer != null || _durationTimer != null) return;
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
    _stableParts.clear();
    _partial = '';
    _pendingFinal = null;
    _voiceSessionId = '';
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
    _terminal = true;
    _cancelAllTimers();
    _binding.removeListener(_onBindingChanged);
    await _binding.close();
    await _terminalFuture;
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
