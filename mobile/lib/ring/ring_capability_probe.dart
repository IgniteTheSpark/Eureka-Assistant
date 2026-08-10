import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/foundation.dart';

enum RingConnectedCaptureMode {
  dualPath,
  localFirst,
  realtimeOnly,
  unsupported,
}

RingConnectedCaptureMode _captureMode({
  required bool livePcmValid,
  required bool localFileValid,
}) => switch ((livePcmValid, localFileValid)) {
  (true, true) => RingConnectedCaptureMode.dualPath,
  (false, true) => RingConnectedCaptureMode.localFirst,
  (true, false) => RingConnectedCaptureMode.realtimeOnly,
  (false, false) => RingConnectedCaptureMode.unsupported,
};

abstract interface class RingCapabilityGateway {
  Stream<RingAudioFrame> get audioFrames;

  Future<List<RingFileRef>> listFiles();

  Future<Uint8List> readMemoryInfo();

  Future<void> startLocalRecording();

  Future<void> stopLocalRecording();

  Future<void> startLiveRecording();

  Future<void> stopLiveRecording();

  Future<Uint8List> download(RingFileRef file);
}

typedef RingProbeDelay = Future<void> Function(Duration duration);

@immutable
class RingConnectedProbeResult {
  const RingConnectedProbeResult({
    required this.duration,
    required this.newFiles,
    required this.memoryInfo,
    required this.livePcmBytes,
    required this.liveFrameGaps,
    required this.downloadedPcmBytes,
    required this.liveStartError,
  });

  final Duration duration;
  final List<RingFileRef> newFiles;
  final Uint8List memoryInfo;
  final int livePcmBytes;
  final int liveFrameGaps;
  final int downloadedPcmBytes;
  final Object? liveStartError;

  bool get livePcmValid =>
      liveStartError == null && livePcmBytes > 0 && liveFrameGaps == 0;

  bool get localFileValid => newFiles.length == 1 && downloadedPcmBytes > 0;

  RingConnectedCaptureMode get connectedMode =>
      _captureMode(livePcmValid: livePcmValid, localFileValid: localFileValid);
}

class RingCapabilityProbe {
  RingCapabilityProbe({
    required RingCapabilityGateway gateway,
    RingProbeDelay? delay,
  }) : _gateway = gateway,
       _delay = delay ?? Future<void>.delayed;

  final RingCapabilityGateway _gateway;
  final RingProbeDelay _delay;

  Future<RingConnectedProbeResult> runConnectedProbe({
    Duration duration = const Duration(seconds: 30),
  }) async {
    final baseline = await _gateway.listFiles();
    Uint8List memoryInfo;
    try {
      memoryInfo = await _gateway.readMemoryInfo();
    } catch (_) {
      memoryInfo = Uint8List(0);
    }

    var liveBytes = 0;
    var liveGaps = 0;
    int? lastSequence;
    final audioSubscription = _gateway.audioFrames.listen((frame) {
      liveBytes += frame.pcm.length;
      final previous = lastSequence;
      if (previous != null && frame.seq > previous + 1) {
        liveGaps += frame.seq - previous - 1;
      }
      lastSequence = frame.seq;
    });

    Object? liveStartError;
    var liveStarted = false;
    await _gateway.startLocalRecording();
    try {
      try {
        await _gateway.startLiveRecording();
        liveStarted = true;
      } catch (error) {
        liveStartError = error;
      }
      await _delay(duration);
    } finally {
      if (liveStarted) await _gateway.stopLiveRecording();
      await _gateway.stopLocalRecording();
      await audioSubscription.cancel();
    }

    final after = await _gateway.listFiles();
    final baselineIds = baseline.map((file) => file.identityMaterial).toSet();
    final newFiles = after
        .where((file) => !baselineIds.contains(file.identityMaterial))
        .toList(growable: false);
    var downloadedPcmBytes = 0;
    if (newFiles.length == 1) {
      downloadedPcmBytes = (await _gateway.download(newFiles.single)).length;
    }
    return RingConnectedProbeResult(
      duration: duration,
      newFiles: List<RingFileRef>.unmodifiable(newFiles),
      memoryInfo: memoryInfo,
      livePcmBytes: liveBytes,
      liveFrameGaps: liveGaps,
      downloadedPcmBytes: downloadedPcmBytes,
      liveStartError: liveStartError,
    );
  }
}

class ChipletRingCapabilityGateway implements RingCapabilityGateway {
  ChipletRingCapabilityGateway(
    this._ring, {
    this.listTimeout = const Duration(seconds: 12),
    this.downloadTimeout = const Duration(seconds: 60),
    this.memoryTimeout = const Duration(seconds: 12),
  });

  final ChipletRing _ring;
  final Duration listTimeout;
  final Duration downloadTimeout;
  final Duration memoryTimeout;
  var _operationSequence = 0;

  String _operationId(String kind) =>
      'probe-$kind-${DateTime.now().microsecondsSinceEpoch}-${_operationSequence++}';

  @override
  Stream<RingAudioFrame> get audioFrames => _ring.audioFrames;

  @override
  Future<List<RingFileRef>> listFiles() async {
    final operationId = _operationId('list');
    final files = <String, RingFileRef>{};
    final completer = Completer<List<RingFileRef>>();
    late final StreamSubscription<RingFileEvent> subscription;
    subscription = _ring.fileEvents.listen(
      (event) {
        if (event.operationId != operationId || completer.isCompleted) return;
        switch (event) {
          case RingFileItemEvent(:final file, :final count):
            files[file.identityMaterial] = file;
            if (count > 0 && files.length >= count) {
              completer.complete(files.values.toList(growable: false));
            }
          case RingFileEmptyEvent() || RingFileDoneEvent():
            completer.complete(files.values.toList(growable: false));
          default:
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    try {
      await _ring.getFileList(operationId: operationId);
      return await completer.future.timeout(listTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<Uint8List> readMemoryInfo() async {
    final operationId = _operationId('memory');
    final completer = Completer<Uint8List>();
    late final StreamSubscription<RingFileEvent> subscription;
    subscription = _ring.fileEvents.listen(
      (event) {
        if (event.operationId != operationId || completer.isCompleted) return;
        if (event case RingMemoryInfoEvent(:final raw)) {
          completer.complete(raw);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    try {
      await _ring.getFileMemory(operationId: operationId);
      return await completer.future.timeout(memoryTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<Uint8List> download(RingFileRef file) async {
    final operationId = _operationId('download');
    final downloaded = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();
    late final StreamSubscription<RingFileEvent> subscription;
    subscription = _ring.fileEvents.listen(
      (event) {
        if (event.operationId != operationId || completer.isCompleted) return;
        switch (event) {
          case RingFileAudioEvent(pcm: final chunk):
            downloaded.add(chunk);
          case RingFileDoneEvent():
            completer.complete(downloaded.takeBytes());
          default:
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    try {
      await _ring.downloadFile(
        0,
        file.id,
        operationId: operationId,
        fileName: file.name,
        sizeBytes: file.sizeBytes,
      );
      return await completer.future.timeout(downloadTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> startLiveRecording() => _ring.startRecording();

  @override
  Future<void> startLocalRecording() =>
      _ring.startLocalRecording(operationId: _operationId('local-start'));

  @override
  Future<void> stopLiveRecording() => _ring.stopRecording();

  @override
  Future<void> stopLocalRecording() =>
      _ring.stopLocalRecording(operationId: _operationId('local-stop'));
}

@immutable
class RingStorageSample {
  const RingStorageSample({required this.duration, required this.bytes});

  final Duration duration;
  final int bytes;
}

@immutable
class RingCapabilityReport {
  const RingCapabilityReport({
    required this.usableBytes,
    required this.bytesPerSecond,
    required this.reserveBytes,
    required this.estimatedSafeSeconds,
    required this.livePcmValid,
    required this.localFileValid,
    required this.connectedMode,
  });

  factory RingCapabilityReport.fromSamples({
    required int usableBytes,
    required List<RingStorageSample> samples,
    required bool livePcmValid,
    required bool localFileValid,
  }) {
    if (usableBytes <= 0) {
      throw ArgumentError.value(usableBytes, 'usableBytes', 'must be positive');
    }
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
    final rates = samples.map((sample) {
      final seconds = sample.duration.inMilliseconds / 1000;
      if (seconds <= 0 || sample.bytes <= 0) {
        throw ArgumentError.value(sample, 'samples', 'must be positive');
      }
      return sample.bytes / seconds;
    }).toList()..sort();
    final middle = rates.length ~/ 2;
    final median = rates.length.isOdd
        ? rates[middle]
        : (rates[middle - 1] + rates[middle]) / 2;
    final bytesPerSecond = median.round();
    final largestSample = samples
        .map((sample) => sample.bytes)
        .reduce(math.max);
    final reserveBytes = math.max((usableBytes * 0.10).ceil(), largestSample);
    final safeBytes = math.max(0, usableBytes - reserveBytes);
    return RingCapabilityReport(
      usableBytes: usableBytes,
      bytesPerSecond: bytesPerSecond,
      reserveBytes: reserveBytes,
      estimatedSafeSeconds: safeBytes ~/ bytesPerSecond,
      livePcmValid: livePcmValid,
      localFileValid: localFileValid,
      connectedMode: _captureMode(
        livePcmValid: livePcmValid,
        localFileValid: localFileValid,
      ),
    );
  }

  final int usableBytes;
  final int bytesPerSecond;
  final int reserveBytes;
  final int estimatedSafeSeconds;
  final bool livePcmValid;
  final bool localFileValid;
  final RingConnectedCaptureMode connectedMode;
}
