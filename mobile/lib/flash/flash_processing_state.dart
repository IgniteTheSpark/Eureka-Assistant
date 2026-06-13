import 'package:flutter/foundation.dart';

class FlashProcessingState {
  const FlashProcessingState({
    required this.sessionId,
    required this.recordingId,
    required this.inputTurnId,
    required this.message,
  });

  final String sessionId;
  final String recordingId;
  final String inputTurnId;
  final String message;
}

class FlashProcessingStatus {
  FlashProcessingStatus._();

  static final FlashProcessingStatus instance = FlashProcessingStatus._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Map<String, FlashProcessingState> _bySession = {};
  final Map<String, String> _sessionByRecording = {};

  FlashProcessingState? stateForSession(String sessionId) =>
      _bySession[sessionId];

  void applyCapture(Map<String, dynamic> payload) {
    final sessionId = payload['session_id']?.toString() ?? '';
    if (sessionId.isEmpty) return;
    final state = FlashProcessingState(
      sessionId: sessionId,
      recordingId: payload['recording_id']?.toString() ?? '',
      inputTurnId: payload['input_turn_id']?.toString() ?? '',
      message: '正在整理…',
    );
    _bySession[sessionId] = state;
    if (state.recordingId.isNotEmpty) {
      _sessionByRecording[state.recordingId] = sessionId;
    }
    revision.value++;
  }

  void applyFlashStatus(Map<String, dynamic> payload) {
    final status = payload['status']?.toString() ?? '';
    final sessionId = payload['session_id']?.toString() ?? '';
    final recordingId = payload['recording_id']?.toString() ?? '';
    final resolvedSessionId = sessionId.isNotEmpty
        ? sessionId
        : _sessionByRecording[recordingId] ?? '';
    if (resolvedSessionId.isEmpty) return;

    if (status == 'done' || status == 'failed') {
      _bySession.remove(resolvedSessionId);
      if (recordingId.isNotEmpty) _sessionByRecording.remove(recordingId);
      revision.value++;
      return;
    }

    if (status == 'processing_flash' || status == 'asr_done') {
      final current = _bySession[resolvedSessionId];
      _bySession[resolvedSessionId] = FlashProcessingState(
        sessionId: resolvedSessionId,
        recordingId: recordingId.isNotEmpty
            ? recordingId
            : current?.recordingId ?? '',
        inputTurnId:
            payload['input_turn_id']?.toString() ?? current?.inputTurnId ?? '',
        message: status == 'processing_flash' ? '分析中…' : '正在整理…',
      );
      if (recordingId.isNotEmpty) {
        _sessionByRecording[recordingId] = resolvedSessionId;
      }
      revision.value++;
    }
  }

  void clearSession(String sessionId) {
    final state = _bySession.remove(sessionId);
    if (state?.recordingId.isNotEmpty == true) {
      _sessionByRecording.remove(state!.recordingId);
    }
    if (state != null) revision.value++;
  }
}
