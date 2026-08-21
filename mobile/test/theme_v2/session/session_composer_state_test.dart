import 'package:eureka/theme_v2/session/session_composer_state.dart';
import 'package:eureka/voice_input/voice_input_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty unfocused composer is collapsed idle', () {
    final state = _derive();

    expect(state.mode, SessionComposerMode.collapsedIdle);
    expect(state.showFooter, isFalse);
    expect(state.showSend, isFalse);
    expect(state.canSend, isFalse);
    expect(state.canStartVoice, isTrue);
  });

  test('whitespace-only text remains collapsed idle', () {
    final state = _derive(text: '  \n  ');

    expect(state.mode, SessionComposerMode.collapsedIdle);
    expect(state.hasDraft, isFalse);
  });

  test('focus expands editing controls and draft enables send', () {
    final empty = _derive(hasFocus: true);
    final draft = _derive(hasFocus: true, text: '草稿');

    expect(empty.mode, SessionComposerMode.editing);
    expect(empty.showFooter, isTrue);
    expect(empty.showSend, isTrue);
    expect(empty.canSend, isFalse);
    expect(draft.mode, SessionComposerMode.editing);
    expect(draft.canSend, isTrue);
  });

  test('unfocused draft remains review ready and sendable', () {
    final state = _derive(text: '保留草稿');

    expect(state.mode, SessionComposerMode.reviewReady);
    expect(state.showFooter, isTrue);
    expect(state.showSend, isTrue);
    expect(state.canSend, isTrue);
  });

  for (final voiceState in [
    VoiceInputControllerState.connecting,
    VoiceInputControllerState.listening,
    VoiceInputControllerState.stopping,
  ]) {
    test('$voiceState wins over focus and draft and removes send', () {
      final state = _derive(
        hasFocus: true,
        text: '临时转录',
        voiceState: voiceState,
      );

      expect(state.mode, SessionComposerMode.voiceActive);
      expect(state.showFooter, isTrue);
      expect(state.showVoiceStatus, isTrue);
      expect(state.showSend, isFalse);
      expect(state.canSend, isFalse);
      expect(state.canStartVoice, isFalse);
    });
  }

  test('agent reply locks both actions without changing draft layout', () {
    final state = _derive(text: '保留草稿', agentReplying: true);

    expect(state.mode, SessionComposerMode.reviewReady);
    expect(state.showSend, isTrue);
    expect(state.canSend, isFalse);
    expect(state.canStartVoice, isFalse);
  });
}

SessionComposerPresentation _derive({
  bool hasFocus = false,
  String text = '',
  VoiceInputControllerState voiceState = VoiceInputControllerState.idle,
  bool agentReplying = false,
}) {
  return SessionComposerPresentation.derive(
    hasFocus: hasFocus,
    text: text,
    voiceState: voiceState,
    agentReplying: agentReplying,
  );
}
