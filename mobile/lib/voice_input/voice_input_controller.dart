import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'voice_input_coordinator.dart';
import 'voice_input_models.dart';

enum VoiceInputControllerState { idle, connecting, listening, stopping }

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
    required VoiceInputCoordinator coordinator,
    this.maximumDuration = const Duration(minutes: 5),
    this.warningDuration = const Duration(seconds: 30),
  }) {
    _binding = coordinator.bind(
      targetId: this,
      mode: VoiceInputMode.ordinary,
      callbacks: VoiceInputTargetCallbacks(
        onActivated: _onActivated,
        onTranscript: _onEvent,
        onCancelled: _onCancelled,
        onFailure: _onFailure,
      ),
    )..addListener(_onBindingChanged);
  }

  final VoiceInputTextController textController;
  late final VoiceInputTargetBinding _binding;
  final Duration maximumDuration;
  final Duration warningDuration;

  final Duration productionMaximumDuration = const Duration(minutes: 5);
  final Duration productionWarningAt = const Duration(seconds: 270);

  VoiceInputControllerState _state = VoiceInputControllerState.idle;
  VoiceInputErrorCode? _errorCode;
  TextEditingValue? _snapshot;
  Timer? _warningTimer;
  Timer? _durationTimer;
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
  bool get canStop => _state == VoiceInputControllerState.listening;
  bool get isDurationWarning => _durationWarning;
  int get terminalCount => _terminalCount;

  Future<bool> start() async {
    if (_closed || isBusy) return false;
    _errorCode = null;
    return _binding.start();
  }

  Future<void> stop() async {
    if (!canStop || _terminalLatched) return;
    await _binding.stop();
  }

  Future<void> cancel() async {
    if (!isBusy || _terminalLatched) return;
    await _binding.cancel();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancelAllTimers();
    _binding.removeListener(_onBindingChanged);
    await _binding.close();
  }

  void _onActivated() {
    _snapshot = textController.value;
    _captureInsertionRange(_snapshot!);
    _stableParts.clear();
    _provisional = '';
    _lastSequence = 0;
    _durationWarning = false;
    _terminalLatched = false;
    _errorCode = null;
    _state = VoiceInputControllerState.connecting;
    if (!_closed) notifyListeners();
  }

  void _onBindingChanged() {
    final next = switch (_binding.state) {
      VoiceInputCoordinatorState.idle => VoiceInputControllerState.idle,
      VoiceInputCoordinatorState.connecting =>
        VoiceInputControllerState.connecting,
      VoiceInputCoordinatorState.listening =>
        VoiceInputControllerState.listening,
      VoiceInputCoordinatorState.finalizing =>
        VoiceInputControllerState.stopping,
    };
    if (next == VoiceInputControllerState.listening &&
        _state != VoiceInputControllerState.listening) {
      _scheduleDurationLimits();
    }
    if (next == VoiceInputControllerState.stopping) {
      _cancelDurationTimers();
    }
    _state = next;
    if (!_closed) notifyListeners();
  }

  void _onEvent(VoiceTranscriptEvent event) {
    if (_terminalLatched) return;
    if (event.sequence <= _lastSequence) return;
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
        _completePresentation(restoreSnapshot: false, errorCode: null);
    }
  }

  void _onCancelled(VoiceInputCancelReason reason) {
    _completePresentation(restoreSnapshot: true, errorCode: null);
  }

  void _onFailure(VoiceInputErrorCode code) {
    _completePresentation(restoreSnapshot: true, errorCode: code);
  }

  void _completePresentation({
    required bool restoreSnapshot,
    required VoiceInputErrorCode? errorCode,
  }) {
    if (_terminalLatched) return;
    _terminalLatched = true;
    _cancelAllTimers();
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
    _terminalCount += 1;
    if (!_closed) notifyListeners();
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
  }

  @override
  void dispose() {
    if (!_closed) unawaited(close());
    super.dispose();
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
