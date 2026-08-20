enum VoiceInputMode { ordinary, reka }

extension VoiceInputModeWireName on VoiceInputMode {
  String get wireName => switch (this) {
    VoiceInputMode.ordinary => 'ordinary',
    VoiceInputMode.reka => 'reka',
  };

  Duration get maximumDuration => switch (this) {
    VoiceInputMode.ordinary => const Duration(minutes: 5),
    VoiceInputMode.reka => const Duration(minutes: 1),
  };
}

enum VoiceTranscriptKind { partial, stable, finalTranscript }

enum VoiceInputErrorCode {
  permissionDenied,
  unauthenticated,
  busy,
  connectionFailed,
  connectionLost,
  rateLimited,
  noSpeech,
  serviceUnavailable,
  unsupportedAudio,
  protocolError,
}

sealed class VoiceInputEvent {
  const VoiceInputEvent();
}

final class VoiceTranscriptEvent extends VoiceInputEvent {
  const VoiceTranscriptEvent({
    required this.kind,
    required this.sequence,
    required this.text,
    this.audioDurationMs,
  });

  final VoiceTranscriptKind kind;
  final int sequence;
  final String text;
  final int? audioDurationMs;

  @override
  bool operator ==(Object other) {
    return other is VoiceTranscriptEvent &&
        other.kind == kind &&
        other.sequence == sequence &&
        other.text == text &&
        other.audioDurationMs == audioDurationMs;
  }

  @override
  int get hashCode => Object.hash(kind, sequence, text, audioDurationMs);
}

final class VoiceInputFailure extends VoiceInputEvent {
  const VoiceInputFailure({required this.code, required this.retryable});

  final VoiceInputErrorCode code;
  final bool retryable;

  @override
  bool operator ==(Object other) {
    return other is VoiceInputFailure &&
        other.code == code &&
        other.retryable == retryable;
  }

  @override
  int get hashCode => Object.hash(code, retryable);
}

final class VoiceInputException implements Exception {
  const VoiceInputException(this.code, {this.retryable = false});

  final VoiceInputErrorCode code;
  final bool retryable;

  @override
  String toString() => 'VoiceInputException(${code.name})';
}
