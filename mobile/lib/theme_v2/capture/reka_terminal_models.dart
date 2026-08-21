import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';
import 'thinking_orb.dart';

enum RekaTerminalPhase {
  connecting,
  listening,
  cancelArmed,
  transcribing,
  sending,
  receiving,
  understanding,
  organizing,
  done,
  empty,
  failed,
}

@immutable
class RekaTerminalModel {
  const RekaTerminalModel({
    required this.identity,
    required this.aliases,
    required this.source,
    required this.phase,
    required this.statusLabel,
    this.transcript = '',
    this.resultCount,
    this.queuedCount = 0,
    this.canOpenDetail = false,
  });

  final String identity;
  final Set<String> aliases;
  final CaptureActivitySource source;
  final RekaTerminalPhase phase;
  final String statusLabel;
  final String transcript;
  final int? resultCount;
  final int queuedCount;
  final bool canOpenDetail;

  String get sourceCommand => source.rekaCommand;
  ThinkingOrbVisualState get orbState => phase.orbState;
  Color headerTint(Brightness brightness) => phase.headerTint(brightness);
}

extension CaptureActivitySourceRekaCopy on CaptureActivitySource {
  String get rekaCommand => switch (this) {
    CaptureActivitySource.app => 'REKA://APP',
    CaptureActivitySource.ring => 'REKA://RING',
    CaptureActivitySource.card => 'REKA://CARD',
    CaptureActivitySource.audioUpload => 'REKA://UPLOAD',
  };
}

extension RekaTerminalPhasePresentation on RekaTerminalPhase {
  ThinkingOrbVisualState get orbState => switch (this) {
    RekaTerminalPhase.connecting ||
    RekaTerminalPhase.listening ||
    RekaTerminalPhase.cancelArmed => ThinkingOrbVisualState.listening,
    RekaTerminalPhase.transcribing => ThinkingOrbVisualState.transcribing,
    RekaTerminalPhase.sending ||
    RekaTerminalPhase.organizing => ThinkingOrbVisualState.organizing,
    RekaTerminalPhase.receiving => ThinkingOrbVisualState.receiving,
    RekaTerminalPhase.understanding => ThinkingOrbVisualState.understanding,
    RekaTerminalPhase.done => ThinkingOrbVisualState.success,
    RekaTerminalPhase.empty => ThinkingOrbVisualState.empty,
    RekaTerminalPhase.failed => ThinkingOrbVisualState.failed,
  };

  Color headerTint(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      RekaTerminalPhase.connecting || RekaTerminalPhase.listening =>
        dark ? const Color(0xFF123C49) : const Color(0xFFD6F5F8),
      RekaTerminalPhase.cancelArmed =>
        dark ? const Color(0xFF512B35) : const Color(0xFFFFE0E5),
      RekaTerminalPhase.transcribing || RekaTerminalPhase.receiving =>
        dark ? const Color(0xFF302C59) : const Color(0xFFE8E4FF),
      RekaTerminalPhase.sending ||
      RekaTerminalPhase.understanding ||
      RekaTerminalPhase.organizing =>
        dark ? const Color(0xFF472C52) : const Color(0xFFF4E2F6),
      RekaTerminalPhase.done =>
        dark ? const Color(0xFF34432E) : const Color(0xFFE8F1D9),
      RekaTerminalPhase.empty || RekaTerminalPhase.failed =>
        dark ? const Color(0xFF4B2C35) : const Color(0xFFFFE4E5),
    };
  }
}
