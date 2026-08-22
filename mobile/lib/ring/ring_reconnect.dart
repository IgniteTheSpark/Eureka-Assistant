import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class RingReconnectGateway {
  Stream<RingState> get state;

  Future<void> startScan(String targetId);

  Future<void> stopScan();

  Future<void> connect(String id);

  Future<void> disconnect();

  Future<void> startBackgroundSession();

  Future<void> stopBackgroundSession();
}

abstract interface class RingReconnectBindingStore {
  Future<String?> readMac();
}

typedef RingReconnectConnectedCallback = FutureOr<void> Function();

/// Keeps the ring connected by SCANNING for the saved MAC and connecting when it
/// appears — the same robust pattern the card uses (DeviceSilentReconnect).
///
/// reconnectionLockByBLE() alone is unreliable after the app process is killed
/// (it relies on the SDK's in-memory "last device", which is gone on cold start),
/// so on launch / after a drop we actively scan and connect by MAC instead.
///
/// Singleton so the pairing page can [pause] it while the user manually scans
/// (two scanners on one BLE stack would fight), then [resume] on exit.
class RingReconnect {
  RingReconnect({
    required RingReconnectGateway gateway,
    required RingReconnectBindingStore bindingStore,
    this.onConnected,
  }) : _gateway = gateway,
       _bindingStore = bindingStore;

  RingReconnect._production()
    : _gateway = _ChipletRingReconnectGateway(ChipletRing()),
      _bindingStore = const _SharedPreferencesRingReconnectBindingStore();

  static final RingReconnect instance = RingReconnect._production();

  final RingReconnectGateway _gateway;
  final RingReconnectBindingStore _bindingStore;
  RingReconnectConnectedCallback? onConnected;
  StreamSubscription<RingState>? _sub;
  Timer? _retryTimer;
  Timer? _scanTimer;
  int _backoff = 3; // seconds between retry rounds
  int _operationRevision = 0;
  String? _mac;
  bool _connected = false;
  bool _connecting = false;
  bool _scanning = false;
  bool _paused = false;
  bool _backgroundSessionActive = false;

  /// Begin keeping the ring connected. Idempotent.
  Future<void> start() async {
    final revision = ++_operationRevision;
    _sub ??= _gateway.state.listen(_onState);
    final mac = await _bindingStore.readMac();
    if (revision != _operationRevision) return;
    _mac = mac;
    await _syncBackgroundSessionBestEffort();
    if (revision != _operationRevision) return;
    _ensureReconnecting();
  }

  bool get _hasMac => _mac != null && _mac!.isNotEmpty;

  /// Refresh the saved MAC (call after a fresh pairing).
  Future<void> refreshMac() async {
    final revision = ++_operationRevision;
    final mac = await _bindingStore.readMac();
    if (revision != _operationRevision) return;
    _mac = mac;
    await _syncBackgroundSessionBestEffort();
    if (revision != _operationRevision) return;
    _ensureReconnecting();
  }

  /// Forget the saved ring (on unbind): clear the in-memory MAC and stop all
  /// reconnect activity so it won't auto-reconnect until a new pairing. The
  /// caller is responsible for removing 'ring_mac' from prefs (for cold start).
  void forget() {
    _operationRevision++;
    _mac = null;
    unawaited(_stopBackgroundSession());
    _stopScan();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Pause auto-reconnect (e.g. while the pairing page does its own scan).
  void pause() {
    _operationRevision++;
    _paused = true;
    _stopScan();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Resume auto-reconnect after the pairing page closes. Re-reads the saved MAC
  /// (it may have changed if the user just paired a different ring).
  void resume() {
    _paused = false;
    final revision = ++_operationRevision;
    unawaited(_resumeFromSavedMac(revision));
  }

  Future<void> _resumeFromSavedMac(int revision) async {
    try {
      final mac = await _bindingStore.readMac();
      if (revision != _operationRevision) return;
      _mac = mac;
      await _syncBackgroundSessionBestEffort();
      if (revision != _operationRevision) return;
      _ensureReconnecting();
    } catch (_) {
      // Resume is best effort and must not create an unhandled async error.
    }
  }

  void _onState(RingState state) {
    final nowConnected = state.conn == RingConnState.connected;
    final wasConnected = _connected;
    // While scanning for reconnect, connect as soon as the saved ring shows up.
    if (!nowConnected &&
        _scanning &&
        !_connecting &&
        _hasMac &&
        state.devices.any((device) => device.id == _mac)) {
      _stopScan();
      _beginConnect(_mac!);
    }
    _connected = nowConnected;
    if (_connected) {
      _backoff = 3;
      _stopScan();
      _retryTimer?.cancel();
      _retryTimer = null;
      if (!wasConnected) _notifyConnected();
    } else {
      _ensureReconnecting(); // (re)start scanning toward the saved ring
    }
  }

  void _notifyConnected() {
    final callback = onConnected;
    if (callback == null) return;
    Future<void>.sync(callback).catchError((Object _) {
      // Recovery is best effort; the next connection transition retries it.
    });
  }

  /// Drive a scan round whenever we should be reconnecting but aren't already.
  void _ensureReconnecting() {
    if (_paused || _connected || _connecting || !_hasMac) return;
    if (_scanning || _retryTimer != null) return; // already working on it
    _beginScanRound();
  }

  void _beginScanRound() {
    if (_paused || _connected || _connecting || !_hasMac || _scanning) return;
    _scanning = true;
    unawaited(_gateway.startScan(_mac!));
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 20), () {
      _stopScan();
      if (!_connected && !_paused) _scheduleRetry();
    });
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: _backoff), () {
      _backoff = (_backoff * 2).clamp(3, 60);
      _beginScanRound();
    });
  }

  void _stopScan() {
    if (_scanning) {
      _scanning = false;
      unawaited(_gateway.stopScan());
    }
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  void _beginConnect(String mac) {
    final revision = _operationRevision;
    _connecting = true;
    unawaited(_connect(mac, revision));
  }

  Future<void> _connect(String mac, int revision) async {
    var succeeded = false;
    try {
      await _gateway.connect(mac);
      succeeded = true;
    } catch (_) {}

    final stale = revision != _operationRevision || _paused || _mac != mac;
    if (stale && succeeded) {
      try {
        await _gateway.disconnect();
      } catch (_) {}
      _connected = false;
    }

    _connecting = false;
    if (stale || !succeeded) _ensureReconnecting();
  }

  Future<void> dispose() async {
    _operationRevision++;
    await _sub?.cancel();
    _sub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stopScan();
    _connected = false;
    _connecting = false;
    _paused = false;
    _mac = null;
    await _stopBackgroundSession();
  }

  Future<void> _syncBackgroundSession() async {
    if (_hasMac) {
      if (_backgroundSessionActive) return;
      await _gateway.startBackgroundSession();
      _backgroundSessionActive = true;
      // The user may unbind while Android is still starting the foreground
      // service. Reconcile against the latest binding after startup completes.
      if (!_hasMac) {
        await _stopBackgroundSession();
        return;
      }
      return;
    }
    await _stopBackgroundSession();
  }

  Future<void> _syncBackgroundSessionBestEffort() async {
    try {
      await _syncBackgroundSession();
    } catch (_) {
      // Keep foreground reconnect usable if Android rejects FGS startup. The
      // next lifecycle transition retries background protection.
    }
  }

  Future<void> _stopBackgroundSession() async {
    if (!_backgroundSessionActive) return;
    try {
      await _gateway.stopBackgroundSession();
      _backgroundSessionActive = false;
    } catch (_) {
      // Keep the flag set so dispose or the next binding transition retries.
    }
  }
}

class _ChipletRingReconnectGateway implements RingReconnectGateway {
  const _ChipletRingReconnectGateway(this._ring);

  final ChipletRing _ring;

  @override
  Stream<RingState> get state => _ring.state;

  @override
  Future<void> connect(String id) => _ring.connect(id);

  @override
  Future<void> disconnect() => _ring.disconnect();

  @override
  Future<void> startScan(String targetId) =>
      _ring.startScan(targetId: targetId);

  @override
  Future<void> stopScan() => _ring.stopScan();

  @override
  Future<void> startBackgroundSession() => _ring.startBackgroundSession();

  @override
  Future<void> stopBackgroundSession() => _ring.stopBackgroundSession();
}

class _SharedPreferencesRingReconnectBindingStore
    implements RingReconnectBindingStore {
  const _SharedPreferencesRingReconnectBindingStore();

  @override
  Future<String?> readMac() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('ring_mac');
  }
}
