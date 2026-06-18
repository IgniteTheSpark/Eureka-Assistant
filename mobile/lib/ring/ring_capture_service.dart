import 'dart:io';

import 'package:chiplet_ring/chiplet_ring.dart';

import '../api/api_client.dart';
import '../api/tencent_asr_s3_client.dart';
import '../ble_flash/flash_file_status_controller.dart';
import '../flash/flash.dart';
import 'ring_asr.dart';
import 'ring_capture_controller.dart';
import 'ring_reconnect.dart';

/// Wires the ring (chiplet_ring plugin) → Tencent ASR → /api/flash card creation.
///
/// Milestone 2, approach A: double-click the ring to record in real time; on the
/// second double-click the accumulated PCM is transcribed and filed as a flash card.
/// Reuses the existing ASR client and `sendFlash`; does not touch the W1/W2 card flow.

RingCaptureController? _ringCapture;
RingReconnect? _ringReconnect;

/// Start ring capture once. Idempotent — safe to call on every auth rebuild
/// (the auth gate in main.dart re-runs this block whenever it rebuilds).
void startRingCapture(ApiClient api) {
  if (_ringCapture != null) return;
  final ring = ChipletRing();
  // Keep the ring connected: reconnect on launch (saved MAC) + after drops.
  _ringReconnect = RingReconnect(ring)..start();
  final asrClient = TencentAsrS3Client(); // baseUrl defaults to AppConfig.tencentAsrBase
  final asr = RingAsr(
    recognize: (File wav) async {
      final r = await asrClient.recognizeFile(file: wav);
      return r.text;
    },
  );
  _ringCapture = RingCaptureController(
    keyEvents: ring.keyEvents,
    audioFrames:
        ring.audioFrames.map((f) => RingFrame(pcm: f.pcm, channels: f.channels, seq: f.seq)),
    startRecording: ring.startRecording,
    stopRecording: ring.stopRecording,
    transcribe: (pcm, sr, ch) => asr.transcribePcm(pcm, sampleRate: sr, channels: ch),
    createCard: (text) async {
      await sendFlash(api, text, source: 'voice');
    },
    // Mirror the card's progressive「Reka听到：…正在X」bubble (floating mascot)
    // instead of a single static line. Ring ASR is on-device, so the「听写」beat
    // has no server counterpart — the client must drive it.
    onPhase: (phase) {
      final s = FlashFileStatusController.instance;
      switch (phase) {
        case RingCapturePhase.recording:
          break; // recording on-device; no bubble until we have audio to file
        case RingCapturePhase.transcribing:
          s.processing('听写');
        case RingCapturePhase.filing:
          s.processing('整理');
        case RingCapturePhase.done:
        case RingCapturePhase.empty:
          s.clear();
        case RingCapturePhase.error:
          s.failed('');
      }
    },
  )..start();
}

/// Tear down on logout. Safe to call when not started.
Future<void> stopRingCapture() async {
  await _ringCapture?.dispose();
  _ringCapture = null;
  await _ringReconnect?.dispose();
  _ringReconnect = null;
}
