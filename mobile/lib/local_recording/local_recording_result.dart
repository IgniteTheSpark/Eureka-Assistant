import 'package:flutter/foundation.dart';

import '../flash/flash.dart';

enum LocalRecordingPhase {
  idle,
  requestingPermission,
  recording,
  transcribing,
  submitting,
  done,
  failed,
  cancelled,
}

extension LocalRecordingPhaseLabel on LocalRecordingPhase {
  bool get isBusy => switch (this) {
    LocalRecordingPhase.requestingPermission ||
    LocalRecordingPhase.recording ||
    LocalRecordingPhase.transcribing ||
    LocalRecordingPhase.submitting => true,
    _ => false,
  };
}

@immutable
class LocalRecordingResult {
  const LocalRecordingResult({
    required this.phase,
    this.audioPath,
    this.text,
    this.flash,
    this.error,
  });

  final LocalRecordingPhase phase;
  final String? audioPath;
  final String? text;
  final FlashResult? flash;
  final String? error;

  bool get isTerminal => switch (phase) {
    LocalRecordingPhase.done ||
    LocalRecordingPhase.failed ||
    LocalRecordingPhase.cancelled => true,
    _ => false,
  };
}
