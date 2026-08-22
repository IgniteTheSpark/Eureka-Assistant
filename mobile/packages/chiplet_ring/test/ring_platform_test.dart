import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:chiplet_ring/src/ring_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chiplet_ring/methods');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  test(
    'filtered scan and background capture invoke expected native methods',
    () async {
      final p = RingPlatform();
      await p.startBackgroundSession();
      await p.startScan(targetId: 'AA:BB');
      await p.connect('AA:BB');
      await p.setCaptureActive(true);
      await p.startRecording();
      await p.stopRecording();
      await p.setCaptureActive(false);
      await p.disconnect();
      await p.stopBackgroundSession();
      expect(calls.map((call) => call.method), [
        'startBackgroundSession',
        'startScan',
        'connect',
        'setCaptureActive',
        'startRecording',
        'stopRecording',
        'setCaptureActive',
        'disconnect',
        'stopBackgroundSession',
      ]);
      expect(calls[1].arguments, {'targetId': 'AA:BB'});
      expect(calls[3].arguments, {'active': true});
      expect(calls[6].arguments, {'active': false});
    },
  );

  test('file commands carry a stable operation id', () async {
    final p = RingPlatform();

    await p.getFileList(operationId: 'list-1');
    await p.getFileMemory(operationId: 'memory-1');
    await p.downloadFile(
      operationId: 'download-1',
      file: const RingFileRef(
        name: 'R0001.bin',
        id: [1, 2, 3],
        sizeBytes: 240000,
      ),
    );
    await p.deleteFile(
      operationId: 'delete-1',
      file: const RingFileRef(
        name: 'R0001.bin',
        id: [1, 2, 3],
        sizeBytes: 240000,
      ),
    );

    expect(calls.map((call) => call.method), [
      'getFileList',
      'getFileMemory',
      'downloadFile',
      'deleteFile',
    ]);
    expect(calls[0].arguments, {'operationId': 'list-1'});
    expect(calls[1].arguments, {'operationId': 'memory-1'});
    expect(calls[2].arguments, {
      'operationId': 'download-1',
      'name': 'R0001.bin',
      'id': [1, 2, 3],
      'size': 240000,
    });
    expect(calls[3].arguments, {
      'operationId': 'delete-1',
      'name': 'R0001.bin',
      'id': [1, 2, 3],
      'size': 240000,
    });
  });

  test('typed file event retains operation and device file identity', () {
    final event = RingFileEvent.fromMap({
      'kind': 'item',
      'operationId': 'list-1',
      'name': 'R0001.bin',
      'size': 240000,
      'id': [1, 2, 3],
    });

    expect(event, isA<RingFileItemEvent>());
    final item = event as RingFileItemEvent;
    expect(item.operationId, 'list-1');
    expect(item.file.name, 'R0001.bin');
    expect(item.file.sizeBytes, 240000);
    expect(item.file.id, [1, 2, 3]);
  });
}
