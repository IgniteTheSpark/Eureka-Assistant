import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:br_flutter_plugin_ble/br_audio_converter_plugin.dart';
import 'package:br_flutter_plugin_ble/br_bluetooth_plugin.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/eureka_flash_file_api.dart';
import '../api/tencent_asr_s3_client.dart';
import 'flash_file_status_controller.dart';
import 'flash_file_task.dart';

class FlashFileWorkflow {
  FlashFileWorkflow._({
    BrBluetoothPlugin? ble,
    BrAudioConverterPlugin? converter,
    TencentAsrS3Client? asrClient,
    EurekaFlashFileApi? eurekaApi,
  }) : _ble = ble ?? BrBluetoothPlugin.instance,
       _converter = converter ?? BrAudioConverterPlugin(),
       _asrClient = asrClient ?? TencentAsrS3Client(),
       _eurekaApi = eurekaApi ?? EurekaFlashFileApi();

  static final FlashFileWorkflow instance = FlashFileWorkflow._();

  static const _logTag = '[FlashFile]';
  static const _prefsKey = 'flash_file_tasks_v1';
  final BrBluetoothPlugin _ble;
  final BrAudioConverterPlugin _converter;
  final TencentAsrS3Client _asrClient;
  final EurekaFlashFileApi _eurekaApi;
  final Map<String, FlashFileTask> _tasks = {};
  final ValueNotifier<int> taskRevision = ValueNotifier<int>(0);

  bool _loaded = false;
  bool _started = false;
  bool _syncRunning = false;
  bool _transcodeRunning = false;
  bool _uploadRunning = false;
  bool _notifyRunning = false;
  bool _deviceConnected = false;
  Set<String> _syncableFlashFiles = const {};
  Timer? _wakeTimer;

  void _log(String message) => debugPrint('$_logTag $message');

  String _brief(FlashFileTask task) =>
      'key=${task.key} stage=${task.stage.name} source=${task.source.name} '
      'asrTask=${task.tencentAsrTaskId ?? "-"} recording=${task.eurekaRecordingId ?? "-"}';

  Future<void> start() async {
    _log('workflow start requested');
    _started = true;
    await _load();
    _log('workflow loaded tasks count=${_tasks.length}');
    await scanOfflineIfConnected();
    _kick();
  }

  Future<void> scanOfflineIfConnected() async {
    if (!_started) {
      _log('skip offline scan: workflow not started');
      return;
    }
    try {
      _deviceConnected = await _ble.isConnected() == true;
      if (_deviceConnected) {
        _log('device connected; start offline scan');
        await scanOffline();
      } else {
        _log('skip offline scan: device not connected');
        FlashFileStatusController.instance.clear();
      }
    } catch (e) {
      _deviceConnected = false;
      _log('offline scan connection check failed error=$e');
    }
  }

  Future<void> handleConnectionChanged(bool connected) async {
    _deviceConnected = connected;
    _log('device connection changed connected=$connected');
    if (!connected) {
      FlashFileStatusController.instance.clear();
      return;
    }
    await scanOffline();
  }

  Future<void> upsertRealtime({
    required String fileName,
    int? createTime,
    int? endTime,
    int? crc,
    int? deviceSizeBytes,
  }) async {
    if (!isFlashFileName(fileName)) {
      _log('ignore realtime file: not flash file fileName=$fileName');
      return;
    }
    await _load();
    final sn = await _deviceSn();
    final key = '$sn:$fileName';
    final existing = _tasks[key];
    _tasks[key] = (existing ?? _newTask(sn, fileName, FlashFileSource.realtime))
        .copyWith(
          stage: existing?.stage ?? FlashFileStage.queued,
          createTime: createTime,
          endTime: endTime,
          crc: crc,
          deviceSizeBytes: deviceSizeBytes,
        );
    await _save();
    _notifyTasksChanged();
    _log(
      'realtime task upserted key=$key existing=${existing != null} '
      'createTime=$createTime endTime=$endTime crc=$crc size=$deviceSizeBytes',
    );
    FlashFileStatusController.instance.heard(fileName);
    if (_started) {
      unawaited(scanOfflineIfConnected());
    }
  }

  Future<void> scanOffline() async {
    if (!_started) {
      _log('skip offline scan: workflow not started');
      return;
    }
    await _load();
    final sn = await _deviceSn();
    _log('offline scan start sn=$sn');
    final res = await _withBleSyncMode(() => _ble.getFileList());
    final names = _extractFileNames(res);
    final flashNames = names.where(isFlashFileName).toList();
    _syncableFlashFiles = flashNames.toSet();
    _log(
      'offline scan file list total=${names.length} flashCount=${flashNames.length}',
    );
    var added = 0;
    var deleteRetry = 0;
    for (final name in flashNames) {
      final key = '$sn:$name';
      final existing = _tasks[key];
      if (existing == null) {
        _tasks[key] = _newTask(sn, name, FlashFileSource.offline);
        added += 1;
        _log('offline task discovered key=$key');
      } else if (existing.stage == FlashFileStage.failed &&
          !_isServerSubmitted(existing)) {
        _tasks[key] = _resetForRetransfer(existing);
        added += 1;
        _log('offline scan requeued failed task key=$key');
      } else if (existing.deviceDeletePending &&
          (existing.stage == FlashFileStage.waitingServer ||
              existing.stage == FlashFileStage.done)) {
        _tasks[key] = existing.copyWith(
          stage: FlashFileStage.deletingDeviceFile,
        );
        deleteRetry += 1;
        _log(
          'offline scan scheduled pending device delete ${_brief(existing)}',
        );
      }
    }
    _log(
      'offline scan done flashCount=${flashNames.length} added=$added deleteRetry=$deleteRetry',
    );
    await _save();
    if (flashNames.isEmpty && deleteRetry == 0) {
      FlashFileStatusController.instance.clear();
    }
    _kick();
  }

  void applyServerStatus(Map<String, dynamic> payload) {
    final taskId = payload['client_task_id']?.toString();
    final status = payload['status']?.toString();
    if (taskId == null || taskId.isEmpty || status == null) {
      _log('ignore server status: missing task/status payload=$payload');
      return;
    }
    _log('server status received clientTask=$taskId status=$status');
    for (final entry in _tasks.entries) {
      final task = entry.value;
      if (task.id != taskId) continue;
      if ((status == 'asr_done' ||
              status == 'processing_flash' ||
              status == 'done') &&
          task.stage == FlashFileStage.waitingServerAsr) {
        _tasks[entry.key] = task.copyWith(
          stage: FlashFileStage.deletingDeviceFile,
        );
        _save();
        _notifyTasksChanged();
        _log(
          'server status moves task to delete ${_brief(task)} status=$status',
        );
        _kick();
      } else if (status == 'done' &&
          task.stage != FlashFileStage.deletingDeviceFile) {
        _tasks[entry.key] = task.copyWith(stage: FlashFileStage.done);
        _save();
        _notifyTasksChanged();
        _log('server status marks done ${_brief(task)}');
      } else if (status == 'failed') {
        if (task.stage == FlashFileStage.deletingDeviceFile) {
          _log(
            'server failed while device delete is pending; keep delete stage ${_brief(task)}',
          );
          return;
        }
        _tasks[entry.key] = task.copyWith(
          stage: FlashFileStage.failed,
          lastError: payload['message']?.toString(),
        );
        _save();
        _notifyTasksChanged();
        _log(
          'server status marks failed ${_brief(task)} message=${payload['message']}',
        );
      }
      return;
    }
    _log('server status unmatched clientTask=$taskId status=$status');
  }

  FlashFileTask _newTask(String sn, String fileName, FlashFileSource source) {
    final id = sha1.convert(utf8.encode('$sn:$fileName')).toString();
    return FlashFileTask(
      id: id,
      key: '$sn:$fileName',
      deviceSn: sn,
      fileName: fileName,
      source: source,
      stage: FlashFileStage.queued,
      updatedAt: DateTime.now(),
    );
  }

  FlashFileTask? realtimeTaskForFile(String fileName) {
    if (fileName.trim().isEmpty) return null;
    final matches = _tasks.values.where(
      (t) => t.source == FlashFileSource.realtime && t.fileName == fileName,
    );
    if (matches.isEmpty) return null;
    return matches.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b);
  }

  FlashFileTask? latestRealtimeTask() {
    final matches = _tasks.values.where(
      (t) => t.source == FlashFileSource.realtime,
    );
    if (matches.isEmpty) return null;
    return matches.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b);
  }

  void _kick() {
    if (!_started) return;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _kickStageWorker(
      isRunning: () => _syncRunning,
      setRunning: (v) => _syncRunning = v,
      nextTask: _nextSyncTask,
      runTask: _runSyncTask,
    );
    _kickStageWorker(
      isRunning: () => _transcodeRunning,
      setRunning: (v) => _transcodeRunning = v,
      nextTask: () => _nextStageTask({FlashFileStage.syncedToPhone}),
      runTask: _transcode,
    );
    _kickStageWorker(
      isRunning: () => _uploadRunning,
      setRunning: (v) => _uploadRunning = v,
      nextTask: () => _nextStageTask({FlashFileStage.converted}),
      runTask: _upload,
    );
    _kickStageWorker(
      isRunning: () => _notifyRunning,
      setRunning: (v) => _notifyRunning = v,
      nextTask: () => _nextStageTask({FlashFileStage.s3Uploaded}),
      runTask: _notifyEureka,
    );
  }

  void _kickStageWorker({
    required bool Function() isRunning,
    required void Function(bool) setRunning,
    required FlashFileTask? Function() nextTask,
    required Future<void> Function(FlashFileTask) runTask,
  }) {
    if (isRunning()) return;
    setRunning(true);
    Future<void>(() async {
      try {
        while (true) {
          final task = nextTask();
          if (task == null) break;
          _log('worker picked ${_brief(task)}');
          try {
            await runTask(task);
          } catch (e) {
            _log('worker task error ${_brief(task)} error=$e');
            await _retryOrFail(task, e);
          }
        }
      } finally {
        setRunning(false);
        _scheduleNextWake();
      }
    });
  }

  void _scheduleNextWake() {
    if (_syncRunning || _transcodeRunning || _uploadRunning || _notifyRunning) {
      return;
    }
    final now = DateTime.now();
    Duration? nextDelay;
    for (final task in _tasks.values) {
      final retryAfter = task.retryAfter;
      if (retryAfter == null) continue;
      final delay = retryAfter.isAfter(now)
          ? retryAfter.difference(now)
          : Duration.zero;
      if (nextDelay == null || delay < nextDelay) {
        nextDelay = delay;
      }
    }
    if (nextDelay == null) return;
    final delay = nextDelay < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : nextDelay;
    _wakeTimer = Timer(delay, _kick);
    _log('scheduled next workflow wake delay=${delay.inSeconds}s');
  }

  FlashFileTask? _nextSyncTask() {
    if (!_deviceConnected) return null;
    return _firstOrNull(
      _sortedTasks(
        _tasks.values.where(
          (t) =>
              _isRetryDue(t) &&
              _syncableFlashFiles.contains(t.fileName) &&
              (t.stage == FlashFileStage.deletingDeviceFile ||
                  t.stage == FlashFileStage.queued),
        ),
      ),
    );
  }

  FlashFileTask? _nextStageTask(Set<FlashFileStage> stages) {
    return _firstOrNull(
      _sortedTasks(
        _tasks.values.where((t) => _isRetryDue(t) && stages.contains(t.stage)),
      ),
    );
  }

  List<FlashFileTask> _sortedTasks(Iterable<FlashFileTask> tasks) {
    return tasks.toList()..sort((a, b) {
      final stage = _stagePriority(a.stage) - _stagePriority(b.stage);
      if (stage != 0) return stage;
      final source =
          (a.source == FlashFileSource.realtime ? 0 : 10) -
          (b.source == FlashFileSource.realtime ? 0 : 10);
      if (source != 0) return source;
      return a.updatedAt.compareTo(b.updatedAt);
    });
  }

  int _stagePriority(FlashFileStage stage) {
    return switch (stage) {
      FlashFileStage.deletingDeviceFile => 0,
      _ => 10,
    };
  }

  FlashFileTask? _firstOrNull(List<FlashFileTask> tasks) {
    return tasks.isEmpty ? null : tasks.first;
  }

  bool _isRetryDue(FlashFileTask task) {
    final retryAfter = task.retryAfter;
    return retryAfter == null || !retryAfter.isAfter(DateTime.now());
  }

  Future<void> _retryOrFail(FlashFileTask task, Object error) async {
    if (_isPermanentFailure(task, error)) {
      _log('permanent failure ${_brief(task)} error=$error');
      await _markFailed(task, error);
      return;
    }
    final latest = _tasks[task.key] ?? task;
    await _update(
      task.key,
      latest.copyWith(stage: FlashFileStage.failed, lastError: '$error'),
    );
    _log('task stopped for refresh ${_brief(latest)} error=$error');
    FlashFileStatusController.instance.failed(
      task.fileName,
      message: '同步失败，请刷新',
    );
  }

  bool _isPermanentFailure(FlashFileTask task, Object error) {
    if (error is ApiException && error.statusCode == 422) return true;
    return false;
  }

  Future<void> _markFailed(FlashFileTask task, Object error) async {
    await _update(
      task.key,
      task.copyWith(stage: FlashFileStage.failed, lastError: '$error'),
    );
    _log('task failed ${_brief(task)} error=$error');
    FlashFileStatusController.instance.failed(task.fileName);
  }

  Future<void> _runSyncTask(FlashFileTask task) async {
    if (task.stage == FlashFileStage.deletingDeviceFile) {
      await _deleteDeviceFile(task);
      return;
    }
    await _sync(task);
  }

  Future<void> _sync(FlashFileTask task) async {
    _log('sync start ${_brief(task)}');
    FlashFileStatusController.instance.syncing(task.fileName);
    await _update(
      task.key,
      task.copyWith(stage: FlashFileStage.syncingFromCard),
    );
    final dir = await _ble.getDefaultStorageDirectory();
    final localPath = _resolveLocalPath(
      const <String, dynamic>{},
      dir,
      task.fileName,
    );
    _log('sync storage dir=$dir file=${task.fileName}');
    if (_localOpusReady(localPath)) {
      _log(
        'local opus already ready ${_brief(task)} path=$localPath bytes=${File(localPath).lengthSync()}',
      );
      await _update(
        task.key,
        task.copyWith(
          stage: FlashFileStage.syncedToPhone,
          localOpusPath: localPath,
        ),
      );
      return;
    }
    final result = await _withBleSyncMode(() async {
      try {
        return await _ble.syncAudioFile(
          fileName: task.fileName,
          directory: dir,
        );
      } on PlatformException catch (e) {
        if (!_isAlreadySyncedError(e)) rethrow;
        if (_localOpusReady(localPath)) {
          _log(
            'ble reported already synced; reuse local file file=${task.fileName} path=$localPath bytes=${File(localPath).lengthSync()}',
          );
          return <String, dynamic>{'filePath': localPath};
        }
        _log(
          'ble reported already synced but local file missing; clear local sync artifacts and retry file=${task.fileName} path=$localPath',
        );
        await _clearLocalSyncArtifacts(localPath);
        return _ble.syncAudioFile(fileName: task.fileName, directory: dir);
      }
    });
    final map = result is Map
        ? result.cast<String, dynamic>()
        : <String, dynamic>{};
    final path = _resolveLocalPath(map, dir, task.fileName);
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() <= 0) {
      throw StateError('synced file missing');
    }
    _log('sync success ${_brief(task)} path=$path bytes=${file.lengthSync()}');
    await _update(
      task.key,
      task.copyWith(stage: FlashFileStage.syncedToPhone, localOpusPath: path),
    );
  }

  Future<void> _transcode(FlashFileTask task) async {
    final opusPath = task.localOpusPath;
    if (opusPath == null) throw StateError('opus path missing');
    _log('transcode start ${_brief(task)} opus=$opusPath');
    FlashFileStatusController.instance.transcoding(task.fileName);
    await _update(
      task.key,
      task.copyWith(stage: FlashFileStage.convertingToMp3),
    );
    final input = await _stripMarkIfNeeded(opusPath);
    final mp3Path = opusPath.replaceFirst(
      RegExp(r'\.opus$', caseSensitive: false),
      '.mp3',
    );
    final ok = await _converter.convertOpusToMp3(
      inputPath: input,
      outputPath: mp3Path,
      meetingId: task.id,
    );
    if (ok != true || !File(mp3Path).existsSync()) {
      throw StateError('opus to mp3 failed');
    }
    final mp3 = File(mp3Path);
    final bytes = await mp3.readAsBytes();
    await _update(
      task.key,
      task.copyWith(
        stage: FlashFileStage.converted,
        localMp3Path: mp3Path,
        mp3Sha256: sha256.convert(bytes).toString(),
        mp3SizeBytes: bytes.length,
      ),
    );
    _log(
      'transcode success ${_brief(task)} mp3=$mp3Path bytes=${bytes.length}',
    );
  }

  Future<void> _upload(FlashFileTask task) async {
    final mp3Path = task.localMp3Path;
    if (mp3Path == null) throw StateError('mp3 path missing');
    _log('upload start ${_brief(task)} mp3=$mp3Path');
    FlashFileStatusController.instance.uploading(task.fileName);
    await _update(
      task.key,
      task.copyWith(stage: FlashFileStage.requestingS3Presign),
    );
    final mp3Name = task.fileName.replaceFirst(
      RegExp(r'\.opus$', caseSensitive: false),
      '.mp3',
    );
    final presign = await _asrClient.createPresign(filename: mp3Name);
    if (presign.s3Key.isEmpty ||
        presign.uploadUrl.isEmpty ||
        presign.audioUrl.isEmpty) {
      throw StateError('invalid S3 presign');
    }
    _log(
      'presign received ${_brief(task)} s3Key=${presign.s3Key} expires=${presign.expiresIn}',
    );
    await _update(
      task.key,
      task.copyWith(
        stage: FlashFileStage.uploadingToS3,
        s3Key: presign.s3Key,
        s3UploadUrl: presign.uploadUrl,
        s3AudioUrl: presign.audioUrl,
        s3UploadHeaders: presign.headers,
        s3ExpiresIn: presign.expiresIn,
      ),
    );
    await _asrClient.uploadMp3(
      uploadUrl: presign.uploadUrl,
      headers: presign.headers,
      file: File(mp3Path),
    );
    _log('upload success ${_brief(task)} s3Key=${presign.s3Key}');
    await _update(
      task.key,
      _tasks[task.key]!.copyWith(stage: FlashFileStage.s3Uploaded),
    );
  }

  Future<void> _notifyEureka(FlashFileTask task) async {
    final latest = _tasks[task.key] ?? task;
    _log('notify Eureka start ${_brief(latest)} s3Key=${latest.s3Key}');
    FlashFileStatusController.instance.submitting(latest.fileName);
    await _update(
      task.key,
      latest.copyWith(stage: FlashFileStage.notifyingEureka),
    );
    final res = await _eurekaApi.notifyTencentAsrS3Upload(_payload(latest));
    _log('notify Eureka success ${_brief(latest)} response=$res');
    await _deleteLocalFlashFiles(latest);
    await _update(
      task.key,
      latest.copyWith(
        stage: FlashFileStage.deletingDeviceFile,
        eurekaRecordingId: res['recording_id']?.toString(),
      ),
    );
  }

  Future<void> _deleteDeviceFile(FlashFileTask task) async {
    _log('delete device file start ${_brief(task)}');
    FlashFileStatusController.instance.cleaning(task.fileName);
    final ok = await _ble.deleteFile(fileName: task.fileName);
    _log('delete device file result ${_brief(task)} ok=$ok');
    await _update(
      task.key,
      task.copyWith(
        stage: ok == true ? FlashFileStage.done : FlashFileStage.done,
        deviceDeletePending: ok != true,
      ),
    );
    FlashFileStatusController.instance.clear();
  }

  Map<String, dynamic> _payload(FlashFileTask task) => {
    'client_task_id': task.id,
    'source': task.source.name,
    'card_sn': task.deviceSn,
    'device_file_name': task.fileName,
    'capture_started_at': task.createTime,
    'capture_ended_at': task.endTime,
    'device_crc': task.crc,
    'device_size_bytes': task.deviceSizeBytes,
    'local_mp3_sha256': task.mp3Sha256,
    'local_mp3_size_bytes': task.mp3SizeBytes,
    's3': {
      's3_key': task.s3Key,
      'upload_url': task.s3UploadUrl,
      'audio_url': task.s3AudioUrl,
      'content_type': task.s3UploadHeaders?['Content-Type'] ?? 'audio/mpeg',
      'headers': task.s3UploadHeaders ?? const {'Content-Type': 'audio/mpeg'},
      'upload_expires_in': task.s3ExpiresIn,
      'uploaded_at': DateTime.now().toIso8601String(),
    },
    'engine_type': '16k_zh',
    'speaker_diarization': false,
    'hotword_list': '',
  };

  Future<String> _deviceSn() async {
    final info = await _ble.getConnectedDeviceInfo();
    return (info?['SN'] ??
            info?['sn'] ??
            info?['device_sn'] ??
            info?['serial'] ??
            'unknown')
        .toString();
  }

  Future<T> _withBleSyncMode<T>(Future<T> Function() run) async {
    await _ble.openBLESync();
    _log('ble sync opened');
    try {
      return await run();
    } finally {
      try {
        await _ble.closeBLESync();
        _log('ble sync closed');
      } catch (e) {
        _log('ble sync close ignored error=$e');
      }
    }
  }

  String _resolveLocalPath(
    Map<String, dynamic> result,
    String? dir,
    String fileName,
  ) {
    final p = (result['filePath'] ?? result['path'])?.toString();
    if (p != null && p.isNotEmpty) {
      if (p.toLowerCase().endsWith('.opus')) return p;
      return _joinPath(p, fileName);
    }
    return _joinPath(dir ?? '', fileName);
  }

  String _joinPath(String dir, String fileName) {
    final d = dir.trim();
    if (d.isEmpty) {
      throw StateError('default storage dir missing');
    }
    if (d.endsWith('/')) return '$d$fileName';
    return '$d/$fileName';
  }

  bool _localOpusReady(String path) {
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 0;
  }

  bool _isAlreadySyncedError(Object error) {
    if (error is! PlatformException) return false;
    return error.code == '-2' ||
        error.code == '1017' ||
        error.message == '-2' ||
        error.message == '1017';
  }

  Future<void> _clearLocalSyncArtifacts(String opusPath) async {
    for (final path in ['$opusPath.sync', '$opusPath.temp']) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        await file.delete();
        _log('local sync artifact deleted path=$path');
      } catch (e) {
        _log('local sync artifact delete failed path=$path error=$e');
      }
    }
  }

  Future<void> _deleteLocalFlashFiles(FlashFileTask task) async {
    final paths = <String>{
      if (task.localOpusPath?.isNotEmpty == true) task.localOpusPath!,
      if (task.localOpusPath?.isNotEmpty == true)
        '${task.localOpusPath}.raw.opus',
      if (task.localOpusPath?.isNotEmpty == true) '${task.localOpusPath}.sync',
      if (task.localOpusPath?.isNotEmpty == true) '${task.localOpusPath}.temp',
      if (task.localMp3Path?.isNotEmpty == true) task.localMp3Path!,
    };
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        await file.delete();
        _log('local flash file deleted path=$path');
      } catch (e) {
        _log('local flash file delete failed path=$path error=$e');
      }
    }
  }

  Future<String> _stripMarkIfNeeded(String path) async {
    final file = File(path);
    final bytes = await file
        .openRead(0, 4)
        .fold<List<int>>([], (a, b) => [...a, ...b]);
    if (bytes.length < 4 ||
        utf8.decode(bytes, allowMalformed: true) != 'MARK') {
      return path;
    }
    final raw = '$path.raw.opus';
    final all = await file.readAsBytes();
    await File(raw).writeAsBytes(all.sublist(4), flush: true);
    _log('MARK header stripped input=$path output=$raw bytes=${all.length}');
    return raw;
  }

  List<String> _extractFileNames(Object? value) {
    final out = <String>{};
    void walk(Object? v) {
      if (v is Map) {
        for (final entry in v.entries) {
          if (entry.key.toString().toLowerCase().contains('name') ||
              entry.key.toString().toLowerCase().contains('file')) {
            final s = entry.value?.toString() ?? '';
            if (s.isNotEmpty) out.add(s);
          }
          walk(entry.value);
        }
      } else if (v is Iterable) {
        for (final item in v) {
          walk(item);
        }
      } else if (v is String && v.isNotEmpty) {
        out.add(v);
      }
    }

    walk(value);
    return out.toList();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _log('load persisted tasks: empty');
      return;
    }
    final list = jsonDecode(raw);
    if (list is! List) {
      _log('load persisted tasks ignored: value is not list');
      return;
    }
    for (final item in list) {
      if (item is Map) {
        final task = _recoverLoadedTask(
          FlashFileTask.fromJson(item.cast<String, dynamic>()),
        );
        _tasks[task.key] = task;
        if (_isServerSubmitted(task)) {
          unawaited(_deleteLocalFlashFiles(task));
        }
      }
    }
    _log('load persisted tasks count=${_tasks.length}');
  }

  FlashFileTask _recoverLoadedTask(FlashFileTask task) {
    if (_isServerSubmitted(task)) {
      return switch (task.stage) {
        FlashFileStage.notifyingEureka || FlashFileStage.eurekaAccepted =>
          task.copyWith(stage: FlashFileStage.s3Uploaded),
        FlashFileStage.waitingServer || FlashFileStage.waitingServerAsr =>
          task.copyWith(stage: FlashFileStage.done),
        _ => task,
      };
    }
    if (task.stage != FlashFileStage.done &&
        task.stage != FlashFileStage.failed) {
      return _resetForRetransfer(task);
    }
    return task;
  }

  bool _isServerSubmitted(FlashFileTask task) {
    return (task.tencentAsrTaskId?.isNotEmpty == true) ||
        (task.eurekaRecordingId?.isNotEmpty == true);
  }

  FlashFileTask _resetForRetransfer(FlashFileTask task) {
    _log('recover task for retransmit ${_brief(task)}');
    return FlashFileTask(
      id: task.id,
      key: task.key,
      deviceSn: task.deviceSn,
      fileName: task.fileName,
      source: task.source,
      stage: FlashFileStage.queued,
      updatedAt: DateTime.now(),
      createTime: task.createTime,
      endTime: task.endTime,
      crc: task.crc,
      deviceSizeBytes: task.deviceSizeBytes,
    );
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _prefsKey,
      jsonEncode(_tasks.values.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> _update(String key, FlashFileTask task) async {
    final old = _tasks[key];
    _tasks[key] = task;
    await _save();
    if (old?.stage != task.stage) {
      _log(
        'stage changed key=$key ${old?.stage.name ?? "-"} -> ${task.stage.name}',
      );
    } else {
      _log('task updated ${_brief(task)}');
    }
    if (_started) _kick();
    _notifyTasksChanged();
  }

  void _notifyTasksChanged() {
    taskRevision.value++;
  }
}
