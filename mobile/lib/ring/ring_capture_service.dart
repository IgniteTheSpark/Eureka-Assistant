import 'dart:io';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/tencent_asr_s3_client.dart';
import '../capture_activity/capture_activity_bus.dart';
import '../capture_activity/capture_activity_event.dart';
import '../flash/flash.dart';
import 'ring_asr.dart';
import 'ring_capture_controller.dart';
import 'ring_reconnect.dart';

/// Most recent ring-capture flash result. Onboarding watches this to advance its
/// 「双击戒指说一句」step the moment a capture files a card. null = none yet in
/// the current listen window (set null before listening to ignore stale results).
final ValueNotifier<FlashResult?> ringLastFlash = ValueNotifier<FlashResult?>(
  null,
);

/// Wires the ring (chiplet_ring plugin) → Tencent ASR → /api/flash card creation.
///
/// Milestone 2, approach A: double-click the ring to record in real time; on the
/// second double-click the accumulated PCM is transcribed and filed as a flash card.
/// Reuses the existing ASR client and `sendFlash`; does not touch the W1/W2 card flow.

RingCaptureController? _ringCapture;

/// Start ring capture once. Idempotent — safe to call on every auth rebuild
/// (the auth gate in main.dart re-runs this block whenever it rebuilds).
void startRingCapture(ApiClient api) {
  if (_ringCapture != null) return;
  final ring = ChipletRing();
  // Keep the ring connected: scan-and-connect to the saved MAC on launch + after drops.
  RingReconnect.instance.start();
  final asrClient =
      TencentAsrS3Client(); // baseUrl defaults to AppConfig.tencentAsrBase
  final asr = RingAsr(
    recognize: (File wav) async {
      final r = await asrClient.recognizeFile(file: wav);
      return r.text;
    },
  );
  _ringCapture = RingCaptureController(
    keyEvents: ring.keyEvents,
    audioFrames: ring.audioFrames.map(
      (f) => RingFrame(pcm: f.pcm, channels: f.channels, seq: f.seq),
    ),
    startRecording: ring.startRecording,
    stopRecording: ring.stopRecording,
    transcribe: (pcm, sr, ch) =>
        asr.transcribePcm(pcm, sampleRate: sr, channels: ch),
    createCard: (text, clientTaskId) async {
      final result = await sendFlash(
        api,
        text,
        source: 'voice',
        clientTaskId: clientTaskId,
      );
      ringLastFlash.value = result; // onboarding's 戒指 capture step watches this
      CaptureActivityBus.instance.publish(
        CaptureActivityEvent(
          aliases: {
            captureActivityAlias('client', clientTaskId),
            captureActivityAlias('recording', result.recordingId),
          }..remove(''),
          source: CaptureActivitySource.ring,
          phase: result.ok
              ? (result.hasPending
                    ? CaptureActivityPhase.understanding
                    : CaptureActivityPhase.done)
              : CaptureActivityPhase.failed,
          isRealtime: true,
          sessionId: result.physicalSessionId.isEmpty
              ? null
              : result.physicalSessionId,
          inputTurnId: result.inputTurnId.isEmpty ? null : result.inputTurnId,
          resultCount: result.cards.length,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    },
    onError: (error) => debugPrint('Ring capture failed: $error'),
    onActivityPhase: (phase, clientTaskId) {
      final normalized = switch (phase) {
        RingCapturePhase.recording => CaptureActivityPhase.listening,
        RingCapturePhase.transcribing => CaptureActivityPhase.transcribing,
        RingCapturePhase.filing => CaptureActivityPhase.understanding,
        RingCapturePhase.empty => CaptureActivityPhase.empty,
        RingCapturePhase.error => CaptureActivityPhase.failed,
        // The HTTP response or SSE owns the real terminal result.
        RingCapturePhase.done => null,
      };
      if (normalized == null) return;
      CaptureActivityBus.instance.publish(
        CaptureActivityEvent(
          aliases: {captureActivityAlias('client', clientTaskId)},
          source: CaptureActivitySource.ring,
          phase: normalized,
          isRealtime: true,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    },
  )..start();
}

/// Tear down on logout. Safe to call when not started.
Future<void> stopRingCapture() async {
  await _ringCapture?.dispose();
  _ringCapture = null;
  await RingReconnect.instance.dispose();
}
