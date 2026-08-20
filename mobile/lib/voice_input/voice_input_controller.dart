import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'voice_input_models.dart';
import 'voice_input_service.dart';

enum VoiceInputControllerState { idle, connecting, listening, stopping }

final class VoiceInputLease {
  static final VoiceInputLease shared = VoiceInputLease();

  Object? _owner;

  bool acquire(Object owner) {
    if (_owner != null) return identical(_owner, owner);
    _owner = owner;
    return true;
  }

  void release(Object owner) {
    if (identical(_owner, owner)) _owner = null;
  }

  bool isOwnedBy(Object owner) => identical(_owner, owner);
  bool get isActive => _owner != null;
}

final class VoiceInputTextController extends TextEditingController {
  VoiceInputTextController({String? text, TextSelection? selection})
    : super.fromValue(
        TextEditingValue(
          text: text ?? '',
          selection:
              selection ?? TextSelection.collapsed(offset: (text ?? '').length),
        ),
      );

  VoiceInputTextController.fromValue(super.value) : super.fromValue();

  TextRange? _provisionalRange;
  TextRange? get provisionalRange => _provisionalRange;

  void setVoiceValue(TextEditingValue next, {TextRange? provisionalRange}) {
    _provisionalRange = provisionalRange;
    value = next;
  }

  void clearProvisionalStyle() {
    if (_provisionalRange == null) return;
    _provisionalRange = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final range = _provisionalRange;
    if (range == null || !range.isValid || range.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final safeStart = range.start.clamp(0, text.length);
    final safeEnd = range.end.clamp(safeStart, text.length);
    final provisionalStyle = (style ?? const TextStyle()).copyWith(
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
    );
    return TextSpan(
      style: style,
      children: [
        if (safeStart > 0) TextSpan(text: text.substring(0, safeStart)),
        TextSpan(
          text: text.substring(safeStart, safeEnd),
          style: provisionalStyle,
        ),
        if (safeEnd < text.length) TextSpan(text: text.substring(safeEnd)),
      ],
    );
  }
}

final class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required this.textController,
    required VoiceInputServiceClient service,
    VoiceInputLease? lease,
    this.maximumDuration = const Duration(minutes: 5),
    this.warningDuration = const Duration(seconds: 30),
    this.finalTimeout = const Duration(seconds: 10),
  }) : _service = service,
       _lease = lease ?? VoiceInputLease.shared;

  final VoiceInputTextController textController;
  final VoiceInputServiceClient _service;
  final VoiceInputLease _lease;
  final Duration maximumDuration;
  final Duration warningDuration;
  final Duration finalTimeout;

  final Duration productionMaximumDuration = const Duration(minutes: 5);
  final Duration productionWarningAt = const Duration(seconds: 270);

  VoiceInputControllerState _state = VoiceInputControllerState.idle;
  VoiceInputErrorCode? _errorCode;
  VoiceInputSessionHandle? _session;
  StreamSubscription<VoiceInputEvent>? _subscription;
  TextEditingValue? _snapshot;
  Timer? _warningTimer;
  Timer? _durationTimer;
  Timer? _finalTimer;
  final List<String> _stableParts = <String>[];
  String _provisional = '';
  int _lastSequence = 0;
  int _insertionStart = 0;
  int _insertionEnd = 0;
  bool _durationWarning = false;
  bool _terminalLatched = false;
  bool _closed = false;
  int _terminalCount = 0;

  VoiceInputControllerState get state => _state;
  VoiceInputErrorCode? get errorCode => _errorCode;
  bool get isBusy => _state != VoiceInputControllerState.idle;
  bool get isStopping => _state == VoiceInputControllerState.stopping;
  bool get canStop =>
      _state == VoiceInputControllerState.listening && _session != null;
  bool get isDurationWarning => _durationWarning;
  int get terminalCount => _terminalCount;

  Future<bool> start() async {
    if (_closed || isBusy) return false;
    _errorCode = null;
    if (!_lease.acquire(this)) {
      _errorCode = VoiceInputErrorCode.busy;
      notifyListeners();
      return false;
    }

    _snapshot = textController.value;
    _captureInsertionRange(_snapshot!);
    _stableParts.clear();
    _provisional = '';
    _lastSequence = 0;
    _durationWarning = false;
    _terminalLatched = false;
    _state = VoiceInputControllerState.connecting;
    notifyListeners();

    try {
      final session = await _service.start(VoiceInputMode.ordinary);
      if (_closed || _terminalLatched) {
        await session.cancel();
        return false;
      }
      _session = session;
      _subscription = session.events.listen(
        _onEvent,
        onError: (_) => _startFailure(
          VoiceInputErrorCode.connectionLost,
          cancelSession: false,
        ),
        onDone: () {
          if (!_terminalLatched) {
            _startFailure(
              VoiceInputErrorCode.connectionLost,
              cancelSession: false,
            );
          }
        },
      );
      _state = VoiceInputControllerState.listening;
      _scheduleDurationLimits();
      notifyListeners();
      return true;
    } on VoiceInputException catch (error) {
      await _finish(
        restoreSnapshot: true,
        errorCode: error.code,
        cancelSession: false,
      );
      return false;
    } catch (_) {
      await _finish(
        restoreSnapshot: true,
        errorCode: VoiceInputErrorCode.connectionFailed,
        cancelSession: false,
      );
      return false;
    }
  }

  Future<void> stop() async {
    if (!canStop || _terminalLatched) return;
    _state = VoiceInputControllerState.stopping;
    _cancelDurationTimers();
    notifyListeners();
    try {
      await _session!.stop();
      if (_terminalLatched) return;
      _finalTimer = Timer(finalTimeout, () {
        _startFailure(VoiceInputErrorCode.connectionLost, cancelSession: true);
      });
    } catch (_) {
      await _finish(
        restoreSnapshot: true,
        errorCode: VoiceInputErrorCode.connectionLost,
        cancelSession: true,
      );
    }
  }

  Future<void> cancel() async {
    if (!isBusy || _terminalLatched) return;
    await _finish(restoreSnapshot: true, errorCode: null, cancelSession: true);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (isBusy && !_terminalLatched) {
      await _finish(
        restoreSnapshot: true,
        errorCode: null,
        cancelSession: true,
      );
    }
    _cancelAllTimers();
    await _subscription?.cancel();
    _lease.release(this);
  }

  void _onEvent(VoiceInputEvent event) {
    if (_terminalLatched) return;
    if (event is VoiceInputFailure) {
      _startFailure(event.code, cancelSession: false);
      return;
    }
    if (event is! VoiceTranscriptEvent || event.sequence <= _lastSequence) {
      return;
    }
    _lastSequence = event.sequence;
    switch (event.kind) {
      case VoiceTranscriptKind.partial:
        _provisional = event.text;
        _renderVoiceText();
      case VoiceTranscriptKind.stable:
        _stableParts.add(event.text);
        _provisional = '';
        _renderVoiceText();
      case VoiceTranscriptKind.finalTranscript:
        _applyFinalText(event.text);
        _terminalLatched = true;
        unawaited(
          _finish(
            restoreSnapshot: false,
            errorCode: null,
            cancelSession: false,
            alreadyLatched: true,
          ),
        );
    }
  }

  void _startFailure(VoiceInputErrorCode code, {required bool cancelSession}) {
    if (_terminalLatched) return;
    _terminalLatched = true;
    unawaited(
      _finish(
        restoreSnapshot: true,
        errorCode: code,
        cancelSession: cancelSession,
        alreadyLatched: true,
      ),
    );
  }

  Future<void> _finish({
    required bool restoreSnapshot,
    required VoiceInputErrorCode? errorCode,
    required bool cancelSession,
    bool alreadyLatched = false,
  }) async {
    if (!alreadyLatched) {
      if (_terminalLatched) return;
      _terminalLatched = true;
    }
    _cancelAllTimers();
    final session = _session;
    final subscription = _subscription;
    _subscription = null;
    _session = null;

    final sessionCleanup = _cleanSession(session, cancel: cancelSession);
    final subscriptionCleanup = subscription?.cancel();

    // Restore/commit the field synchronously. Network and stream teardown may
    // take another event-loop turn, but the terminal latch already suppresses
    // every late callback and the user should see cancel/final immediately.
    if (restoreSnapshot && _snapshot != null) {
      textController.setVoiceValue(_snapshot!);
    } else {
      textController.clearProvisionalStyle();
    }
    _stableParts.clear();
    _provisional = '';
    _errorCode = errorCode;
    _durationWarning = false;
    _state = VoiceInputControllerState.idle;
    _lease.release(this);
    _terminalCount += 1;
    if (!_closed) notifyListeners();

    await sessionCleanup;
    try {
      await subscriptionCleanup;
    } catch (_) {}
  }

  Future<void> _cleanSession(
    VoiceInputSessionHandle? session, {
    required bool cancel,
  }) async {
    if (session == null) return;
    try {
      if (cancel) {
        await session.cancel();
      } else {
        await session.dispose();
      }
    } catch (_) {}
  }

  void _captureInsertionRange(TextEditingValue snapshot) {
    final length = snapshot.text.length;
    final selection = snapshot.selection;
    if (!selection.isValid) {
      _insertionStart = length;
      _insertionEnd = length;
      return;
    }
    _insertionStart = math.min(selection.start, selection.end).clamp(0, length);
    _insertionEnd = math.max(selection.start, selection.end).clamp(0, length);
  }

  void _renderVoiceText() {
    final stable = _stableParts.fold<String>('', _appendTranscript);
    final voiceText = _appendTranscript(stable, _provisional);
    final provisionalStart = _provisional.isEmpty
        ? null
        : _insertionStart + voiceText.length - _provisional.length;
    _replaceInsertion(
      voiceText,
      provisionalRange: provisionalStart == null
          ? null
          : TextRange(
              start: provisionalStart,
              end: provisionalStart + _provisional.length,
            ),
    );
    notifyListeners();
  }

  void _applyFinalText(String text) {
    _replaceInsertion(text.trim());
  }

  void _replaceInsertion(String voiceText, {TextRange? provisionalRange}) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final nextText = snapshot.text.replaceRange(
      _insertionStart,
      _insertionEnd,
      voiceText,
    );
    final cursor = _insertionStart + voiceText.length;
    textController.setVoiceValue(
      TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: cursor),
      ),
      provisionalRange: provisionalRange,
    );
  }

  void _scheduleDurationLimits() {
    final warningDelay = maximumDuration - warningDuration;
    _warningTimer = Timer(
      warningDelay.isNegative ? Duration.zero : warningDelay,
      () {
        if (_terminalLatched || !isBusy) return;
        _durationWarning = true;
        notifyListeners();
      },
    );
    _durationTimer = Timer(maximumDuration, () => unawaited(stop()));
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
