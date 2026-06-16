import 'dart:io';

import 'package:chiplet_ring/chiplet_ring.dart';

import '../api/api_client.dart';
import '../api/tencent_asr_s3_client.dart';
import '../flash/flash.dart';
import 'ring_asr.dart';
import 'ring_capture_controller.dart';

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
  final asrClient = TencentAsrS3Client(); // baseUrl defaults to AppConfig.tencentAsrBase
  final asr = RingAsr(
    recognize: (File wav) async {
      final r = await asrClient.recognizeFile(file: wav);
      return r.text;
    },
  );
  _ringCapture = RingCaptureController(
    keyEvents: ring.keyEvents,
    audioFrames: ring.audioFrames.map((f) => RingFrame(pcm: f.pcm, channels: f.channels)),
    startRecording: ring.startRecording,
    stopRecording: ring.stopRecording,
    transcribe: (pcm, sr, ch) => asr.transcribePcm(pcm, sampleRate: sr, channels: ch),
    createCard: (text) async {
      await sendFlash(api, text, source: 'voice');
    },
  )..start();
}

/// Tear down on logout. Safe to call when not started.
Future<void> stopRingCapture() async {
  await _ringCapture?.dispose();
  _ringCapture = null;
}
