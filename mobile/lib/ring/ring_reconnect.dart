import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the ring connected: reconnects on app launch (to the saved MAC) and
/// after any drop, with exponential backoff. All failures are swallowed — this
/// must never block or surface UI (mirrors the card's DeviceSilentReconnect).
class RingReconnect {
  RingReconnect(this._ring);
  final ChipletRing _ring;

  StreamSubscription<RingState>? _sub;
  Timer? _timer;
  int _backoff = 3; // seconds
  String? _mac;

  Future<void> start() async {
    final sp = await SharedPreferences.getInstance();
    _mac = sp.getString('ring_mac');
    _sub ??= _ring.state.listen(_onState);
    if (_mac != null && _mac!.isNotEmpty) {
      _attempt(); // reconnect to the previously-paired ring on launch
    }
  }

  void _onState(RingState s) {
    if (s.conn == RingConnState.connected) {
      _backoff = 3;
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (s.conn == RingConnState.disconnected &&
        _mac != null &&
        _mac!.isNotEmpty) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _backoff), _attempt);
  }

  Future<void> _attempt() async {
    final mac = _mac;
    if (mac == null || mac.isEmpty) return;
    try {
      await _ring.setSavedMac(mac);
      await _ring.reconnect();
    } catch (_) {
      // swallow — next disconnect/backoff will retry
    }
    _backoff = (_backoff * 2).clamp(3, 30);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
  }
}
