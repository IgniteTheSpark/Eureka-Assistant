import 'dart:async';
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';

abstract interface class RingFileNative {
  Stream<RingFileEvent> get fileEvents;

  Future<void> getFileList(String operationId);

  Future<void> downloadFile(String operationId, RingFileRef file);

  Future<void> deleteFile(String operationId, RingFileRef file);
}

abstract interface class RingFileAccess {
  Stream<void> get memoryFullEvents;

  Future<List<RingFileRef>> listFiles();

  Future<Uint8List> download(RingFileRef file);

  Future<bool> delete(RingFileRef file);
}

typedef RingFileOperationIdFactory = String Function();

class RingFileGateway implements RingFileAccess {
  RingFileGateway({
    required RingFileNative native,
    RingFileOperationIdFactory? createOperationId,
    this.listTimeout = const Duration(seconds: 15),
    this.downloadTimeout = const Duration(seconds: 60),
    this.deleteTimeout = const Duration(seconds: 15),
  }) : _native = native,
       _createOperationId = createOperationId ?? _defaultOperationId {
    _eventSubscription = _native.fileEvents.listen(
      _onEvent,
      onError: _onStreamError,
    );
  }

  factory RingFileGateway.production({ChipletRing? ring}) {
    return RingFileGateway(
      native: ChipletRingFileNative(ring ?? ChipletRing()),
    );
  }

  final RingFileNative _native;
  final RingFileOperationIdFactory _createOperationId;
  final Duration listTimeout;
  final Duration downloadTimeout;
  final Duration deleteTimeout;
  final _memoryFullController = StreamController<void>.broadcast();
  late final StreamSubscription<RingFileEvent> _eventSubscription;
  _GatewayOperation? _active;
  bool _disposed = false;
  static int _operationSequence = 0;

  static String _defaultOperationId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'ring-file-$micros-${_operationSequence++}';
  }

  @override
  Stream<void> get memoryFullEvents => _memoryFullController.stream;

  @override
  Future<List<RingFileRef>> listFiles() {
    final files = <String, RingFileRef>{};
    return _run<List<RingFileRef>>(
      timeout: listTimeout,
      start: _native.getFileList,
      handle: (event, complete, _) {
        if (event is RingFileItemEvent) {
          files[event.file.identityMaterial] = event.file;
          if (event.count > 0 && files.length >= event.count) {
            complete(List<RingFileRef>.unmodifiable(files.values));
          }
          return;
        }
        if (event is RingFileDoneEvent || event is RingFileEmptyEvent) {
          complete(List<RingFileRef>.unmodifiable(files.values));
        }
      },
    );
  }

  @override
  Future<Uint8List> download(RingFileRef file) {
    final bytes = BytesBuilder(copy: false);
    return _run<Uint8List>(
      timeout: downloadTimeout,
      start: (operationId) => _native.downloadFile(operationId, file),
      handle: (event, complete, _) {
        if (event is RingFileAudioEvent) {
          bytes.add(event.pcm);
          return;
        }
        if (event is RingFileDoneEvent || event is RingFileEmptyEvent) {
          complete(bytes.takeBytes());
        }
      },
    );
  }

  @override
  Future<bool> delete(RingFileRef file) {
    return _run<bool>(
      timeout: deleteTimeout,
      start: (operationId) => _native.deleteFile(operationId, file),
      handle: (event, complete, _) {
        if (event is RingFileDeletedEvent) {
          complete(event.ok);
        } else if (event is RingFileDoneEvent || event is RingFileEmptyEvent) {
          complete(false);
        }
      },
    );
  }

  Future<T> _run<T>({
    required Duration timeout,
    required Future<void> Function(String operationId) start,
    required void Function(
      RingFileEvent event,
      void Function(T value) complete,
      void Function(Object error, [StackTrace? stackTrace]) fail,
    )
    handle,
  }) {
    if (_disposed) {
      return Future<T>.error(StateError('ring file gateway is disposed'));
    }
    if (_active != null) {
      return Future<T>.error(
        StateError('another ring file operation is already active'),
      );
    }

    final operationId = _createOperationId();
    final completer = Completer<T>();
    late final Timer timer;

    void finish() {
      timer.cancel();
      if (_active?.operationId == operationId) _active = null;
    }

    void complete(T value) {
      if (completer.isCompleted) return;
      finish();
      completer.complete(value);
    }

    void fail(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) return;
      finish();
      completer.completeError(error, stackTrace ?? StackTrace.current);
    }

    timer = Timer(
      timeout,
      () => fail(TimeoutException('ring file operation timed out', timeout)),
    );
    _active = _GatewayOperation(
      operationId: operationId,
      onEvent: (event) => handle(event, complete, fail),
      onError: fail,
    );
    Future<void>.sync(() => start(operationId)).catchError((Object error) {
      fail(error);
    });
    return completer.future;
  }

  void _onEvent(RingFileEvent event) {
    if (event is RingMemoryFullEvent && !_memoryFullController.isClosed) {
      _memoryFullController.add(null);
    }
    final active = _active;
    if (active == null || event.operationId != active.operationId) return;
    active.onEvent(event);
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _active?.onError(error, stackTrace);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _active?.onError(
      StateError('ring file gateway disposed'),
      StackTrace.current,
    );
    _active = null;
    await _eventSubscription.cancel();
    await _memoryFullController.close();
  }
}

class ChipletRingFileNative implements RingFileNative {
  ChipletRingFileNative(this._ring);

  final ChipletRing _ring;

  @override
  Stream<RingFileEvent> get fileEvents => _ring.fileEvents;

  @override
  Future<void> getFileList(String operationId) {
    return _ring.getFileList(operationId: operationId);
  }

  @override
  Future<void> downloadFile(String operationId, RingFileRef file) {
    return _ring.downloadFile(
      0,
      file.id,
      operationId: operationId,
      fileName: file.name,
      sizeBytes: file.sizeBytes,
    );
  }

  @override
  Future<void> deleteFile(String operationId, RingFileRef file) {
    return _ring.deleteFile(
      file.id,
      operationId: operationId,
      fileName: file.name,
      sizeBytes: file.sizeBytes,
    );
  }
}

class _GatewayOperation {
  const _GatewayOperation({
    required this.operationId,
    required this.onEvent,
    required this.onError,
  });

  final String operationId;
  final void Function(RingFileEvent event) onEvent;
  final void Function(Object error, [StackTrace? stackTrace]) onError;
}
