import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:eureka/flash/flash.dart';
import 'package:eureka/ring/ring_asr.dart';
import 'package:eureka/ring/ring_capture_store.dart';
import 'package:eureka/ring/ring_capture_task.dart';
import 'package:eureka/ring/ring_file_gateway.dart';
import 'package:eureka/ring/ring_file_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'ring_file_workflow_test_',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('backend acceptance precedes ring file deletion', () async {
    final log = <String>[];
    final fixture = _workflow(
      supportDirectory: supportDirectory,
      onRecognize: (_) async {
        log.add('asr');
        return '喝了五百毫升水';
      },
      onSubmit: (_, _, provenance) async {
        log.add('accepted');
        expect(provenance.deviceFileName, 'R1.bin');
        return _acceptedFlash();
      },
      onDelete: (_) async {
        log.add('deleted');
        return true;
      },
    );
    await fixture.workflow.start('user-a', 'AA:BB');

    await fixture.workflow.recover(_file());

    expect(log, ['asr', 'accepted', 'deleted']);
    final task = (await fixture.store.load('user-a')).single;
    expect(task.stage, RingCaptureStage.done);
    expect(task.deletePending, isFalse);
    expect(task.recordingId, 'recording-1');
  });

  test(
    'network failure retains the device file and durable transcript',
    () async {
      final fixture = _workflow(
        supportDirectory: supportDirectory,
        onSubmit: (_, _, _) async => throw const SocketException('offline'),
      );
      await fixture.workflow.start('user-a', 'AA:BB');

      await fixture.workflow.recover(_file());

      expect(fixture.gateway.deleteCalls, isEmpty);
      final task = (await fixture.store.load('user-a')).single;
      expect(task.stage, RingCaptureStage.failed);
      expect(task.lastErrorCode, 'submit_failed');
      expect(task.transcript, '喝了五百毫升水');
      expect(task.localWavPath, isNotNull);
      expect(await File(task.localWavPath!).exists(), isTrue);
    },
  );

  test('ASR failure retains the file and never submits', () async {
    var submitCount = 0;
    final fixture = _workflow(
      supportDirectory: supportDirectory,
      onRecognize: (_) async => throw StateError('asr unavailable'),
      onSubmit: (_, _, _) async {
        submitCount += 1;
        return _acceptedFlash();
      },
    );
    await fixture.workflow.start('user-a', 'AA:BB');

    await fixture.workflow.recover(_file());

    expect(submitCount, 0);
    expect(fixture.gateway.deleteCalls, isEmpty);
    final task = (await fixture.store.load('user-a')).single;
    expect(task.lastErrorCode, 'asr_failed');
  });

  test(
    'deletePending retries deletion without repeating ASR or submit',
    () async {
      var recognizeCount = 0;
      var submitCount = 0;
      final fixture = _workflow(
        supportDirectory: supportDirectory,
        deleteResults: [false, true],
        onRecognize: (_) async {
          recognizeCount += 1;
          return '喝了五百毫升水';
        },
        onSubmit: (_, _, _) async {
          submitCount += 1;
          return _acceptedFlash();
        },
      );
      await fixture.workflow.start('user-a', 'AA:BB');

      await fixture.workflow.recover(_file());
      var task = (await fixture.store.load('user-a')).single;
      expect(task.stage, RingCaptureStage.accepted);
      expect(task.deletePending, isTrue);

      await fixture.workflow.scanAndRecover();

      task = (await fixture.store.load('user-a')).single;
      expect(task.stage, RingCaptureStage.done);
      expect(recognizeCount, 1);
      expect(submitCount, 1);
      expect(fixture.gateway.deleteCalls, hasLength(2));
    },
  );

  test('empty PCM fails locally and keeps the device file', () async {
    final fixture = _workflow(
      supportDirectory: supportDirectory,
      pcm: Uint8List(0),
    );
    await fixture.workflow.start('user-a', 'AA:BB');

    await fixture.workflow.recover(_file());

    final task = (await fixture.store.load('user-a')).single;
    expect(task.lastErrorCode, 'empty_device_audio');
    expect(fixture.gateway.deleteCalls, isEmpty);
  });

  test('memory-full signal triggers one serial recovery scan', () async {
    final phases = <RingFileWorkflowPhase>[];
    final fixture = _workflow(
      supportDirectory: supportDirectory,
      files: const [],
      onActivity: (_, phase) => phases.add(phase),
    );
    await fixture.workflow.start('user-a', 'AA:BB');

    fixture.gateway.emitMemoryFull();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(phases, contains(RingFileWorkflowPhase.memoryFull));
    expect(fixture.gateway.listCalls, 1);
  });

  test('duplicate scan callbacks process one hardware file once', () async {
    var submitCount = 0;
    final fixture = _workflow(
      supportDirectory: supportDirectory,
      onSubmit: (_, _, _) async {
        submitCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _acceptedFlash();
      },
    );
    await fixture.workflow.start('user-a', 'AA:BB');

    await Future.wait([
      fixture.workflow.scanAndRecover(),
      fixture.workflow.scanAndRecover(),
    ]);

    expect(submitCount, 1);
    expect(fixture.gateway.downloadCalls, hasLength(1));
    expect(fixture.gateway.deleteCalls, hasLength(1));
  });

  test(
    'realtime capture persists before audio and submits stable provenance',
    () async {
      FlashCaptureProvenance? submittedProvenance;
      final fixture = _workflow(
        supportDirectory: supportDirectory,
        files: const [],
        onSubmit: (_, clientTaskId, provenance) async {
          expect(clientTaskId, 'ring-live-1');
          submittedProvenance = provenance;
          return _acceptedFlash();
        },
      );
      await fixture.workflow.start('user-a', 'AA:BB');

      await fixture.workflow.beginRealtimeCapture(
        'ring-live-1',
        startedAt: DateTime.utc(2026, 8, 11, 0, 30),
      );
      var task = (await fixture.store.load('user-a')).single;
      expect(task.stage, RingCaptureStage.recording);
      expect(task.deviceCaptureKey, startsWith('ring-realtime:'));

      final outcome = await fixture.workflow.finishRealtimeCapture(
        'ring-live-1',
        Uint8List.fromList(List.filled(320, 1)),
        sampleRate: 8000,
        channels: 1,
        frameGapCount: 0,
        endedAt: DateTime.utc(2026, 8, 11, 0, 30, 10),
      );

      expect(outcome, RingRealtimeCaptureOutcome.done);
      expect(submittedProvenance, isNotNull);
      expect(submittedProvenance!.deviceId, 'AA:BB');
      expect(
        submittedProvenance!.captureStartedAt,
        DateTime.utc(2026, 8, 11, 0, 30),
      );
      expect(
        submittedProvenance!.captureEndedAt,
        DateTime.utc(2026, 8, 11, 0, 30, 10),
      );
      expect(fixture.gateway.downloadCalls, isEmpty);
      expect(fixture.gateway.deleteCalls, isEmpty);
      task = (await fixture.store.load('user-a')).single;
      expect(task.stage, RingCaptureStage.done);
      expect(task.localWavPath, isNull);
    },
  );

  test('realtime network failure resumes without repeating ASR', () async {
    final store = _MemoryRingCaptureStore();
    var recognizeCount = 0;
    var submitCount = 0;
    final first = _workflow(
      supportDirectory: supportDirectory,
      files: const [],
      store: store,
      onRecognize: (_) async {
        recognizeCount += 1;
        return '需要稍后续传';
      },
      onSubmit: (_, _, _) async {
        submitCount += 1;
        throw const SocketException('offline');
      },
    );
    await first.workflow.start('user-a', 'AA:BB');
    await first.workflow.beginRealtimeCapture('ring-live-retry');
    expect(
      await first.workflow.finishRealtimeCapture(
        'ring-live-retry',
        Uint8List.fromList(List.filled(320, 1)),
        sampleRate: 8000,
        channels: 1,
        frameGapCount: 0,
      ),
      RingRealtimeCaptureOutcome.failed,
    );
    await first.workflow.stop();

    final second = _workflow(
      supportDirectory: supportDirectory,
      files: const [],
      store: store,
      onRecognize: (_) async {
        recognizeCount += 1;
        return '不应再次转写';
      },
      onSubmit: (_, _, _) async {
        submitCount += 1;
        return _acceptedFlash();
      },
    );
    await second.workflow.start('user-a', 'AA:BB');
    await second.workflow.resumeRealtimeCaptures();

    expect(recognizeCount, 1);
    expect(submitCount, 2);
    expect((await store.load('user-a')).single.stage, RingCaptureStage.done);
  });

  test(
    'known realtime frame gap is retained as an explicit failed turn',
    () async {
      var recognizeCount = 0;
      var submitCount = 0;
      final fixture = _workflow(
        supportDirectory: supportDirectory,
        files: const [],
        onRecognize: (_) async {
          recognizeCount += 1;
          return '不完整音频';
        },
        onSubmit: (_, _, _) async {
          submitCount += 1;
          return _acceptedFlash();
        },
      );
      await fixture.workflow.start('user-a', 'AA:BB');
      await fixture.workflow.beginRealtimeCapture('ring-live-gap');

      final outcome = await fixture.workflow.finishRealtimeCapture(
        'ring-live-gap',
        Uint8List.fromList(List.filled(320, 1)),
        sampleRate: 8000,
        channels: 1,
        frameGapCount: 1,
      );

      expect(outcome, RingRealtimeCaptureOutcome.failed);
      expect(recognizeCount, 0);
      expect(submitCount, 0);
      final task = (await fixture.store.load('user-a')).single;
      expect(task.lastErrorCode, 'live_frame_gap');
    },
  );
}

_WorkflowFixture _workflow({
  required Directory supportDirectory,
  List<RingFileRef>? files,
  Uint8List? pcm,
  List<bool>? deleteResults,
  _MemoryRingCaptureStore? store,
  Future<String> Function(File file)? onRecognize,
  SubmitRecoveredFlash? onSubmit,
  Future<bool> Function(RingFileRef file)? onDelete,
  RingFileWorkflowActivityCallback? onActivity,
}) {
  final gateway = _FakeRingFileAccess(
    files: files ?? [_file()],
    pcm: pcm ?? Uint8List.fromList(List.filled(320, 1)),
    deleteResults: deleteResults,
    onDelete: onDelete,
  );
  final resolvedStore = store ?? _MemoryRingCaptureStore();
  final asr = RingAsr(
    recognize:
        onRecognize ??
        (_) async {
          return '喝了五百毫升水';
        },
  );
  final workflow = RingFileWorkflow(
    gateway: gateway,
    store: resolvedStore,
    asr: asr,
    submit:
        onSubmit ??
        (_, _, _) async {
          return _acceptedFlash();
        },
    getSupportDirectory: () async => supportDirectory,
    now: () => DateTime.utc(2026, 8, 11, 0, 30),
    onActivity: onActivity,
  );
  return _WorkflowFixture(workflow, gateway, resolvedStore);
}

RingFileRef _file() {
  return const RingFileRef(name: 'R1.bin', id: [1, 2, 3], sizeBytes: 240000);
}

FlashResult _acceptedFlash() {
  return FlashResult(
    ok: true,
    sessionId: 'recording-1',
    recordingId: 'recording-1',
    physicalSessionId: 'session-1',
    inputTurnId: 'turn-1',
    reply: '',
    summary: '',
    cards: const [],
    error: '',
    hasPending: true,
  );
}

class _WorkflowFixture {
  _WorkflowFixture(this.workflow, this.gateway, this.store);

  final RingFileWorkflow workflow;
  final _FakeRingFileAccess gateway;
  final _MemoryRingCaptureStore store;
}

class _FakeRingFileAccess implements RingFileAccess {
  _FakeRingFileAccess({
    required this.files,
    required this.pcm,
    List<bool>? deleteResults,
    this.onDelete,
  }) : deleteResults = List<bool>.from(deleteResults ?? const [true]);

  final List<RingFileRef> files;
  final Uint8List pcm;
  final List<bool> deleteResults;
  final Future<bool> Function(RingFileRef file)? onDelete;
  final _memoryFull = StreamController<void>.broadcast();
  final List<RingFileRef> downloadCalls = [];
  final List<RingFileRef> deleteCalls = [];
  int listCalls = 0;

  void emitMemoryFull() => _memoryFull.add(null);

  @override
  Stream<void> get memoryFullEvents => _memoryFull.stream;

  @override
  Future<bool> delete(RingFileRef file) async {
    deleteCalls.add(file);
    final callback = onDelete;
    if (callback != null) return callback(file);
    if (deleteResults.isEmpty) return true;
    return deleteResults.removeAt(0);
  }

  @override
  Future<Uint8List> download(RingFileRef file) async {
    downloadCalls.add(file);
    return pcm;
  }

  @override
  Future<List<RingFileRef>> listFiles() async {
    listCalls += 1;
    return List<RingFileRef>.from(files);
  }
}

class _MemoryRingCaptureStore implements RingCaptureStore {
  final _tasks = <String, Map<String, RingCaptureTask>>{};

  @override
  Future<List<RingCaptureTask>> load(String userId) async {
    return List<RingCaptureTask>.from(_tasks[userId]?.values ?? const []);
  }

  @override
  Future<void> remove(String userId, String taskId) async {
    _tasks[userId]?.remove(taskId);
  }

  @override
  Future<void> upsert(String userId, RingCaptureTask task) async {
    (_tasks[userId] ??= {})[task.id] = task;
  }
}
