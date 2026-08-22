import 'package:flutter/foundation.dart';

import '../../voice_input/voice_input_controller.dart';

enum SessionComposerMode { collapsedIdle, editing, voiceActive, reviewReady }

@immutable
final class SessionComposerPresentation {
  const SessionComposerPresentation._({
    required this.mode,
    required this.hasDraft,
    required this.voiceState,
    required this.agentReplying,
  });

  factory SessionComposerPresentation.derive({
    required bool hasFocus,
    required String text,
    required VoiceInputControllerState voiceState,
    required bool agentReplying,
  }) {
    final hasDraft = text.trim().isNotEmpty;
    final mode = voiceState != VoiceInputControllerState.idle
        ? SessionComposerMode.voiceActive
        : hasFocus
        ? SessionComposerMode.editing
        : hasDraft
        ? SessionComposerMode.reviewReady
        : SessionComposerMode.collapsedIdle;
    return SessionComposerPresentation._(
      mode: mode,
      hasDraft: hasDraft,
      voiceState: voiceState,
      agentReplying: agentReplying,
    );
  }

  final SessionComposerMode mode;
  final bool hasDraft;
  final VoiceInputControllerState voiceState;
  final bool agentReplying;

  bool get showFooter => mode != SessionComposerMode.collapsedIdle;

  bool get showSend =>
      mode == SessionComposerMode.editing ||
      mode == SessionComposerMode.reviewReady;

  bool get showVoiceStatus => mode == SessionComposerMode.voiceActive;

  bool get canSend => showSend && hasDraft && !agentReplying;

  bool get canStartVoice =>
      voiceState == VoiceInputControllerState.idle && !agentReplying;
}
