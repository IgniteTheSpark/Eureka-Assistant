import 'dart:async';
import 'dart:io';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/tencent_asr_s3_client.dart';
import '../capture_activity/capture_activity_bus.dart';
import '../capture_activity/capture_activity_event.dart';
import '../flash/flash.dart';
import 'ring_asr.dart';
import 'ring_capture_controller.dart';
import 'ring_capture_store.dart';
import 'ring_capture_task.dart';
import 'ring_file_gateway.dart';
import 'ring_file_workflow.dart';
import 'ring_reconnect.dart';

final ValueNotifier<FlashResult?> ringLastFlash = ValueNotifier<FlashResult?>(
  null,
);

RingCaptureController? _ringCapture;
RingFileWorkflow? _ringWorkflow;
RingFileGateway? _ringFileGateway;
ApiClient? _ringApi;
String? _ringOwnerUserId;
String? _ringWorkflowDeviceId;
Future<void>? _ringStartInFlight;

Future<void> startRingCapture({required String userId}) {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) {
    return Future<void>.error(
      ArgumentError.value(userId, 'userId', 'must not be empty'),
    );
  }
  if (_ringOwnerUserId == normalizedUserId &&
      (_ringCapture != null || _ringStartInFlight != null)) {
    return _ringStartInFlight ?? Future<void>.value();
  }
  final start = _startRingCapture(normalizedUserId);
  _ringStartInFlight = start;
  start.then<void>(
    (_) {
      if (identical(_ringStartInFlight, start)) _ringStartInFlight = null;
    },
    onError: (Object _, StackTrace _) {
      if (identical(_ringStartInFlight, start)) _ringStartInFlight = null;
    },
  );
  return start;
}

Future<void> _startRingCapture(String userId) async {
  if (_ringOwnerUserId != null && _ringOwnerUserId != userId) {
    await stopRingCapture();
  }
  if (_ringCapture != null) return;

  final api = ApiClient();
  final ring = ChipletRing();
  final fileGateway = RingFileGateway.production(ring: ring);
  final asrClient = TencentAsrS3Client();
  final asr = RingAsr(
    recognize: (File wav) async {
      final result = await asrClient.recognizeFile(file: wav);
      return result.text;
    },
  );
  late final RingFileWorkflow workflow;
  workflow = RingFileWorkflow(
    gateway: fileGateway,
    store: SharedPreferencesRingCaptureStore(),
    asr: asr,
    submit: (text, clientTaskId, provenance) async {
      final result = await sendFlash(
        api,
        text,
        source: 'voice',
        clientTaskId: clientTaskId,
        provenance: provenance,
      );
      ringLastFlash.value = result;
      _publishBackendResult(
        taskId: clientTaskId,
        provenance: provenance,
        result: result,
      );
      return result;
    },
    onActivity: _publishWorkflowActivity,
  );

  _ringApi = api;
  _ringOwnerUserId = userId;
  _ringFileGateway = fileGateway;
  _ringWorkflow = workflow;

  Future<RingFileWorkflow> ensureWorkflow() async {
    final preferences = await SharedPreferences.getInstance();
    final deviceId = preferences.getString('ring_mac')?.trim() ?? '';
    if (deviceId.isEmpty) {
      throw StateError('ring is not bound');
    }
    if (workflow.isStarted && _ringWorkflowDeviceId != deviceId) {
      await workflow.stop();
      _ringWorkflowDeviceId = null;
    }
    if (!workflow.isStarted) {
      await workflow.start(userId, deviceId);
      _ringWorkflowDeviceId = deviceId;
    }
    return workflow;
  }

  Future<void> resumeDurableRealtime() async {
    try {
      final activeWorkflow = await ensureWorkflow();
      await activeWorkflow.resumeRealtimeCaptures();
    } on Object {
      // No saved ring or no network yet. The next connection transition retries.
    }
  }

  RingReconnect.instance.onConnected = resumeDurableRealtime;
  await RingReconnect.instance.start();
  await resumeDurableRealtime();

  _ringCapture = RingCaptureController(
    keyEvents: ring.keyEvents,
    audioFrames: ring.audioFrames.map(
      (frame) =>
          RingFrame(pcm: frame.pcm, channels: frame.channels, seq: frame.seq),
    ),
    startRecording: ring.startRecording,
    stopRecording: ring.stopRecording,
    persistBegin: (taskId, startedAt) async {
      final activeWorkflow = await ensureWorkflow();
      await activeWorkflow.beginRealtimeCapture(taskId, startedAt: startedAt);
    },
    onCaptureStartFailed: (taskId, error) async {
      final activeWorkflow = _ringWorkflow;
      if (activeWorkflow?.isStarted == true) {
        await activeWorkflow!.failRealtimeStart(
          taskId,
          code: error is RingCaptureCancelledError
              ? 'live_capture_cancelled'
              : 'live_start_failed',
        );
      }
    },
    finishCapture: (payload) async {
      final activeWorkflow = await ensureWorkflow();
      final outcome = await activeWorkflow.finishRealtimeCapture(
        payload.taskId,
        payload.pcm,
        sampleRate: payload.sampleRate,
        channels: payload.channels,
        frameGapCount: payload.frameGapCount,
        endedAt: payload.endedAt,
      );
      return switch (outcome) {
        RingRealtimeCaptureOutcome.done => RingCaptureFinishOutcome.done,
        RingRealtimeCaptureOutcome.empty => RingCaptureFinishOutcome.empty,
        RingRealtimeCaptureOutcome.failed => RingCaptureFinishOutcome.failed,
      };
    },
    onError: (error) => debugPrint('Ring capture failed: ${error.runtimeType}'),
    onActivityPhase: (phase, clientTaskId) {
      if (phase != RingCapturePhase.recording) return;
      CaptureActivityBus.instance.publish(
        CaptureActivityEvent(
          aliases: {captureActivityAlias('client', clientTaskId)},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.listening,
          isRealtime: true,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    },
  )..start();
}

void _publishWorkflowActivity(
  RingCaptureTask? task,
  RingFileWorkflowPhase phase,
) {
  if (task == null) return;
  final capturePhase = switch (phase) {
    RingFileWorkflowPhase.receiving => CaptureActivityPhase.receiving,
    RingFileWorkflowPhase.transcribing => CaptureActivityPhase.transcribing,
    RingFileWorkflowPhase.submitting => CaptureActivityPhase.understanding,
    RingFileWorkflowPhase.failed => CaptureActivityPhase.failed,
    RingFileWorkflowPhase.done || RingFileWorkflowPhase.memoryFull => null,
  };
  if (capturePhase == null) return;
  final realtime = (task.deviceCaptureKey ?? '').startsWith('ring-realtime:');
  CaptureActivityBus.instance.publish(
    CaptureActivityEvent(
      aliases: _taskAliases(task),
      source: CaptureActivitySource.ring,
      phase: capturePhase,
      isRealtime: realtime,
      sessionId: task.sessionId,
      inputTurnId: task.inputTurnId,
      occurredAt: task.startedAt,
    ),
  );
}

void _publishBackendResult({
  required String taskId,
  required FlashCaptureProvenance provenance,
  required FlashResult result,
}) {
  CaptureActivityBus.instance.publish(
    CaptureActivityEvent(
      aliases: {
        captureActivityAlias('client', taskId),
        captureActivityAlias('device-capture', provenance.deviceCaptureKey),
        captureActivityAlias('device-file', provenance.deviceFileName),
        captureActivityAlias('recording', result.recordingId),
      }..remove(''),
      source: CaptureActivitySource.ring,
      phase: result.ok
          ? (result.hasPending
                ? CaptureActivityPhase.understanding
                : CaptureActivityPhase.done)
          : CaptureActivityPhase.failed,
      isRealtime: provenance.deviceCaptureKey.startsWith('ring-realtime:'),
      sessionId: result.physicalSessionId.isEmpty
          ? null
          : result.physicalSessionId,
      inputTurnId: result.inputTurnId.isEmpty ? null : result.inputTurnId,
      resultCount: result.cards.length,
      occurredAt:
          provenance.captureStartedAt?.toUtc() ?? DateTime.now().toUtc(),
    ),
  );
}

Set<String> _taskAliases(RingCaptureTask task) => {
  captureActivityAlias('client', task.id),
  captureActivityAlias('device-capture', task.deviceCaptureKey),
  captureActivityAlias('device-file', task.fileName),
  captureActivityAlias('recording', task.recordingId),
}..remove('');

Future<void> stopRingCapture() async {
  final starting = _ringStartInFlight;
  if (starting != null) {
    try {
      await starting;
    } on Object {
      // Continue tearing down any resources created before startup failed.
    }
  }
  await _ringCapture?.dispose();
  _ringCapture = null;
  RingReconnect.instance.onConnected = null;
  await RingReconnect.instance.dispose();
  await _ringWorkflow?.stop();
  _ringWorkflow = null;
  await _ringFileGateway?.dispose();
  _ringFileGateway = null;
  _ringApi?.close();
  _ringApi = null;
  _ringOwnerUserId = null;
  _ringWorkflowDeviceId = null;
}
