import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:eureka/voice_input/voice_audio_capture.dart';
import 'package:eureka/voice_input/voice_gateway.dart';
import 'package:eureka/voice_input/voice_input_models.dart';
import 'package:eureka/voice_input/voice_input_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PcmFrameChunker', () {
    test(
      'preserves order and flushes only complete trailing PCM16 samples',
      () {
        final chunker = PcmFrameChunker(frameBytes: 6);

        final first = chunker.add(Uint8List.fromList([0, 1, 2, 3]));
        final second = chunker.add(Uint8List.fromList([4, 5, 6, 7, 8]));

        expect(first, isEmpty);
        expect(second.map((value) => value.toList()), [
          [0, 1, 2, 3, 4, 5],
        ]);
        expect(chunker.flush()?.toList(), [6, 7]);
      },
    );
  });

  test(
    'permission denial happens before allocating a gateway socket',
    () async {
      final capture = _FakeCapture(permission: false);
      var connections = 0;
      final service = _service(
        capture: capture,
        connector: (uri, headers) async {
          connections += 1;
          return _FakeGatewayConnection();
        },
      );

      await expectLater(
        service.start(VoiceInputMode.ordinary),
        throwsA(
          isA<VoiceInputException>().having(
            (error) => error.code,
            'code',
            VoiceInputErrorCode.permissionDenied,
          ),
        ),
      );
      expect(capture.permissionChecks, 1);
      expect(capture.startCount, 0);
      expect(connections, 0);
    },
  );

  test(
    'converts gateway URI and sends auth plus exact start contract',
    () async {
      final capture = _FakeCapture();
      final gateway = _FakeGatewayConnection(onText: _readyOnStart);
      Uri? connectedUri;
      Map<String, String>? connectedHeaders;
      final service = _service(
        capture: capture,
        apiBase: 'https://api.example.test/base',
        connector: (uri, headers) async {
          connectedUri = uri;
          connectedHeaders = headers;
          return gateway;
        },
      );

      final session = await service.start(VoiceInputMode.ordinary);

      expect(connectedUri, Uri.parse('wss://api.example.test/api/asr/stream'));
      expect(connectedHeaders, {'Authorization': 'Bearer test-token'});
      expect(gateway.sentText.single, {
        'type': 'start',
        'voiceSessionId': 'session-1',
        'mode': 'ordinary',
        'audio': {'encoding': 'pcm_s16le', 'sampleRate': 16000, 'channels': 1},
      });
      expect(capture.startCount, 1);
      await session.cancel();
    },
  );

  test('http API base becomes ws', () {
    expect(
      voiceGatewayUri('http://localhost:8000'),
      Uri.parse('ws://localhost:8000/api/asr/stream'),
    );
  });

  test(
    'coordinator cancellation interrupts a start waiting for ready',
    () async {
      final capture = _FakeCapture();
      final gateway = _FakeGatewayConnection();
      final service = _service(
        capture: capture,
        connector: (_, _) async => gateway,
      );
      final start = service.start(VoiceInputMode.ordinary);
      final startExpectation = expectLater(
        start,
        throwsA(
          isA<VoiceInputException>().having(
            (error) => error.code,
            'code',
            VoiceInputErrorCode.connectionFailed,
          ),
        ),
      );
      await pumpEventQueue();

      await service.cancelActive();
      await startExpectation;
      expect(capture.stopCount, 1);
      expect(capture.disposeCount, 1);
      expect(gateway.closeCount, 1);
    },
  );

  test('pre-ready gateway errors retain their normalized code', () async {
    final capture = _FakeCapture();
    late _FakeGatewayConnection gateway;
    gateway = _FakeGatewayConnection(
      onText: (value) {
        if (value['type'] == 'start') {
          scheduleMicrotask(
            () => gateway.emit({
              'type': 'error',
              'voiceSessionId': 'session-1',
              'code': 'rate_limited',
              'retryable': true,
            }),
          );
        }
      },
    );

    await expectLater(
      _service(
        capture: capture,
        connector: (_, _) async => gateway,
      ).start(VoiceInputMode.ordinary),
      throwsA(
        isA<VoiceInputException>().having(
          (error) => error.code,
          'code',
          VoiceInputErrorCode.rateLimited,
        ),
      ),
    );
  });

  test(
    'cancel interrupts a pending connector and closes a late socket',
    () async {
      final firstCapture = _FakeCapture();
      final secondCapture = _FakeCapture();
      final captures = <_FakeCapture>[firstCapture, secondCapture];
      final pending = Completer<VoiceGatewayConnection>();
      final lateGateway = _FakeGatewayConnection();
      final recoveredGateway = _FakeGatewayConnection(onText: _readyOnStart);
      var connectionCount = 0;
      final service = VoiceInputService(
        captureFactory: () => captures.removeAt(0),
        connector: (_, _) {
          connectionCount += 1;
          return connectionCount == 1
              ? pending.future
              : Future.value(recoveredGateway);
        },
        apiBase: 'https://api.example.test',
        tokenProvider: () => 'test-token',
        sessionIdFactory: () => 'session-1',
        connectionTimeout: const Duration(seconds: 1),
        cleanupTimeout: const Duration(milliseconds: 10),
      );

      final firstExpectation = expectLater(
        service.start(VoiceInputMode.ordinary),
        throwsA(
          isA<VoiceInputException>().having(
            (error) => error.code,
            'code',
            VoiceInputErrorCode.connectionFailed,
          ),
        ),
      );
      await pumpEventQueue();
      await service.cancelActive();
      await firstExpectation;

      final recovered = await service.start(VoiceInputMode.ordinary);
      expect(secondCapture.startCount, 1);
      await recovered.cancel();

      pending.complete(lateGateway);
      await pumpEventQueue();
      expect(lateGateway.closeCount, 1);
      expect(firstCapture.disposeCount, 1);
    },
  );

  test('cancel interrupts a pending microphone permission check', () async {
    final pendingPermission = Completer<bool>();
    final firstCapture = _FakeCapture(permissionCompleter: pendingPermission);
    final secondCapture = _FakeCapture();
    final captures = <_FakeCapture>[firstCapture, secondCapture];
    final gateway = _FakeGatewayConnection(onText: _readyOnStart);
    final service = VoiceInputService(
      captureFactory: () => captures.removeAt(0),
      connector: (_, _) async => gateway,
      apiBase: 'https://api.example.test',
      tokenProvider: () => 'test-token',
      sessionIdFactory: () => 'session-1',
      connectionTimeout: const Duration(seconds: 1),
      cleanupTimeout: const Duration(milliseconds: 10),
    );

    final firstExpectation = expectLater(
      service.start(VoiceInputMode.ordinary),
      throwsA(
        isA<VoiceInputException>().having(
          (error) => error.code,
          'code',
          VoiceInputErrorCode.connectionFailed,
        ),
      ),
    );
    await pumpEventQueue();
    await service.cancelActive();
    await firstExpectation;

    final recovered = await service.start(VoiceInputMode.ordinary);
    expect(secondCapture.startCount, 1);
    await recovered.cancel();
    pendingPermission.complete(true);
    await pumpEventQueue();
    expect(firstCapture.disposeCount, 1);
  });

  test('cancel interrupts a recorder start that never returns', () async {
    final pendingAudio = Completer<Stream<Uint8List>>();
    final firstCapture = _FakeCapture(startCompleter: pendingAudio);
    final secondCapture = _FakeCapture();
    final captures = <_FakeCapture>[firstCapture, secondCapture];
    late _FakeGatewayConnection firstGateway;
    firstGateway = _FakeGatewayConnection(
      onText: (value) {
        if (value['type'] == 'start') {
          scheduleMicrotask(() => firstGateway.emit(_ready(value)));
        }
      },
    );
    late _FakeGatewayConnection secondGateway;
    secondGateway = _FakeGatewayConnection(
      onText: (value) {
        if (value['type'] == 'start') {
          scheduleMicrotask(() => secondGateway.emit(_ready(value)));
        }
      },
    );
    var connectionCount = 0;
    final service = VoiceInputService(
      captureFactory: () => captures.removeAt(0),
      connector: (_, _) async =>
          connectionCount++ == 0 ? firstGateway : secondGateway,
      apiBase: 'https://api.example.test',
      tokenProvider: () => 'test-token',
      sessionIdFactory: () => 'session-1',
      connectionTimeout: const Duration(seconds: 1),
      cleanupTimeout: const Duration(milliseconds: 10),
    );

    final firstExpectation = expectLater(
      service.start(VoiceInputMode.ordinary),
      throwsA(
        isA<VoiceInputException>().having(
          (error) => error.code,
          'code',
          VoiceInputErrorCode.connectionFailed,
        ),
      ),
    );
    await pumpEventQueue();
    expect(firstCapture.startCount, 1);
    await service.cancelActive();
    await firstExpectation;

    final recovered = await service.start(VoiceInputMode.ordinary);
    expect(secondCapture.startCount, 1);
    await recovered.cancel();
    var lateListenCount = 0;
    var lateCancelCount = 0;
    final lateAudio = StreamController<Uint8List>(
      onListen: () => lateListenCount += 1,
      onCancel: () => lateCancelCount += 1,
    );
    pendingAudio.complete(lateAudio.stream);
    await pumpEventQueue();
    expect(lateListenCount, 1);
    expect(lateCancelCount, 1);
    expect(firstCapture.disposeCount, 1);
    expect(firstGateway.closeCount, 1);
    await lateAudio.close();
  });

  test('stop fails closed when native recorder stop never returns', () async {
    final capture = _FakeCapture(stopCompleter: Completer<void>());
    final gateway = _FakeGatewayConnection(onText: _readyOnStart);
    final session = await VoiceInputService(
      captureFactory: () => capture,
      connector: (_, _) async => gateway,
      apiBase: 'https://api.example.test',
      tokenProvider: () => 'test-token',
      sessionIdFactory: () => 'session-1',
      cleanupTimeout: const Duration(milliseconds: 10),
    ).start(VoiceInputMode.ordinary);
    final events = session.events.toList();

    await session.stop();

    expect(await events, const [
      VoiceInputFailure(
        code: VoiceInputErrorCode.unsupportedAudio,
        retryable: false,
      ),
    ]);
    expect(capture.disposeCount, 1);
    expect(gateway.closeCount, 1);
  });

  test(
    'waits for ready before recording and forwards ordered PCM frames',
    () async {
      final capture = _FakeCapture();
      late _FakeGatewayConnection gateway;
      gateway = _FakeGatewayConnection(
        onText: (value) {
          if (value['type'] == 'start') {
            expect(capture.startCount, 0);
            scheduleMicrotask(() => gateway.emit(_ready(value)));
          } else if (value['type'] == 'stop') {
            scheduleMicrotask(() {
              gateway.emit({
                'type': 'stable',
                'voiceSessionId': 'session-1',
                'sequence': 1,
                'text': '你好',
              });
              gateway.emit({
                'type': 'final',
                'voiceSessionId': 'session-1',
                'sequence': 2,
                'text': '你好 world',
                'audioDurationMs': 220,
              });
            });
          }
        },
      );
      final session = await _service(
        capture: capture,
        connector: (_, _) async => gateway,
      ).start(VoiceInputMode.ordinary);
      final eventsFuture = session.events.toList();

      capture.add(List<int>.generate(5000, (index) => index % 251));
      capture.add(List<int>.generate(2000, (index) => (index + 7) % 251));
      await pumpEventQueue();
      await session.stop();
      final events = await eventsFuture;

      expect(gateway.sentBytes.map((value) => value.length), [6400, 600]);
      expect(gateway.sentBytes.expand((value) => value), [
        ...List<int>.generate(5000, (index) => index % 251),
        ...List<int>.generate(2000, (index) => (index + 7) % 251),
      ]);
      expect(events, [
        const VoiceTranscriptEvent(
          kind: VoiceTranscriptKind.stable,
          sequence: 1,
          text: '你好',
        ),
        const VoiceTranscriptEvent(
          kind: VoiceTranscriptKind.finalTranscript,
          sequence: 2,
          text: '你好 world',
          audioDurationMs: 220,
        ),
      ]);
      expect(capture.stopCount, 1);
      expect(capture.disposeCount, 1);
      expect(gateway.closeCount, 1);
    },
  );

  test(
    'forwards the recorder final PCM chunk produced while stopping',
    () async {
      final capture = _FakeCapture(bytesOnStop: [9, 8, 7, 6]);
      late _FakeGatewayConnection gateway;
      gateway = _FakeGatewayConnection(
        onText: (value) {
          if (value['type'] == 'start') {
            scheduleMicrotask(() => gateway.emit(_ready(value)));
          } else if (value['type'] == 'stop') {
            scheduleMicrotask(() {
              gateway.emit({
                'type': 'final',
                'voiceSessionId': 'session-1',
                'sequence': 1,
                'text': 'done',
                'audioDurationMs': 1,
              });
            });
          }
        },
      );
      final session = await _service(
        capture: capture,
        connector: (_, _) async => gateway,
      ).start(VoiceInputMode.ordinary);
      final eventsFuture = session.events.toList();

      await session.stop();
      await eventsFuture;

      expect(gateway.sentBytes.map((value) => value.toList()), [
        [9, 8, 7, 6],
      ]);
    },
  );

  test('start-send failure releases capture and socket exactly once', () async {
    final capture = _FakeCapture();
    final gateway = _FakeGatewayConnection(throwOnText: true);
    final service = _service(
      capture: capture,
      connector: (_, _) async => gateway,
    );

    await expectLater(
      service.start(VoiceInputMode.ordinary),
      throwsA(
        isA<VoiceInputException>().having(
          (error) => error.code,
          'code',
          VoiceInputErrorCode.connectionFailed,
        ),
      ),
    );

    expect(capture.stopCount, 1);
    expect(capture.disposeCount, 1);
    expect(gateway.closeCount, 1);
  });

  test('malformed gateway event fails closed and cleans up once', () async {
    final capture = _FakeCapture();
    late _FakeGatewayConnection gateway;
    gateway = _FakeGatewayConnection(
      onText: (value) {
        if (value['type'] == 'start') {
          scheduleMicrotask(() => gateway.emit(_ready(value)));
        }
      },
    );
    final session = await _service(
      capture: capture,
      connector: (_, _) async => gateway,
    ).start(VoiceInputMode.ordinary);
    final eventsFuture = session.events.toList();

    gateway.emit({
      'type': 'partial',
      'voiceSessionId': 'session-1',
      'text': 'missing sequence',
    });
    final events = await eventsFuture;

    expect(events.single, isA<VoiceInputFailure>());
    expect(
      (events.single as VoiceInputFailure).code,
      VoiceInputErrorCode.protocolError,
    );
    expect(capture.stopCount, 1);
    expect(capture.disposeCount, 1);
    expect(gateway.closeCount, 1);
    await session.dispose();
    expect(capture.stopCount, 1);
    expect(capture.disposeCount, 1);
    expect(gateway.closeCount, 1);
  });

  test(
    'cancel discards buffered audio and suppresses late old-session events',
    () async {
      final capture = _FakeCapture();
      final gateway = _FakeGatewayConnection(onText: _readyOnStart);
      final session = await _service(
        capture: capture,
        connector: (_, _) async => gateway,
      ).start(VoiceInputMode.reka);
      final eventsFuture = session.events.toList();

      capture.add([0, 1, 2, 3]);
      await session.cancel();
      gateway.emit({
        'type': 'final',
        'voiceSessionId': 'session-1',
        'sequence': 1,
        'text': 'must be ignored',
        'audioDurationMs': 10,
      });

      expect(await eventsFuture, isEmpty);
      expect(gateway.sentBytes, isEmpty);
      expect(gateway.sentText.last, {
        'type': 'cancel',
        'voiceSessionId': 'session-1',
      });
      expect(capture.stopCount, 1);
      expect(capture.disposeCount, 1);
      expect(gateway.closeCount, 1);
    },
  );

  test(
    'safe gateway errors are normalized without transcript content',
    () async {
      final capture = _FakeCapture();
      final gateway = _FakeGatewayConnection(onText: _readyOnStart);
      final session = await _service(
        capture: capture,
        connector: (_, _) async => gateway,
      ).start(VoiceInputMode.ordinary);
      final eventFuture = session.events.first;

      gateway.emit({
        'type': 'error',
        'voiceSessionId': 'session-1',
        'code': 'rate_limited',
        'retryable': true,
      });
      final event = await eventFuture;

      expect(
        event,
        const VoiceInputFailure(
          code: VoiceInputErrorCode.rateLimited,
          retryable: true,
        ),
      );
    },
  );
}

VoiceInputService _service({
  required _FakeCapture capture,
  required VoiceGatewayConnector connector,
  String apiBase = 'https://api.example.test',
}) {
  return VoiceInputService(
    captureFactory: () => capture,
    connector: connector,
    apiBase: apiBase,
    tokenProvider: () => 'test-token',
    sessionIdFactory: () => 'session-1',
  );
}

Map<String, Object?> _ready(Map<String, Object?> start) => {
  'type': 'ready',
  'voiceSessionId': start['voiceSessionId'],
};

void _readyOnStart(Map<String, Object?> value) {
  final gateway = _FakeGatewayConnection.current;
  if (value['type'] == 'start' && gateway != null) {
    scheduleMicrotask(() => gateway.emit(_ready(value)));
  }
}

class _FakeCapture implements VoiceAudioCapture {
  _FakeCapture({
    this.permission = true,
    this.permissionCompleter,
    this.startCompleter,
    this.stopCompleter,
    this.bytesOnStop,
  });

  final bool permission;
  final Completer<bool>? permissionCompleter;
  final Completer<Stream<Uint8List>>? startCompleter;
  final Completer<void>? stopCompleter;
  final List<int>? bytesOnStop;
  final StreamController<Uint8List> _audio = StreamController<Uint8List>();
  int permissionChecks = 0;
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  void add(List<int> value) => _audio.add(Uint8List.fromList(value));

  @override
  Future<bool> hasPermission() async {
    permissionChecks += 1;
    final pending = permissionCompleter;
    if (pending != null) return pending.future;
    return permission;
  }

  @override
  Future<Stream<Uint8List>> startPcm16() async {
    startCount += 1;
    final pending = startCompleter;
    if (pending != null) return pending.future;
    return _audio.stream;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    final pending = stopCompleter;
    if (pending != null) return pending.future;
    final trailing = bytesOnStop;
    if (trailing != null && !_audio.isClosed) add(trailing);
    if (!_audio.isClosed) {
      final closing = _audio.close();
      if (startCount > 0) await closing;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    if (!_audio.isClosed) {
      final closing = _audio.close();
      if (startCount > 0) await closing;
    }
  }
}

class _FakeGatewayConnection implements VoiceGatewayConnection {
  _FakeGatewayConnection({this.onText, this.throwOnText = false}) {
    current = this;
  }

  static _FakeGatewayConnection? current;
  final void Function(Map<String, Object?> value)? onText;
  final bool throwOnText;
  final StreamController<Object?> _events = StreamController<Object?>();
  final List<Map<String, Object?>> sentText = [];
  final List<Uint8List> sentBytes = [];
  int closeCount = 0;

  void emit(Map<String, Object?> value) {
    if (!_events.isClosed) _events.add(jsonEncode(value));
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  void sendText(String value) {
    if (throwOnText) throw StateError('synthetic send failure');
    final decoded = (jsonDecode(value) as Map).cast<String, Object?>();
    sentText.add(decoded);
    onText?.call(decoded);
  }

  @override
  void sendBytes(Uint8List value) => sentBytes.add(Uint8List.fromList(value));

  @override
  Future<void> close() async {
    closeCount += 1;
    if (!_events.isClosed) unawaited(_events.close());
  }
}
