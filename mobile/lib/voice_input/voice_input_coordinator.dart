import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_input_models.dart';
import 'voice_input_service.dart';

enum VoiceInputCoordinatorState { idle, connecting, listening, finalizing }

enum VoiceInputCancelReason {
  user,
  superseded,
  disposed,
  appLifecycle,
  authentication,
  coordinatorDisposed,
}

final class VoiceInputTargetCallbacks {
  const VoiceInputTargetCallbacks({
    required this.onActivated,
    required this.onTranscript,
    required this.onCancelled,
    required this.onFailure,
  });

  final VoidCallback onActivated;
  final ValueChanged<VoiceTranscriptEvent> onTranscript;
  final ValueChanged<VoiceInputCancelReason> onCancelled;
  final ValueChanged<VoiceInputErrorCode> onFailure;
}

final class VoiceInputTargetBinding extends ChangeNotifier {
  VoiceInputTargetBinding._({
    required VoiceInputCoordinator coordinator,
    required this.targetId,
    required this.mode,
    required VoiceInputTargetCallbacks callbacks,
  }) : _coordinator = coordinator,
       _callbacks = callbacks;

  final VoiceInputCoordinator _coordinator;
  final Object targetId;
  final VoiceInputMode mode;
  final VoiceInputTargetCallbacks _callbacks;

  VoiceInputCoordinatorState _state = VoiceInputCoordinatorState.idle;
  VoiceInputErrorCode? _errorCode;
  String? _voiceSessionId;
  int _generation = 0;
  bool _disposed = false;

  VoiceInputCoordinatorState get state => _state;
  VoiceInputErrorCode? get errorCode => _errorCode;
  String? get voiceSessionId => _voiceSessionId;
  bool get isActive => _state != VoiceInputCoordinatorState.idle;
  bool get isDisposed => _disposed;

  Future<bool> start() => _coordinator._start(this);

  Future<void> stop() => _coordinator._stop(this);

  Future<void> cancel() =>
      _coordinator._cancelBinding(this, VoiceInputCancelReason.user);

  Future<void> close() async {
    if (_disposed) return;
    final cleanup = _coordinator._cancelBinding(
      this,
      VoiceInputCancelReason.disposed,
    );
    _disposed = true;
    super.dispose();
    await cleanup;
  }

  @override
  void dispose() {
    if (_disposed) return;
    final cleanup = _coordinator._cancelBinding(
      this,
      VoiceInputCancelReason.disposed,
    );
    _disposed = true;
    super.dispose();
    unawaited(cleanup);
  }

  void _activate(int generation) {
    if (_disposed) return;
    _generation = generation;
    _errorCode = null;
    _voiceSessionId = null;
    _setState(VoiceInputCoordinatorState.connecting);
    _safeCall(_callbacks.onActivated);
  }

  void _setState(VoiceInputCoordinatorState value) {
    _state = value;
    if (!_disposed) notifyListeners();
  }

  void _cancelled(VoiceInputCancelReason reason) {
    _voiceSessionId = null;
    _setState(VoiceInputCoordinatorState.idle);
    _safeCall(() => _callbacks.onCancelled(reason));
  }

  void _failed(VoiceInputErrorCode code) {
    _voiceSessionId = null;
    _errorCode = code;
    _setState(VoiceInputCoordinatorState.idle);
    _safeCall(() => _callbacks.onFailure(code));
  }

  void _transcript(VoiceTranscriptEvent event) {
    _safeCall(() => _callbacks.onTranscript(event));
  }
}

final class VoiceInputCoordinator {
  VoiceInputCoordinator({
    required VoiceInputServiceClient service,
    this.finalTimeout = const Duration(seconds: 10),
  }) : _service = service;

  final VoiceInputServiceClient _service;
  final Duration finalTimeout;

  VoiceInputTargetBinding? _activeBinding;
  VoiceInputSessionHandle? _activeSession;
  StreamSubscription<VoiceInputEvent>? _activeSubscription;
  Timer? _finalTimer;
  Future<void> _operationTail = Future<void>.value();
  int _generation = 0;
  int _latestStartRequest = 0;
  bool _disposed = false;

  VoiceInputTargetBinding? get activeBinding => _activeBinding;

  VoiceInputTargetBinding bind({
    required Object targetId,
    required VoiceInputMode mode,
    required VoiceInputTargetCallbacks callbacks,
  }) {
    if (_disposed) throw StateError('VoiceInputCoordinator is disposed');
    return VoiceInputTargetBinding._(
      coordinator: this,
      targetId: targetId,
      mode: mode,
      callbacks: callbacks,
    );
  }

  Future<bool> _start(VoiceInputTargetBinding binding) {
    if (_disposed || binding._disposed) return Future<bool>.value(false);
    if (identical(_activeBinding, binding)) {
      return Future<bool>.value(false);
    }

    final request = ++_latestStartRequest;
    final previousCleanup = _invalidateActive(
      VoiceInputCancelReason.superseded,
      notifyCancellation: true,
    );
    final cleanupFuture = previousCleanup == null
        ? Future<void>.value()
        : _beginCleanup(previousCleanup, cancel: true);

    final generation = ++_generation;
    _activeBinding = binding;
    binding._activate(generation);

    return _serialize<bool>(() async {
      await cleanupFuture;
      if (!_matches(binding, generation) || request != _latestStartRequest) {
        return false;
      }

      VoiceInputSessionHandle session;
      try {
        session = await _service.start(binding.mode);
      } on VoiceInputException catch (error) {
        if (_matches(binding, generation)) {
          _failActive(binding, generation, error.code);
        }
        return false;
      } catch (_) {
        if (_matches(binding, generation)) {
          _failActive(
            binding,
            generation,
            VoiceInputErrorCode.connectionFailed,
          );
        }
        return false;
      }

      if (!_matches(binding, generation) || request != _latestStartRequest) {
        await _cancelSession(session);
        return false;
      }

      _activeSession = session;
      binding._voiceSessionId = session.voiceSessionId;
      _activeSubscription = session.events.listen(
        (event) => _onEvent(binding, generation, session.voiceSessionId, event),
        onError: (_) => _failActive(
          binding,
          generation,
          VoiceInputErrorCode.connectionLost,
        ),
        onDone: () {
          if (_matches(binding, generation)) {
            _failActive(
              binding,
              generation,
              VoiceInputErrorCode.connectionLost,
            );
          }
        },
        cancelOnError: false,
      );
      binding._setState(VoiceInputCoordinatorState.listening);
      return true;
    });
  }

  Future<void> _stop(VoiceInputTargetBinding binding) async {
    final generation = binding._generation;
    if (!_matches(binding, generation) ||
        binding.state != VoiceInputCoordinatorState.listening) {
      return;
    }
    final session = _activeSession;
    if (session == null) return;

    binding._setState(VoiceInputCoordinatorState.finalizing);
    try {
      await session.stop();
      if (!_matches(binding, generation)) return;
      _finalTimer?.cancel();
      _finalTimer = Timer(finalTimeout, () {
        _failActive(binding, generation, VoiceInputErrorCode.connectionLost);
      });
    } catch (_) {
      if (_matches(binding, generation)) {
        _failActive(binding, generation, VoiceInputErrorCode.connectionLost);
      }
    }
  }

  Future<void> _cancelBinding(
    VoiceInputTargetBinding binding,
    VoiceInputCancelReason reason,
  ) {
    if (!identical(_activeBinding, binding)) return Future<void>.value();
    _latestStartRequest++;
    final resources = _invalidateActive(reason, notifyCancellation: true);
    return resources == null
        ? Future<void>.value()
        : _beginCleanup(resources, cancel: true);
  }

  Future<void> cancelActive(VoiceInputCancelReason reason) {
    if (_activeBinding == null) return Future<void>.value();
    _latestStartRequest++;
    final resources = _invalidateActive(reason, notifyCancellation: true);
    return resources == null
        ? Future<void>.value()
        : _beginCleanup(resources, cancel: true);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _latestStartRequest++;
    final resources = _invalidateActive(
      VoiceInputCancelReason.coordinatorDisposed,
      notifyCancellation: true,
    );
    if (resources != null) await _beginCleanup(resources, cancel: true);
    await _operationTail;
  }

  void _onEvent(
    VoiceInputTargetBinding binding,
    int generation,
    String voiceSessionId,
    VoiceInputEvent event,
  ) {
    if (!_matches(binding, generation) ||
        _activeSession?.voiceSessionId != voiceSessionId) {
      return;
    }
    if (event is VoiceInputFailure) {
      _failActive(binding, generation, event.code);
      return;
    }
    if (event is! VoiceTranscriptEvent) return;

    if (event.kind != VoiceTranscriptKind.finalTranscript) {
      binding._transcript(event);
      return;
    }

    try {
      binding._transcript(event);
    } finally {
      final resources = _invalidateActive(null, notifyCancellation: false);
      if (resources != null) {
        unawaited(_beginCleanup(resources, cancel: false));
      }
    }
  }

  void _failActive(
    VoiceInputTargetBinding binding,
    int generation,
    VoiceInputErrorCode code,
  ) {
    if (!_matches(binding, generation)) return;
    final resources = _invalidateActive(null, notifyCancellation: false);
    binding._failed(code);
    if (resources != null) unawaited(_beginCleanup(resources, cancel: true));
  }

  _VoiceInputResources? _invalidateActive(
    VoiceInputCancelReason? reason, {
    required bool notifyCancellation,
  }) {
    final binding = _activeBinding;
    if (binding == null) return null;
    final resources = _VoiceInputResources(
      session: _activeSession,
      subscription: _activeSubscription,
      interruptServiceStart: _activeSession == null,
    );
    _generation++;
    _activeBinding = null;
    _activeSession = null;
    _activeSubscription = null;
    _finalTimer?.cancel();
    _finalTimer = null;
    if (notifyCancellation && reason != null) {
      binding._cancelled(reason);
    } else {
      binding._setState(VoiceInputCoordinatorState.idle);
      binding._voiceSessionId = null;
    }
    return resources;
  }

  bool _matches(VoiceInputTargetBinding binding, int generation) {
    return !_disposed &&
        !binding._disposed &&
        identical(_activeBinding, binding) &&
        binding._generation == generation;
  }

  Future<void> _beginCleanup(
    _VoiceInputResources resources, {
    required bool cancel,
  }) async {
    final session = resources.session;
    if (session != null) {
      try {
        if (cancel) {
          await session.cancel();
        } else {
          await session.dispose();
        }
      } catch (_) {}
    } else if (resources.interruptServiceStart &&
        _service is VoiceInputServiceCancellation) {
      try {
        await (_service as VoiceInputServiceCancellation).cancelActive();
      } catch (_) {}
    }
    try {
      await resources.subscription?.cancel();
    } catch (_) {}
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _VoiceInputResources {
  const _VoiceInputResources({
    required this.session,
    required this.subscription,
    required this.interruptServiceStart,
  });

  final VoiceInputSessionHandle? session;
  final StreamSubscription<VoiceInputEvent>? subscription;
  final bool interruptServiceStart;
}

Future<void> _cancelSession(VoiceInputSessionHandle session) async {
  try {
    await session.cancel();
  } catch (_) {}
}

void _safeCall(VoidCallback callback) {
  try {
    callback();
  } catch (_) {}
}
