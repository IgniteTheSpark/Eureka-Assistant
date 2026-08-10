import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../flash/flash.dart';
import 'ring_asr.dart';
import 'ring_capture_store.dart';
import 'ring_capture_task.dart';
import 'ring_file_gateway.dart';

enum RingFileWorkflowPhase {
  receiving,
  transcribing,
  submitting,
  done,
  failed,
  memoryFull,
}

enum RingRealtimeCaptureOutcome { done, empty, failed }

typedef SubmitRecoveredFlash =
    Future<FlashResult> Function(
      String text,
      String clientTaskId,
      FlashCaptureProvenance provenance,
    );
typedef RingFileWorkflowActivityCallback =
    void Function(RingCaptureTask? task, RingFileWorkflowPhase phase);

class RingFileWorkflow {
  RingFileWorkflow({
    required RingFileAccess gateway,
    required RingCaptureStore store,
    required RingAsr asr,
    required SubmitRecoveredFlash submit,
    Future<Directory> Function()? getSupportDirectory,
    DateTime Function()? now,
    this.onActivity,
    this.associationRetryDelay = const Duration(seconds: 2),
  }) : _gateway = gateway,
       _store = store,
       _asr = asr,
       _submit = submit,
       _getSupportDirectory =
           getSupportDirectory ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final RingFileAccess _gateway;
  final RingCaptureStore _store;
  final RingAsr _asr;
  final SubmitRecoveredFlash _submit;
  final Future<Directory> Function() _getSupportDirectory;
  final DateTime Function() _now;
  final RingFileWorkflowActivityCallback? onActivity;
  final Duration associationRetryDelay;

  final Map<String, RingCaptureTask> _tasks = {};
  final Map<String, Future<void>> _recoveries = {};
  final Set<Timer> _associationTimers = {};
  StreamSubscription<void>? _memoryFullSubscription;
  Future<void>? _scanInFlight;
  Future<void>? _realtimeResumeInFlight;
  String? _userId;
  String? _deviceId;

  bool get isStarted => _userId != null && _deviceId != null;

  Future<void> start(String userId, String deviceId) async {
    final normalizedUserId = userId.trim();
    final normalizedDeviceId = deviceId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    if (normalizedDeviceId.isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
    }
    if (isStarted) {
      if (_userId == normalizedUserId && _deviceId == normalizedDeviceId) {
        return;
      }
      throw StateError('ring file workflow is already owned by another user');
    }

    _userId = normalizedUserId;
    _deviceId = normalizedDeviceId;
    _tasks
      ..clear()
      ..addEntries(
        (await _store.load(normalizedUserId))
            .where(
              (task) =>
                  task.deviceId.trim().toUpperCase() ==
                  normalizedDeviceId.toUpperCase(),
            )
            .map((task) => MapEntry(task.id, task)),
      );
    _memoryFullSubscription = _gateway.memoryFullEvents.listen((_) {
      onActivity?.call(null, RingFileWorkflowPhase.memoryFull);
      _ignoreErrors(scanAndRecover());
    });
    _restoreTaskActivities();
  }

  void _restoreTaskActivities() {
    for (final task in _tasks.values) {
      if (task.stage == RingCaptureStage.done) continue;
      final phase = switch (task.stage) {
        RingCaptureStage.provisional ||
        RingCaptureStage.recording => RingFileWorkflowPhase.failed,
        RingCaptureStage.transcribing => RingFileWorkflowPhase.transcribing,
        RingCaptureStage.submitting ||
        RingCaptureStage.accepted ||
        RingCaptureStage.deletingDeviceFile => RingFileWorkflowPhase.submitting,
        RingCaptureStage.failed => RingFileWorkflowPhase.failed,
        _ => RingFileWorkflowPhase.receiving,
      };
      onActivity?.call(task, phase);
    }
  }

  Future<RingCaptureTask> beginRealtimeCapture(
    String taskId, {
    DateTime? startedAt,
  }) async {
    _requireStarted();
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      throw ArgumentError.value(taskId, 'taskId', 'must not be empty');
    }
    final existing = _tasks[normalizedTaskId];
    if (existing != null) {
      if (existing.deviceId.toUpperCase() != _deviceId!.toUpperCase()) {
        throw StateError('realtime task belongs to a different ring');
      }
      return existing;
    }
    final captureKey = ringRealtimeCaptureKey(
      deviceId: _deviceId!,
      taskId: normalizedTaskId,
    );
    final now = _utcNow();
    final task = RingCaptureTask(
      id: normalizedTaskId,
      userId: _userId!,
      deviceId: _deviceId!,
      stage: RingCaptureStage.recording,
      startedAt: (startedAt ?? now).toUtc(),
      updatedAt: now,
      fileName: _realtimeFileName(captureKey),
      deviceCaptureKey: captureKey,
    );
    await _save(task);
    return task;
  }

  Future<void> failRealtimeStart(
    String taskId, {
    String code = 'live_start_failed',
  }) async {
    _requireStarted();
    final task = _tasks[taskId];
    if (task == null) return;
    await _fail(task, code);
  }

  Future<RingRealtimeCaptureOutcome> finishRealtimeCapture(
    String taskId,
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
    required int frameGapCount,
    DateTime? endedAt,
  }) async {
    _requireStarted();
    final storedTask = _tasks[taskId];
    if (storedTask == null) {
      throw StateError('realtime ring capture task not found');
    }
    var task = storedTask.copyWith(endedAt: (endedAt ?? _utcNow()).toUtc());
    await _save(task);
    if (pcm.isEmpty) {
      await _fail(task, 'empty_device_audio');
      return RingRealtimeCaptureOutcome.empty;
    }

    try {
      final outputFile = await _stableWavFile(task);
      final wav = await _asr.writePcmWav(
        pcm,
        outputFile: outputFile,
        sampleRate: sampleRate,
        channels: channels,
      );
      final bytes = await wav.readAsBytes();
      task = task.copyWith(
        stage: RingCaptureStage.downloaded,
        updatedAt: _utcNow(),
        localWavPath: wav.path,
        localAudioSha256: sha256.convert(bytes).toString(),
        localAudioSizeBytes: bytes.length,
        lastErrorCode: null,
      );
      await _save(task);
    } on Object {
      await _fail(task, 'local_write_failed');
      return RingRealtimeCaptureOutcome.failed;
    }

    if (frameGapCount > 0) {
      await _fail(task, 'live_frame_gap');
      return RingRealtimeCaptureOutcome.failed;
    }
    task = await _transcribe(task);
    if (task.stage == RingCaptureStage.failed) {
      return task.lastErrorCode == 'empty_transcript'
          ? RingRealtimeCaptureOutcome.empty
          : RingRealtimeCaptureOutcome.failed;
    }
    return _submitRealtime(task);
  }

  Future<void> resumeRealtimeCaptures() {
    _requireStarted();
    final active = _realtimeResumeInFlight;
    if (active != null) return active;
    final resume = _resumeRealtimeCaptures();
    _realtimeResumeInFlight = resume;
    resume.then<void>(
      (_) {
        if (identical(_realtimeResumeInFlight, resume)) {
          _realtimeResumeInFlight = null;
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_realtimeResumeInFlight, resume)) {
          _realtimeResumeInFlight = null;
        }
      },
    );
    return resume;
  }

  Future<void> _resumeRealtimeCaptures() async {
    final tasks = List<RingCaptureTask>.from(_tasks.values).where(
      (task) => (task.deviceCaptureKey ?? '').startsWith('ring-realtime:'),
    );
    for (var task in tasks) {
      if (task.stage == RingCaptureStage.done) continue;
      if (task.lastErrorCode == 'live_frame_gap' ||
          task.lastErrorCode == 'empty_device_audio') {
        continue;
      }
      if (!_hasDurableWav(task)) {
        await _fail(task, 'capture_interrupted');
        continue;
      }
      if ((task.transcript ?? '').trim().isEmpty) {
        task = await _transcribe(task);
        if (task.stage == RingCaptureStage.failed) continue;
      }
      await _submitRealtime(task);
    }
  }

  Future<RingRealtimeCaptureOutcome> _submitRealtime(
    RingCaptureTask task,
  ) async {
    final transcript = task.transcript?.trim() ?? '';
    final captureKey = task.deviceCaptureKey;
    final fileName = task.fileName;
    final audioSha = task.localAudioSha256;
    final audioSize = task.localAudioSizeBytes;
    if (transcript.isEmpty ||
        captureKey == null ||
        fileName == null ||
        audioSha == null ||
        audioSize == null) {
      await _fail(task, 'recovery_metadata_incomplete');
      return RingRealtimeCaptureOutcome.failed;
    }

    task = await _transition(task, RingCaptureStage.submitting);
    onActivity?.call(task, RingFileWorkflowPhase.submitting);
    late final FlashResult result;
    try {
      result = await _submit(
        transcript,
        task.id,
        FlashCaptureProvenance(
          deviceCaptureKey: captureKey,
          deviceKind: 'ring',
          deviceId: task.deviceId,
          deviceFileName: fileName,
          captureStartedAt: task.startedAt,
          captureEndedAt: task.endedAt,
          localAudioSha256: audioSha,
          localAudioSizeBytes: audioSize,
        ),
      );
    } on Object {
      await _fail(task, 'submit_failed');
      return RingRealtimeCaptureOutcome.failed;
    }
    if (!result.ok) {
      await _fail(task, 'backend_rejected');
      return RingRealtimeCaptureOutcome.failed;
    }

    final done = task.copyWith(
      stage: RingCaptureStage.done,
      updatedAt: _utcNow(),
      recordingId: result.recordingId,
      sessionId: result.physicalSessionId,
      inputTurnId: result.inputTurnId,
      localWavPath: null,
      deletePending: false,
      lastErrorCode: null,
    );
    await _deleteLocalWav(task.localWavPath);
    await _save(done);
    onActivity?.call(done, RingFileWorkflowPhase.done);
    return RingRealtimeCaptureOutcome.done;
  }

  Future<void> scanAndRecover() {
    _requireStarted();
    final active = _scanInFlight;
    if (active != null) return active;
    final scan = _scanAndRecover();
    _scanInFlight = scan;
    scan.then<void>(
      (_) {
        if (identical(_scanInFlight, scan)) _scanInFlight = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_scanInFlight, scan)) _scanInFlight = null;
      },
    );
    return scan;
  }

  Future<void> _scanAndRecover() async {
    final files = await _gateway.listFiles();
    final discoveredKeys = <String>{};
    for (final file in files) {
      discoveredKeys.add(_keyFor(file));
      await recover(file);
    }

    for (final task in List<RingCaptureTask>.from(_tasks.values)) {
      final key = task.deviceCaptureKey;
      if (!task.deletePending || key == null || discoveredKeys.contains(key)) {
        continue;
      }
      await _finishDeletedTask(task);
    }
  }

  Future<void> recover(RingFileRef file) {
    _requireStarted();
    final key = _keyFor(file);
    final active = _recoveries[key];
    if (active != null) return active;
    final recovery = _recover(file, key);
    _recoveries[key] = recovery;
    recovery.then<void>(
      (_) {
        if (identical(_recoveries[key], recovery)) _recoveries.remove(key);
      },
      onError: (Object _, StackTrace _) {
        if (identical(_recoveries[key], recovery)) _recoveries.remove(key);
      },
    );
    return recovery;
  }

  Future<void> _recover(RingFileRef file, String key) async {
    var task = _tasks.values.where((item) {
      return item.deviceCaptureKey == key;
    }).firstOrNull;
    if (task == null) {
      final now = _utcNow();
      task = RingCaptureTask(
        id: _taskIdForKey(key),
        userId: _userId!,
        deviceId: _deviceId!,
        stage: RingCaptureStage.fileAssociated,
        startedAt: now,
        updatedAt: now,
        fileName: file.name,
        fileId: file.id,
        deviceSizeBytes: file.sizeBytes,
        deviceCaptureKey: key,
      );
      await _save(task);
    }

    if (task.stage == RingCaptureStage.done) return;
    if (task.deletePending || task.stage == RingCaptureStage.accepted) {
      await _deleteAcceptedFile(task, file);
      return;
    }

    onActivity?.call(task, RingFileWorkflowPhase.receiving);
    if (!_hasDurableWav(task)) {
      task = await _download(task, file);
      if (task.stage == RingCaptureStage.failed) return;
    }
    if ((task.transcript ?? '').trim().isEmpty) {
      task = await _transcribe(task);
      if (task.stage == RingCaptureStage.failed) return;
    }
    await _submitAndDelete(task, file);
  }

  Future<RingCaptureTask> _download(
    RingCaptureTask task,
    RingFileRef file,
  ) async {
    task = await _transition(task, RingCaptureStage.downloading);
    late final List<int> pcm;
    try {
      pcm = await _gateway.download(file);
    } on Object {
      return _fail(task, 'file_download_failed');
    }
    if (pcm.isEmpty) return _fail(task, 'empty_device_audio');

    try {
      final outputFile = await _stableWavFile(task);
      task = await _transition(task, RingCaptureStage.downloaded);
      final wav = await _asr.writePcmWav(
        Uint8List.fromList(pcm),
        outputFile: outputFile,
        sampleRate: 8000,
        channels: 1,
      );
      final bytes = await wav.readAsBytes();
      final persisted = task.copyWith(
        stage: RingCaptureStage.downloaded,
        updatedAt: _utcNow(),
        localWavPath: wav.path,
        localAudioSha256: sha256.convert(bytes).toString(),
        localAudioSizeBytes: bytes.length,
        lastErrorCode: null,
      );
      await _save(persisted);
      return persisted;
    } on Object {
      return _fail(task, 'local_write_failed');
    }
  }

  Future<RingCaptureTask> _transcribe(RingCaptureTask task) async {
    final path = task.localWavPath;
    if (path == null || path.isEmpty) return _fail(task, 'local_audio_missing');
    task = await _transition(task, RingCaptureStage.transcribing);
    onActivity?.call(task, RingFileWorkflowPhase.transcribing);
    try {
      final file = File(path);
      if (!await file.exists()) return _fail(task, 'local_audio_missing');
      final transcript = (await _asr.transcribeWav(file)).trim();
      if (transcript.isEmpty) return _fail(task, 'empty_transcript');
      final persisted = task.copyWith(
        updatedAt: _utcNow(),
        transcript: transcript,
        lastErrorCode: null,
      );
      await _save(persisted);
      return persisted;
    } on Object {
      return _fail(task, 'asr_failed');
    }
  }

  Future<void> _submitAndDelete(RingCaptureTask task, RingFileRef file) async {
    final transcript = task.transcript?.trim() ?? '';
    final deviceCaptureKey = task.deviceCaptureKey;
    final sha = task.localAudioSha256;
    final size = task.localAudioSizeBytes;
    if (transcript.isEmpty ||
        deviceCaptureKey == null ||
        sha == null ||
        size == null) {
      await _fail(task, 'recovery_metadata_incomplete');
      return;
    }

    task = await _transition(task, RingCaptureStage.submitting);
    onActivity?.call(task, RingFileWorkflowPhase.submitting);
    late final FlashResult result;
    try {
      result = await _submit(
        transcript,
        task.id,
        FlashCaptureProvenance(
          deviceCaptureKey: deviceCaptureKey,
          deviceKind: 'ring',
          deviceId: task.deviceId,
          deviceFileName: task.fileName ?? file.name,
          captureStartedAt: task.startedAt,
          captureEndedAt: task.endedAt,
          localAudioSha256: sha,
          localAudioSizeBytes: size,
        ),
      );
    } on Object {
      await _fail(task, 'submit_failed');
      return;
    }
    if (!result.ok) {
      await _fail(task, 'backend_rejected');
      return;
    }

    final accepted = task.copyWith(
      stage: RingCaptureStage.accepted,
      updatedAt: _utcNow(),
      recordingId: result.recordingId,
      sessionId: result.physicalSessionId,
      inputTurnId: result.inputTurnId,
      deletePending: true,
      lastErrorCode: null,
    );
    await _save(accepted);
    await _deleteAcceptedFile(accepted, file);
  }

  Future<void> _deleteAcceptedFile(
    RingCaptureTask task,
    RingFileRef file,
  ) async {
    var deleted = false;
    try {
      deleted = await _gateway.delete(file);
    } on Object {
      deleted = false;
    }
    if (!deleted) {
      final pending = task.copyWith(
        stage: RingCaptureStage.accepted,
        updatedAt: _utcNow(),
        deletePending: true,
        lastErrorCode: 'device_delete_pending',
      );
      await _save(pending);
      return;
    }
    await _finishDeletedTask(task);
  }

  Future<void> _finishDeletedTask(RingCaptureTask task) async {
    await _deleteLocalWav(task.localWavPath);
    final done = task.copyWith(
      stage: RingCaptureStage.done,
      updatedAt: _utcNow(),
      localWavPath: null,
      deletePending: false,
      lastErrorCode: null,
    );
    await _save(done);
    onActivity?.call(done, RingFileWorkflowPhase.done);
  }

  Future<RingFileRef?> associateNewFile(
    String taskId,
    List<RingFileRef> baseline,
  ) async {
    _requireStarted();
    final task = _tasks[taskId];
    if (task == null) throw StateError('ring capture task not found');
    final before = baseline.map((file) => file.identityMaterial).toSet();
    final files = await _gateway.listFiles();
    final added = files
        .where((file) => !before.contains(file.identityMaterial))
        .toList();
    if (added.length == 1) {
      final file = added.single;
      final associated = task.copyWith(
        stage: RingCaptureStage.fileAssociated,
        updatedAt: _utcNow(),
        fileName: file.name,
        fileId: file.id,
        deviceSizeBytes: file.sizeBytes,
        deviceCaptureKey: _keyFor(file),
        lastErrorCode: null,
      );
      await _save(associated);
      await recover(file);
      return file;
    }
    if (added.isEmpty) {
      _scheduleAssociationRetry(taskId, baseline);
      return null;
    }
    for (final file in added) {
      await recover(file);
    }
    return null;
  }

  void _scheduleAssociationRetry(String taskId, List<RingFileRef> baseline) {
    if (associationRetryDelay <= Duration.zero) return;
    late final Timer timer;
    timer = Timer(associationRetryDelay, () {
      _associationTimers.remove(timer);
      if (!isStarted || !_tasks.containsKey(taskId)) return;
      _ignoreErrors(associateNewFile(taskId, baseline));
    });
    _associationTimers.add(timer);
  }

  Future<RingCaptureTask> _transition(
    RingCaptureTask task,
    RingCaptureStage stage,
  ) async {
    final updated = task.copyWith(
      stage: stage,
      updatedAt: _utcNow(),
      lastErrorCode: null,
    );
    await _save(updated);
    return updated;
  }

  Future<RingCaptureTask> _fail(RingCaptureTask task, String code) async {
    final failed = task.copyWith(
      stage: RingCaptureStage.failed,
      updatedAt: _utcNow(),
      lastErrorCode: code,
    );
    await _save(failed);
    onActivity?.call(failed, RingFileWorkflowPhase.failed);
    return failed;
  }

  Future<void> _save(RingCaptureTask task) async {
    _tasks[task.id] = task;
    await _store.upsert(_userId!, task);
  }

  bool _hasDurableWav(RingCaptureTask task) {
    return (task.localWavPath ?? '').isNotEmpty &&
        (task.localAudioSha256 ?? '').isNotEmpty &&
        (task.localAudioSizeBytes ?? 0) > 0;
  }

  String _keyFor(RingFileRef file) {
    return ringDeviceCaptureKey(
      deviceId: _deviceId!,
      fileName: file.name,
      fileId: file.id,
      sizeBytes: file.sizeBytes,
    );
  }

  String _taskIdForKey(String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return 'ring-file-$digest';
  }

  String _realtimeFileName(String captureKey) {
    final digest = captureKey.split(':').last;
    return 'LIVE-$digest.wav';
  }

  Future<File> _stableWavFile(RingCaptureTask task) async {
    final root = await _getSupportDirectory();
    final userDirectory = sha256
        .convert(utf8.encode(task.userId))
        .toString()
        .substring(0, 16);
    final taskName = sha256
        .convert(utf8.encode(task.id))
        .toString()
        .substring(0, 32);
    return File('${root.path}/ring-captures/$userDirectory/$taskName.wav');
  }

  Future<void> _deleteLocalWav(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Object {
      // Backend acceptance is the durable boundary. Local cleanup is best effort.
    }
  }

  DateTime _utcNow() => _now().toUtc();

  void _requireStarted() {
    if (!isStarted) throw StateError('ring file workflow has not started');
  }

  Future<void> stop() async {
    for (final timer in _associationTimers) {
      timer.cancel();
    }
    _associationTimers.clear();
    await _memoryFullSubscription?.cancel();
    _memoryFullSubscription = null;
    _scanInFlight = null;
    _realtimeResumeInFlight = null;
    _recoveries.clear();
    _tasks.clear();
    _userId = null;
    _deviceId = null;
  }

  void _ignoreErrors(Future<void> future) {
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
