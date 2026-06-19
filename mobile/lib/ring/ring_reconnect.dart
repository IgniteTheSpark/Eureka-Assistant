import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  RingReconnect._();
  static final RingReconnect instance = RingReconnect._();

  final ChipletRing _ring = ChipletRing();
  StreamSubscription<RingState>? _sub;
  Timer? _retryTimer;
  Timer? _scanTimer;
  int _backoff = 3; // seconds between retry rounds
  String? _mac;
  bool _connected = false;
  bool _scanning = false;
  bool _paused = false;

  /// Begin keeping the ring connected. Idempotent.
  Future<void> start() async {
    _mac = (await SharedPreferences.getInstance()).getString('ring_mac');
    _sub ??= _ring.state.listen(_onState);
    _ensureReconnecting();
  }

  bool get _hasMac => _mac != null && _mac!.isNotEmpty;

  /// Refresh the saved MAC (call after a fresh pairing).
  Future<void> refreshMac() async {
    _mac = (await SharedPreferences.getInstance()).getString('ring_mac');
    _ensureReconnecting();
  }

  /// Forget the saved ring (on unbind): clear the in-memory MAC and stop all
  /// reconnect activity so it won't auto-reconnect until a new pairing. The
  /// caller is responsible for removing 'ring_mac' from prefs (for cold start).
  void forget() {
    _mac = null;
    _stopScan();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Pause auto-reconnect (e.g. while the pairing page does its own scan).
  void pause() {
    _paused = true;
    _stopScan();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Resume auto-reconnect after the pairing page closes. Re-reads the saved MAC
  /// (it may have changed if the user just paired a different ring).
  void resume() {
    _paused = false;
    SharedPreferences.getInstance().then((sp) {
      _mac = sp.getString('ring_mac');
      _ensureReconnecting();
    });
  }

  void _onState(RingState s) {
    final nowConnected = s.conn == RingConnState.connected;
    // While scanning for reconnect, connect as soon as the saved ring shows up.
    if (!nowConnected && _scanning && _hasMac && s.devices.any((d) => d.id == _mac)) {
      _stopScan();
      _ring.connect(_mac!);
    }
    _connected = nowConnected;
    if (_connected) {
      _backoff = 3;
      _stopScan();
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      _ensureReconnecting(); // (re)start scanning toward the saved ring
    }
  }

  /// Drive a scan round whenever we should be reconnecting but aren't already.
  void _ensureReconnecting() {
    if (_paused || _connected || !_hasMac) return;
    if (_scanning || _retryTimer != null) return; // already working on it
    _beginScanRound();
  }

  void _beginScanRound() {
    if (_paused || _connected || !_hasMac || _scanning) return;
    _scanning = true;
    _ring.startScan();
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
      _ring.stopScan();
    }
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _retryTimer?.cancel();
    _stopScan();
    _connected = false;
  }
}
