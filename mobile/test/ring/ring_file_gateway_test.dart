import 'dart:async';
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:eureka/ring/ring_file_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'late done from an old download cannot complete the active download',
    () async {
      final native = _FakeRingFileNative();
      final gateway = RingFileGateway(native: native);
      addTearDown(gateway.dispose);

      final first = gateway.download(_file(name: 'R1.bin', id: [1]));
      await _pump();
      native.emit(RingFileAudioEvent(native.activeOperationId, Uint8List(8)));
      native.emit(RingFileDoneEvent(native.activeOperationId));
      expect((await first).length, 8);

      final second = gateway.download(_file(name: 'R2.bin', id: [2]));
      await _pump();
      native.emit(const RingFileDoneEvent('old-operation'));
      await expectLater(
        Future.any<Object?>([
          second.then<Object?>((value) => value),
          Future<Object?>.delayed(
            const Duration(milliseconds: 20),
            () => 'still-pending',
          ),
        ]),
        completion('still-pending'),
      );
      native.emit(RingFileAudioEvent(native.activeOperationId, Uint8List(16)));
      native.emit(RingFileDoneEvent(native.activeOperationId));
      expect((await second).length, 16);
    },
  );

  test('list deduplicates callbacks and completes at reported count', () async {
    final native = _FakeRingFileNative();
    final gateway = RingFileGateway(native: native);
    addTearDown(gateway.dispose);

    final future = gateway.listFiles();
    await _pump();
    final operationId = native.activeOperationId;
    final first = _file(name: 'R1.bin', id: [1]);
    final second = _file(name: 'R2.bin', id: [2]);
    native.emit(RingFileItemEvent(operationId, first, count: 2, index: 0));
    native.emit(RingFileItemEvent(operationId, first, count: 2, index: 0));
    native.emit(RingFileItemEvent(operationId, second, count: 2, index: 1));

    expect((await future).map((file) => file.name), ['R1.bin', 'R2.bin']);
  });

  test('gateway refuses a second concurrent hardware operation', () async {
    final native = _FakeRingFileNative();
    final gateway = RingFileGateway(native: native);
    addTearDown(gateway.dispose);

    final first = gateway.listFiles();
    await _pump();

    await expectLater(
      gateway.delete(_file(name: 'R1.bin', id: [1])),
      throwsStateError,
    );
    native.emit(RingFileEmptyEvent(native.activeOperationId));
    expect(await first, isEmpty);
  });

  test('delete only accepts the matching native acknowledgement', () async {
    final native = _FakeRingFileNative();
    final gateway = RingFileGateway(native: native);
    addTearDown(gateway.dispose);

    final future = gateway.delete(_file(name: 'R1.bin', id: [1]));
    await _pump();
    native.emit(const RingFileDeletedEvent('old-operation', true));
    native.emit(RingFileDeletedEvent(native.activeOperationId, true));

    expect(await future, isTrue);
  });
}

RingFileRef _file({required String name, required List<int> id}) {
  return RingFileRef(name: name, id: id, sizeBytes: 240000);
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _FakeRingFileNative implements RingFileNative {
  final _events = StreamController<RingFileEvent>.broadcast(sync: true);
  String activeOperationId = '';

  void emit(RingFileEvent event) => _events.add(event);

  @override
  Stream<RingFileEvent> get fileEvents => _events.stream;

  @override
  Future<void> deleteFile(String operationId, RingFileRef file) async {
    activeOperationId = operationId;
  }

  @override
  Future<void> downloadFile(String operationId, RingFileRef file) async {
    activeOperationId = operationId;
  }

  @override
  Future<void> getFileList(String operationId) async {
    activeOperationId = operationId;
  }
}
