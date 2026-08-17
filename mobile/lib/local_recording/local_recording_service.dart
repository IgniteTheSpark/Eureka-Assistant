import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../api/api_client.dart';
import '../api/eureka_flash_file_api.dart';
import '../api/tencent_asr_s3_client.dart';
import '../flash/flash.dart';
import 'local_recording_result.dart';

typedef LocalRecordingOnResult = void Function(LocalRecordingResult result);

class LocalRecordingService {
  LocalRecordingService({
    ApiClient? api,
    TencentAsrS3Client? asrClient,
    EurekaFlashFileApi? eurekaApi,
    AudioRecorder? recorder,
    Future<Directory> Function()? getTempDir,
    this.onResult,
  }) : _api = api ?? ApiClient(),
       _asrClient = asrClient ?? TencentAsrS3Client(),
       _recorder = recorder ?? AudioRecorder(),
       _getTempDir = getTempDir ?? getTemporaryDirectory {
    _eurekaApi = eurekaApi ?? EurekaFlashFileApi(api: _api);
  }

  static const _sampleRate = 16000;
  static const _logTag = '[LocalRecording]';
  static const _pendingPollInterval = Duration(seconds: 2);
  static const _pendingPollTimeout = Duration(seconds: 120);

  final ApiClient _api;
  final TencentAsrS3Client _asrClient;
  late final EurekaFlashFileApi _eurekaApi;
  final AudioRecorder _recorder;
  final Future<Directory> Function() _getTempDir;

  final LocalRecordingOnResult? onResult;
  final ValueNotifier<LocalRecordingResult> status = ValueNotifier(
    const LocalRecordingResult(phase: LocalRecordingPhase.idle),
  );

  bool _recording = false;
  bool _submitting = false;
  String? _activeAudioPath;

  void _log(String message) => debugPrint('$_logTag $message');

  void _emit(LocalRecordingResult result) {
    status.value = result;
    onResult?.call(result);
  }

  Future<bool> requestPermission() => _recorder.hasPermission(request: true);

  Future<void> startRecording() async {
    if (_recording || _submitting) return;
    _log('start recording requested');
    _emit(const LocalRecordingResult(phase: LocalRecordingPhase.requestingPermission));
    final granted = await _recorder.hasPermission(request: true);
    if (!granted) {
      _log('microphone permission denied');
      _emit(
        const LocalRecordingResult(
          phase: LocalRecordingPhase.failed,
          error: '麦克风权限被拒绝',
        ),
      );
      return;
    }
    try {
      final directory = await _getTempDir();
      final path = '${directory.path}/local_recording_'
          '${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: _sampleRate,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _recording = true;
      _activeAudioPath = path;
      _log('recording started path=$path');
      _emit(const LocalRecordingResult(phase: LocalRecordingPhase.recording));
    } catch (e) {
      _log('recording start failed error=$e');
      _emit(
        LocalRecordingResult(phase: LocalRecordingPhase.failed, error: '$e'),
      );
    }
  }

  Future<LocalRecordingResult?> stopRecording() async {
    if (!_recording) return null;
    _recording = false;
    final path = _activeAudioPath;
    _activeAudioPath = null;
    try {
      await _recorder.stop();
    } catch (e) {
      _log('recording stop failed error=$e');
      _emit(
        LocalRecordingResult(phase: LocalRecordingPhase.failed, error: '$e'),
      );
      return null;
    }
    if (path == null) {
      _emit(
        const LocalRecordingResult(
          phase: LocalRecordingPhase.failed,
          error: '录音路径丢失',
        ),
      );
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) {
      _log('recorded file missing path=$path');
      _emit(
        const LocalRecordingResult(
          phase: LocalRecordingPhase.failed,
          error: '录音文件不存在',
        ),
      );
      return null;
    }
    final size = await file.length();
    if (size == 0) {
      _log('recorded file empty path=$path');
      _emit(
        const LocalRecordingResult(
          phase: LocalRecordingPhase.failed,
          error: '录音内容为空',
        ),
      );
      return null;
    }
    _log('recording stopped path=$path bytes=$size');
    _emit(LocalRecordingResult(phase: LocalRecordingPhase.idle, audioPath: path));
    return LocalRecordingResult(phase: LocalRecordingPhase.idle, audioPath: path);
  }

  Future<LocalRecordingResult> transcribeAndSubmit(
    File audio, {
    String source = 'voice',
    DateTime? capturedAt,
  }) async {
    if (_submitting) {
      return status.value;
    }
    _submitting = true;
    try {
      _emit(const LocalRecordingResult(phase: LocalRecordingPhase.transcribing));
      final asr = await _asrClient.recognizeFile(file: audio);
      if (asr.text.trim().isEmpty) {
        _log('ASR returned empty text');
        _emit(
          const LocalRecordingResult(
            phase: LocalRecordingPhase.failed,
            error: '没有识别到内容',
          ),
        );
        return status.value;
      }
      _emit(const LocalRecordingResult(phase: LocalRecordingPhase.submitting));
      final bytes = await audio.readAsBytes();
      final now = DateTime.now();
      final startedAt = capturedAt ?? now;
      final flash = await sendFlash(
        _api,
        asr.text,
        source: source,
        provenance: FlashCaptureProvenance(
          deviceCaptureKey:
              'local-recording:${now.millisecondsSinceEpoch}',
          deviceKind: 'phone',
          deviceId: 'phone',
          deviceFileName: audio.uri.pathSegments.last,
          localAudioSha256: sha256.convert(bytes).toString(),
          localAudioSizeBytes: bytes.length,
          captureStartedAt: startedAt,
          captureEndedAt: now,
        ),
      );
      _log(
        'submitted ok=${flash.ok} recording=${flash.recordingId} '
        'hasPending=${flash.hasPending} textLen=${asr.text.length}',
      );
      LocalRecordingResult result;
      if (!flash.ok) {
        result = LocalRecordingResult(
          phase: LocalRecordingPhase.failed,
          audioPath: audio.path,
          text: asr.text,
          flash: flash,
          error: flash.error,
        );
      } else if (!flash.hasPending) {
        result = LocalRecordingResult(
          phase: LocalRecordingPhase.done,
          audioPath: audio.path,
          text: asr.text,
          flash: flash,
        );
      } else {
        final pending = await _awaitRecordingFinal(
          flash.recordingId,
          audioPath: audio.path,
          text: asr.text,
        );
        if (pending != null) {
          result = pending;
        } else {
          _log('recording still pending after timeout, report as pending');
          result = LocalRecordingResult(
            phase: LocalRecordingPhase.submitting,
            audioPath: audio.path,
            text: asr.text,
            flash: flash,
            error: '后端仍在处理，请稍后查看结果',
          );
        }
      }
      _emit(result);
      return result;
    } catch (e) {
      _log('transcribe or submit failed error=$e');
      _emit(
        LocalRecordingResult(phase: LocalRecordingPhase.failed, error: '$e'),
      );
      return status.value;
    } finally {
      _submitting = false;
    }
  }

  Future<LocalRecordingResult?> _awaitRecordingFinal(
    String recordingId, {
    required String audioPath,
    required String text,
  }) async {
    final deadline = DateTime.now().add(_pendingPollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pendingPollInterval);
      try {
        final response = await _eurekaApi.getRecording(recordingId);
        final recording =
            (response['recording'] as Map?)?.cast<String, dynamic>();
        final processStatus = recording?['process_status']?.toString();
        _log('poll recording=$recordingId process=$processStatus');
        switch (processStatus) {
          case 'done':
            return LocalRecordingResult(
              phase: LocalRecordingPhase.done,
              audioPath: audioPath,
              text: text,
            );
          case 'empty':
            return LocalRecordingResult(
              phase: LocalRecordingPhase.failed,
              audioPath: audioPath,
              text: text,
              error: '没有识别到内容',
            );
          case 'failed':
            final message =
                recording?['asr_error']?.toString() ??
                recording?['error_message']?.toString() ??
                '整理失败';
            return LocalRecordingResult(
              phase: LocalRecordingPhase.failed,
              audioPath: audioPath,
              text: text,
              error: message,
            );
          case 'asr_processing':
          case 'asr_done':
          case 'agent_processing':
            continue;
          default:
            _log('unexpected process status=$processStatus, continue polling');
        }
      } catch (e) {
        _log('poll recording failed error=$e, continue polling');
      }
    }
    _log('poll recording timed out recording=$recordingId');
    return null;
  }

  Future<void> cancelRecording() async {
    if (!_recording) return;
    _recording = false;
    _activeAudioPath = null;
    try {
      await _recorder.cancel();
    } catch (e) {
      _log('recording cancel failed error=$e');
    }
    _emit(const LocalRecordingResult(phase: LocalRecordingPhase.cancelled));
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    _asrClient.close();
    _api.close();
  }
}
