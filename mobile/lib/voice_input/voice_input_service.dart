import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../api/auth_store.dart';
import '../config.dart';
import 'voice_audio_capture.dart';
import 'voice_gateway.dart';
import 'voice_input_models.dart';

typedef VoiceAudioCaptureFactory = VoiceAudioCapture Function();
typedef VoiceTokenProvider = String? Function();
typedef VoiceSessionIdFactory = String Function();

abstract interface class VoiceInputServiceClient {
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode);
}

abstract interface class VoiceInputServiceCancellation {
  Future<void> cancelActive();
}

abstract interface class VoiceInputSessionHandle {
  String get voiceSessionId;
  VoiceInputMode get mode;
  Stream<VoiceInputEvent> get events;

  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

final class PcmFrameChunker {
  PcmFrameChunker({this.frameBytes = 6400}) {
    if (frameBytes <= 0 || frameBytes.isOdd) {
      throw ArgumentError.value(frameBytes, 'frameBytes');
    }
  }

  final int frameBytes;
  final List<int> _pending = <int>[];

  List<Uint8List> add(Uint8List value) {
    _pending.addAll(value);
    final frames = <Uint8List>[];
    while (_pending.length >= frameBytes) {
      frames.add(Uint8List.fromList(_pending.sublist(0, frameBytes)));
      _pending.removeRange(0, frameBytes);
    }
    return frames;
  }

  Uint8List? flush() {
    final completeLength = _pending.length - (_pending.length % 2);
    if (completeLength == 0) {
      _pending.clear();
      return null;
    }
    final value = Uint8List.fromList(_pending.sublist(0, completeLength));
    _pending.clear();
    return value;
  }

  void clear() => _pending.clear();
}

final class VoiceInputService
    implements VoiceInputServiceClient, VoiceInputServiceCancellation {
  VoiceInputService({
    VoiceAudioCaptureFactory? captureFactory,
    VoiceGatewayConnector? connector,
    String? apiBase,
    VoiceTokenProvider? tokenProvider,
    VoiceSessionIdFactory? sessionIdFactory,
    this.readyTimeout = const Duration(seconds: 10),
    this.connectionTimeout = const Duration(seconds: 10),
    this.cleanupTimeout = const Duration(seconds: 2),
  }) : _captureFactory = captureFactory ?? RecordVoiceAudioCapture.new,
       _connector = connector ?? connectVoiceGateway,
       _apiBase = apiBase ?? AppConfig.apiBase,
       _tokenProvider = tokenProvider ?? (() => AuthStore.token),
       _sessionIdFactory = sessionIdFactory ?? _newSessionId;

  final VoiceAudioCaptureFactory _captureFactory;
  final VoiceGatewayConnector _connector;
  final String _apiBase;
  final VoiceTokenProvider _tokenProvider;
  final VoiceSessionIdFactory _sessionIdFactory;
  final Duration readyTimeout;
  final Duration connectionTimeout;
  final Duration cleanupTimeout;

  VoiceInputSession? _active;
  bool _starting = false;
  Completer<void>? _pendingStartCancellation;
  Completer<void>? _pendingStartDone;

  @override
  Future<void> cancelActive() async {
    final pendingCancellation = _pendingStartCancellation;
    final pendingDone = _pendingStartDone;
    if (pendingCancellation != null && !pendingCancellation.isCompleted) {
      pendingCancellation.complete();
    }
    final active = _active;
    if (active != null) await active.cancel();
    if (pendingDone != null && !pendingDone.isCompleted) {
      await _ignoreWithin(pendingDone.future, cleanupTimeout);
    }
  }

  @override
  Future<VoiceInputSession> start(VoiceInputMode mode) async {
    if (_starting || (_active != null && !_active!.isTerminal)) {
      throw const VoiceInputException(VoiceInputErrorCode.busy);
    }
    _starting = true;
    final pendingCancellation = Completer<void>();
    final pendingDone = Completer<void>();
    _pendingStartCancellation = pendingCancellation;
    _pendingStartDone = pendingDone;
    final capture = _captureFactory();
    VoiceGatewayConnection? gateway;
    try {
      final permitted = await _awaitPendingStartPhase<bool>(
        Future<bool>.sync(capture.hasPermission),
        pendingCancellation.future,
        connectionTimeout,
      );
      if (!permitted) {
        throw const VoiceInputException(VoiceInputErrorCode.permissionDenied);
      }

      final token = _tokenProvider()?.trim();
      if (token == null || token.isEmpty) {
        throw const VoiceInputException(VoiceInputErrorCode.unauthenticated);
      }

      final uri = voiceGatewayUri(_apiBase);
      final connectionFuture = Future<VoiceGatewayConnection>.sync(
        () => _connector(uri, {'Authorization': 'Bearer $token'}),
      );
      try {
        gateway = await Future.any<VoiceGatewayConnection>([
          connectionFuture,
          pendingCancellation.future.then<VoiceGatewayConnection>(
            (_) => throw const _PendingStartCancelled(),
          ),
        ]).timeout(connectionTimeout);
      } on _PendingStartCancelled {
        _closeLateGateway(connectionFuture, cleanupTimeout);
        throw const VoiceInputException(
          VoiceInputErrorCode.connectionFailed,
          retryable: true,
        );
      } on TimeoutException {
        _closeLateGateway(connectionFuture, cleanupTimeout);
        throw const VoiceInputException(
          VoiceInputErrorCode.connectionFailed,
          retryable: true,
        );
      } catch (_) {
        _closeLateGateway(connectionFuture, cleanupTimeout);
        throw const VoiceInputException(
          VoiceInputErrorCode.connectionFailed,
          retryable: true,
        );
      }

      late final VoiceInputSession session;
      session = VoiceInputSession._(
        voiceSessionId: _sessionIdFactory(),
        mode: mode,
        capture: capture,
        gateway: gateway,
        readyTimeout: readyTimeout,
        captureStartTimeout: connectionTimeout,
        cleanupTimeout: cleanupTimeout,
        onTerminal: () {
          if (identical(_active, session)) _active = null;
        },
      );
      _active = session;
      await session._start();
      return session;
    } on VoiceInputException {
      if (gateway == null) {
        await _ignoreWithin(capture.dispose(), cleanupTimeout);
      }
      rethrow;
    } catch (_) {
      if (gateway == null) {
        await _ignoreWithin(capture.dispose(), cleanupTimeout);
      }
      throw const VoiceInputException(
        VoiceInputErrorCode.connectionFailed,
        retryable: true,
      );
    } finally {
      _starting = false;
      if (identical(_pendingStartCancellation, pendingCancellation)) {
        _pendingStartCancellation = null;
      }
      if (identical(_pendingStartDone, pendingDone)) {
        _pendingStartDone = null;
      }
      if (!pendingDone.isCompleted) pendingDone.complete();
    }
  }
}

final class VoiceInputSession implements VoiceInputSessionHandle {
  VoiceInputSession._({
    required this.voiceSessionId,
    required this.mode,
    required VoiceAudioCapture capture,
    required VoiceGatewayConnection gateway,
    required Duration readyTimeout,
    required Duration captureStartTimeout,
    required Duration cleanupTimeout,
    required void Function() onTerminal,
  }) : _capture = capture,
       _gateway = gateway,
       _readyTimeout = readyTimeout,
       _captureStartTimeout = captureStartTimeout,
       _cleanupTimeout = cleanupTimeout,
       _onTerminal = onTerminal;

  @override
  final String voiceSessionId;
  @override
  final VoiceInputMode mode;
  final VoiceAudioCapture _capture;
  final VoiceGatewayConnection _gateway;
  final Duration _readyTimeout;
  final Duration _captureStartTimeout;
  final Duration _cleanupTimeout;
  final void Function() _onTerminal;
  final PcmFrameChunker _chunker = PcmFrameChunker();
  final StreamController<VoiceInputEvent> _events =
      StreamController<VoiceInputEvent>();
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _audioDone = Completer<void>();
  final Completer<void> _startCancellation = Completer<void>();

  StreamSubscription<Object?>? _gatewaySubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  int _lastSequence = 0;
  bool _recording = false;
  bool _stopping = false;
  bool _terminal = false;
  Future<void>? _captureStopFuture;
  Future<void>? _cleanupFuture;

  @override
  Stream<VoiceInputEvent> get events => _events.stream;
  bool get isTerminal => _terminal;

  Future<void> _start() async {
    try {
      _gatewaySubscription = _gateway.events.listen(
        _onGatewayData,
        onError: (_) => unawaited(
          _fail(VoiceInputErrorCode.connectionLost, retryable: true),
        ),
        onDone: () {
          if (!_terminal) {
            unawaited(
              _fail(VoiceInputErrorCode.connectionLost, retryable: true),
            );
          }
        },
        cancelOnError: false,
      );
      _gateway.sendText(
        jsonEncode({
          'type': 'start',
          'voiceSessionId': voiceSessionId,
          'mode': mode.wireName,
          'audio': {
            'encoding': 'pcm_s16le',
            'sampleRate': 16000,
            'channels': 1,
          },
        }),
      );
      await _ready.future.timeout(_readyTimeout);
      if (_terminal) {
        throw const VoiceInputException(
          VoiceInputErrorCode.connectionFailed,
          retryable: true,
        );
      }
      final audioStart = Future<Stream<Uint8List>>.sync(_capture.startPcm16);
      late final Stream<Uint8List> audio;
      try {
        audio = await _awaitPendingStartPhase<Stream<Uint8List>>(
          audioStart,
          _startCancellation.future,
          _captureStartTimeout,
        );
      } on _PendingStartCancelled {
        _cancelLateAudioStream(audioStart, _cleanupTimeout);
        rethrow;
      } on TimeoutException {
        _cancelLateAudioStream(audioStart, _cleanupTimeout);
        rethrow;
      }
      if (_terminal) throw const _PendingStartCancelled();
      _recording = true;
      _audioSubscription = audio.listen(
        _onAudio,
        onError: (_) {
          if (!_audioDone.isCompleted) _audioDone.complete();
          unawaited(
            _fail(VoiceInputErrorCode.unsupportedAudio, retryable: false),
          );
        },
        onDone: () {
          if (!_audioDone.isCompleted) _audioDone.complete();
        },
        cancelOnError: false,
      );
    } on _PendingStartCancelled {
      await _cleanup();
      throw const VoiceInputException(
        VoiceInputErrorCode.connectionFailed,
        retryable: true,
      );
    } on VoiceInputException {
      await _cleanup();
      rethrow;
    } on TimeoutException {
      await _abortStart();
      throw const VoiceInputException(
        VoiceInputErrorCode.connectionFailed,
        retryable: true,
      );
    } catch (_) {
      final code = _ready.isCompleted
          ? VoiceInputErrorCode.unsupportedAudio
          : VoiceInputErrorCode.connectionFailed;
      await _abortStart();
      throw VoiceInputException(
        code,
        retryable: code == VoiceInputErrorCode.connectionFailed,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_terminal || _stopping) return;
    _stopping = true;
    try {
      await _stopCaptureOnce().timeout(_cleanupTimeout);
      await _audioDone.future.timeout(_cleanupTimeout);
      if (_terminal) return;
      final trailing = _chunker.flush();
      if (trailing != null) _gateway.sendBytes(trailing);
      _gateway.sendText(
        jsonEncode({'type': 'stop', 'voiceSessionId': voiceSessionId}),
      );
    } catch (_) {
      await _fail(VoiceInputErrorCode.unsupportedAudio, retryable: false);
    }
  }

  @override
  Future<void> cancel() async {
    if (_terminal) {
      await _cleanup();
      return;
    }
    _terminal = true;
    _cancelPendingSessionStart();
    _chunker.clear();
    if (!_ready.isCompleted) {
      _ready.completeError(
        const VoiceInputException(
          VoiceInputErrorCode.connectionFailed,
          retryable: true,
        ),
      );
    }
    try {
      await _ignoreWithin(_stopCaptureOnce(), _cleanupTimeout);
      _gateway.sendText(
        jsonEncode({'type': 'cancel', 'voiceSessionId': voiceSessionId}),
      );
    } catch (_) {
      // Cancellation is best effort; cleanup below remains authoritative.
    }
    await _cleanup();
    await _closeEvents();
    _onTerminal();
  }

  @override
  Future<void> dispose() => cancel();

  void _onAudio(Uint8List value) {
    if (_terminal || !_recording) return;
    try {
      for (final frame in _chunker.add(value)) {
        _gateway.sendBytes(frame);
      }
    } catch (_) {
      unawaited(_fail(VoiceInputErrorCode.connectionLost, retryable: true));
    }
  }

  void _onGatewayData(Object? raw) {
    if (_terminal) return;
    try {
      if (raw is! String) throw const FormatException();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final event = decoded.cast<String, Object?>();
      if (event['voiceSessionId'] != voiceSessionId) return;
      final type = event['type'];

      if (type == 'ready') {
        if (_ready.isCompleted) throw const FormatException();
        _ready.complete();
        return;
      }
      if (type == 'error') {
        final code = _parseErrorCode(event['code']);
        final retryable = event['retryable'];
        if (code == null || retryable is! bool) throw const FormatException();
        unawaited(_fail(code, retryable: retryable));
        return;
      }
      if (!_ready.isCompleted) throw const FormatException();

      final sequence = event['sequence'];
      final text = event['text'];
      if (sequence is! int ||
          sequence <= 0 ||
          text is! String ||
          text.trim().isEmpty) {
        throw const FormatException();
      }
      if (sequence <= _lastSequence) return;
      _lastSequence = sequence;
      final kind = switch (type) {
        'partial' => VoiceTranscriptKind.partial,
        'stable' => VoiceTranscriptKind.stable,
        'final' => VoiceTranscriptKind.finalTranscript,
        _ => throw const FormatException(),
      };
      int? duration;
      if (kind == VoiceTranscriptKind.finalTranscript) {
        final value = event['audioDurationMs'];
        if (value is! int || value < 0) throw const FormatException();
        duration = value;
      }
      _events.add(
        VoiceTranscriptEvent(
          kind: kind,
          sequence: sequence,
          text: text,
          audioDurationMs: duration,
        ),
      );
      if (kind == VoiceTranscriptKind.finalTranscript) {
        unawaited(_complete());
      }
    } on FormatException {
      unawaited(_fail(VoiceInputErrorCode.protocolError, retryable: false));
    } catch (_) {
      unawaited(_fail(VoiceInputErrorCode.protocolError, retryable: false));
    }
  }

  Future<void> _complete() async {
    if (_terminal) return;
    _terminal = true;
    _cancelPendingSessionStart();
    await _cleanup();
    await _closeEvents();
    _onTerminal();
  }

  Future<void> _fail(
    VoiceInputErrorCode code, {
    required bool retryable,
  }) async {
    if (_terminal) return;
    _terminal = true;
    _cancelPendingSessionStart();
    if (!_ready.isCompleted) {
      _ready.completeError(VoiceInputException(code, retryable: retryable));
    } else if (!_events.isClosed) {
      _events.add(VoiceInputFailure(code: code, retryable: retryable));
    }
    await _cleanup();
    await _closeEvents();
    _onTerminal();
  }

  Future<void> _stopCaptureOnce() async {
    return _captureStopFuture ??= _performCaptureStop();
  }

  Future<void> _performCaptureStop() async {
    try {
      await _capture.stop();
    } finally {
      _recording = false;
    }
  }

  Future<void> _cleanup() {
    return _cleanupFuture ??= _performCleanup();
  }

  Future<void> _performCleanup() async {
    if (!_audioDone.isCompleted) _audioDone.complete();
    await Future.wait<void>([
      _ignoreWithin(_stopCaptureOnce(), _cleanupTimeout),
      _ignoreWithin(
        _audioSubscription?.cancel() ?? Future<void>.value(),
        _cleanupTimeout,
      ),
      _ignoreWithin(
        _gatewaySubscription?.cancel() ?? Future<void>.value(),
        _cleanupTimeout,
      ),
      _ignoreWithin(_capture.dispose(), _cleanupTimeout),
      _ignoreWithin(_gateway.close(), _cleanupTimeout),
    ]);
  }

  Future<void> _abortStart() async {
    if (!_terminal) _terminal = true;
    _cancelPendingSessionStart();
    await _cleanup();
    await _closeEvents();
    _onTerminal();
  }

  Future<void> _closeEvents() async {
    // A single-subscription controller intentionally buffers events until the
    // UI attaches. Awaiting close before that first listen would never finish.
    if (!_events.isClosed) unawaited(_events.close());
  }

  void _cancelPendingSessionStart() {
    if (!_startCancellation.isCompleted) {
      _startCancellation.complete();
    }
  }
}

final class _PendingStartCancelled implements Exception {
  const _PendingStartCancelled();
}

Future<T> _awaitPendingStartPhase<T>(
  Future<T> operation,
  Future<void> cancellation,
  Duration timeout,
) {
  return Future.any<T>([
    operation,
    cancellation.then<T>((_) => throw const _PendingStartCancelled()),
  ]).timeout(timeout);
}

void _closeLateGateway(
  Future<VoiceGatewayConnection> connection,
  Duration timeout,
) {
  unawaited(
    connection.then<void>(
      (gateway) => unawaited(_ignoreWithin(gateway.close(), timeout)),
      onError: (Object _, StackTrace _) {},
    ),
  );
}

void _cancelLateAudioStream(
  Future<Stream<Uint8List>> audioStart,
  Duration timeout,
) {
  unawaited(
    audioStart.then<void>((audio) async {
      try {
        final subscription = audio.listen((_) {});
        await _ignoreWithin(subscription.cancel(), timeout);
      } catch (_) {}
    }, onError: (Object _, StackTrace _) {}),
  );
}

Future<void> _ignoreWithin(Future<void> future, Duration timeout) async {
  try {
    await future.timeout(timeout);
  } catch (_) {}
}

VoiceInputErrorCode? _parseErrorCode(Object? value) => switch (value) {
  'connection_failed' => VoiceInputErrorCode.connectionFailed,
  'connection_lost' => VoiceInputErrorCode.connectionLost,
  'rate_limited' => VoiceInputErrorCode.rateLimited,
  'no_speech' => VoiceInputErrorCode.noSpeech,
  'service_unavailable' => VoiceInputErrorCode.serviceUnavailable,
  'unsupported_audio' => VoiceInputErrorCode.unsupportedAudio,
  _ => null,
};

String _newSessionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
