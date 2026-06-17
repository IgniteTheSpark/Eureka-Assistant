import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/foundation.dart';

/// App-wide ring connection state, as a [Listenable] so widgets (e.g. the header
/// device icon) can react — mirroring how the card uses DeviceController.
class RingConnection extends ChangeNotifier {
  RingConnection._();
  static final RingConnection instance = RingConnection._();

  final ChipletRing _ring = ChipletRing();
  StreamSubscription<RingState>? _sub;

  RingConnState conn = RingConnState.disconnected;
  bool get isConnected => conn == RingConnState.connected;

  /// Idempotent — begins mirroring ring state. Call once after login.
  void ensureStarted() {
    _sub ??= _ring.state.listen((s) {
      if (s.conn != conn) {
        conn = s.conn;
        notifyListeners();
      }
    });
  }
}
