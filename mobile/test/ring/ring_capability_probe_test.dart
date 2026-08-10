import 'dart:async';
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:eureka/ring/ring_capability_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capacity report derives codec rate from physical samples', () {
    final report = RingCapabilityReport.fromSamples(
      usableBytes: 8 * 1024 * 1024,
      samples: const [
        RingStorageSample(duration: Duration(seconds: 30), bytes: 120000),
        RingStorageSample(duration: Duration(seconds: 60), bytes: 240000),
        RingStorageSample(duration: Duration(seconds: 120), bytes: 480000),
      ],
      livePcmValid: true,
      localFileValid: true,
    );

    expect(report.bytesPerSecond, 4000);
    expect(report.connectedMode, RingConnectedCaptureMode.dualPath);
    expect(report.reserveBytes, 838861);
    expect(report.estimatedSafeSeconds, 1887);
  });

  test('connected mode reports realtime only when no local file is valid', () {
    final report = RingCapabilityReport.fromSamples(
      usableBytes: 8 * 1024 * 1024,
      samples: const [
        RingStorageSample(duration: Duration(seconds: 60), bytes: 240000),
      ],
      livePcmValid: true,
      localFileValid: false,
    );

    expect(report.connectedMode, RingConnectedCaptureMode.realtimeOnly);
  });

  test('connected mode reports unsupported when neither path is valid', () {
    final report = RingCapabilityReport.fromSamples(
      usableBytes: 8 * 1024 * 1024,
      samples: const [
        RingStorageSample(duration: Duration(seconds: 60), bytes: 240000),
      ],
      livePcmValid: false,
      localFileValid: false,
    );

    expect(report.connectedMode, RingConnectedCaptureMode.unsupported);
  });

  test(
    'connected probe preserves a local file while measuring live PCM',
    () async {
      final oldFile = _file('old.bin', 1, 1000);
      final newFile = _file('new.bin', 2, 120000);
      final gateway = _FakeGateway(
        fileLists: [
          [oldFile],
          [oldFile, newFile],
        ],
        downloadedPcm: Uint8List(32000),
      );
      final probe = RingCapabilityProbe(
        gateway: gateway,
        delay: (_) async {
          gateway.emitFrame(seq: 0, bytes: 16000);
          gateway.emitFrame(seq: 1, bytes: 16000);
        },
      );

      final result = await probe.runConnectedProbe(
        duration: const Duration(seconds: 30),
      );

      expect(gateway.order, [
        'list',
        'memory',
        'startLocal',
        'startLive',
        'stopLive',
        'stopLocal',
        'list',
        'download:new.bin',
      ]);
      expect(result.newFiles, [newFile]);
      expect(result.livePcmBytes, 32000);
      expect(result.liveFrameGaps, 0);
      expect(result.downloadedPcmBytes, 32000);
      expect(result.localFileValid, isTrue);
      expect(result.livePcmValid, isTrue);
      expect(result.connectedMode, RingConnectedCaptureMode.dualPath);
    },
  );

  test(
    'connected probe keeps local measurement when live start fails',
    () async {
      final newFile = _file('new.bin', 2, 120000);
      final gateway = _FakeGateway(
        fileLists: [
          const [],
          [newFile],
        ],
        downloadedPcm: Uint8List(32000),
        failLiveStart: true,
      );
      final probe = RingCapabilityProbe(gateway: gateway, delay: (_) async {});

      final result = await probe.runConnectedProbe(duration: Duration.zero);

      expect(result.localFileValid, isTrue);
      expect(result.livePcmValid, isFalse);
      expect(result.connectedMode, RingConnectedCaptureMode.localFirst);
      expect(
        gateway.order,
        containsAllInOrder(['startLocal', 'startLive', 'stopLocal']),
      );
    },
  );
}

RingFileRef _file(String name, int id, int size) =>
    RingFileRef(name: name, id: [id], sizeBytes: size);

class _FakeGateway implements RingCapabilityGateway {
  _FakeGateway({
    required this.fileLists,
    required this.downloadedPcm,
    this.failLiveStart = false,
  });

  final List<List<RingFileRef>> fileLists;
  final Uint8List downloadedPcm;
  final bool failLiveStart;
  final order = <String>[];
  final _frames = StreamController<RingAudioFrame>.broadcast(sync: true);
  var _listIndex = 0;

  @override
  Stream<RingAudioFrame> get audioFrames => _frames.stream;

  void emitFrame({required int seq, required int bytes}) {
    _frames.add(RingAudioFrame(pcm: Uint8List(bytes), seq: seq, channels: 1));
  }

  @override
  Future<Uint8List> download(RingFileRef file) async {
    order.add('download:${file.name}');
    return downloadedPcm;
  }

  @override
  Future<List<RingFileRef>> listFiles() async {
    order.add('list');
    return fileLists[_listIndex++];
  }

  @override
  Future<Uint8List> readMemoryInfo() async {
    order.add('memory');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> startLiveRecording() async {
    order.add('startLive');
    if (failLiveStart) throw StateError('live unsupported');
  }

  @override
  Future<void> startLocalRecording() async {
    order.add('startLocal');
  }

  @override
  Future<void> stopLiveRecording() async {
    order.add('stopLive');
  }

  @override
  Future<void> stopLocalRecording() async {
    order.add('stopLocal');
  }
}
