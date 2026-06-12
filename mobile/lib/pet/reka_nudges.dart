import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

/// §14.7 主动 REKA nudge — one proactive prompt surfaced on the floating ball.
@immutable
class RekaNudge {
  final String id;
  final String text; // peek 一句话 (「🐾 该记早餐了?」)
  final String body; // expanded copy in the action bubble
  final String ref; // skill machine_name (cta=log) / entity id
  final String cta; // 'log' | …
  final String status;
  const RekaNudge({
    required this.id,
    required this.text,
    this.body = '',
    this.ref = '',
    this.cta = '',
    this.status = 'delivered',
  });

  static RekaNudge? fromJson(Map j) {
    final id = j['id'] as String?;
    final text = j['text'] as String?;
    if (id == null || text == null || text.isEmpty) return null;
    return RekaNudge(
      id: id,
      text: text,
      body: j['body'] as String? ?? '',
      ref: j['ref'] as String? ?? '',
      cta: j['cta'] as String? ?? '',
      status: j['status'] as String? ?? 'delivered',
    );
  }
}

/// §14.7 nudge lifecycle store — 到达醒目(peek)→ 安静「...」→ feed 可找回.
/// Singleton beside [RekaNotifications]; the FloatingMascot listens to it for
/// the peek bubble + light bob + quiet-dots chip; outcomes go back to the
/// server (acted/dismissed/seen) where they drive the adaptive backoff (§14.8).
class RekaNudges extends ChangeNotifier {
  RekaNudges._();
  static final RekaNudges instance = RekaNudges._();

  final List<RekaNudge> _pending = [];
  List<RekaNudge> get pending => List.unmodifiable(_pending);
  bool get hasPending => _pending.isNotEmpty;

  /// The nudge currently peeking next to the ball (null = quiet state).
  RekaNudge? peek;

  /// Bumped on a NEW arrival → the mascot plays the light bob (拍肩,不开 party).
  int bobSignal = 0;

  bool _loaded = false;

  /// Drop all per-user nudge state on logout so the previous account's nudges
  /// don't leak onto the next user's REKA (peek chip / pending feed).
  void reset() {
    _pending.clear();
    peek = null;
    _loaded = false;
    notifyListeners();
  }

  /// App start: restore today's un-acted nudges → quiet「...」chip, NO bob
  /// (the arrival moment already passed; §14.7 被抑制/离线时直接进安静态).
  Future<void> loadPending() async {
    if (_loaded) return;
    _loaded = true;
    await refresh();
  }

  /// Re-pull pending from the server (authoritative cta/body — the SSE frame
  /// only carries title/body/ref). [peekId] re-points the peek at that nudge
  /// once the fresh copy lands.
  Future<void> refresh({String? peekId}) async {
    final api = ApiClient();
    try {
      final res = await api.getJson('/api/nudges/pending');
      final list = (res is Map ? res['nudges'] : null) as List?;
      if (list == null) return;
      _pending
        ..clear()
        ..addAll(list.whereType<Map>().map(RekaNudge.fromJson).whereType<RekaNudge>());
      final want = peekId ?? peek?.id;
      if (want != null) {
        final i = _pending.indexWhere((x) => x.id == want);
        peek = i >= 0 ? _pending[i] : (peekId != null ? peek : null);
      }
      notifyListeners();
    } catch (_) {
      // best-effort — nudges are an enhancement, never block startup
    } finally {
      api.close();
    }
  }

  /// SSE arrival (type=nudge) → peek + bob.
  void pushArrival(RekaNudge n) {
    _pending.removeWhere((x) => x.id == n.id);
    _pending.insert(0, n);
    peek = n;
    bobSignal++;
    notifyListeners();
  }

  /// Re-open a pending nudge (from the「...」chip or the notification feed).
  /// Returns false when it's not pending anymore (already handled / expired).
  bool reopen(String id) {
    final i = _pending.indexWhere((x) => x.id == id);
    if (i < 0) return false;
    peek = _pending[i];
    notifyListeners();
    return true;
  }

  /// Collapse the peek to the quiet「...」state (ignore ≠ dismiss — the nudge
  /// stays pending + findable in the feed; server marks it ignored at day end).
  void quiet() {
    if (peek == null) return;
    peek = null;
    notifyListeners();
  }

  /// Report an outcome (§14.7) and update local state. acted/dismissed remove
  /// the nudge from the pending set; seen keeps it (just no longer "new").
  Future<void> outcome(String id, String status) async {
    if (status == 'acted' || status == 'dismissed') {
      _pending.removeWhere((x) => x.id == id);
      if (peek?.id == id) peek = null;
      notifyListeners();
    }
    final api = ApiClient();
    try {
      await api.postJson('/api/nudges/$id/outcome', {'status': status});
    } catch (_) {
      // offline → the server marks it ignored at day end; acceptable v1 drift
    } finally {
      api.close();
    }
  }
}
