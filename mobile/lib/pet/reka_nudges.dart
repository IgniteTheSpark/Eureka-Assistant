import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data_revision.dart';

/// §14.7 主动 REKA nudge — one proactive prompt surfaced on the floating ball.
@immutable
class RekaNudge {
  final String id;
  final String text; // peek 一句话 (「🐾 该记早餐了?」)
  final String body; // expanded copy in the action bubble
  final String ref; // skill machine_name (cta=log) / entity id
  final String cta; // 'log' | 'synthesize' | 'research' | 'view'

  /// offer|consumption_summary|quiz|briefing|overdue|habit_reminder|…
  final String kind;
  final String status;
  const RekaNudge({
    required this.id,
    required this.text,
    this.body = '',
    this.ref = '',
    this.cta = '',
    this.kind = '',
    this.status = 'delivered',
  });

  RekaNudge copyWith({String? status}) => RekaNudge(
    id: id,
    text: text,
    body: body,
    ref: ref,
    cta: cta,
    kind: kind,
    status: status ?? this.status,
  );

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
      kind: j['kind'] as String? ?? '',
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

  // §14.5a PULL — the COMPREHENSIVE on-demand offer set (现算; NOT the push
  // ≤2/day feed). Backs the Reka Offer screen; kept separate from `_pending` so
  // the floating-ball peek state (push) and the offer deck (pull) don't bleed.
  final List<RekaNudge> _offers = [];
  List<RekaNudge> get offers => List.unmodifiable(_offers);

  /// The nudge currently peeking next to the ball (null = quiet state).
  RekaNudge? peek;

  /// Bumped on a NEW arrival → the mascot plays the light bob (拍肩,不开 party).
  int bobSignal = 0;

  bool _loaded = false;
  final Map<String, int> _outcomeRevisions = {};
  ({String id, String status, bool committed})? _latestOutcome;
  int _outcomeSignal = 0;

  /// Last optimistic/rollback outcome applied to the shared Home/Inbox cache.
  /// Consumers use the monotonically delivered ChangeNotifier event, not this
  /// value as durable history.
  ({String id, String status, bool committed})? get latestOutcome =>
      _latestOutcome;
  int get outcomeSignal => _outcomeSignal;

  /// Drop all per-user nudge state on logout so the previous account's nudges
  /// don't leak onto the next user's REKA (peek chip / pending feed).
  void reset() {
    _pending.clear();
    _offers.clear();
    peek = null;
    _loaded = false;
    _outcomeRevisions.clear();
    _latestOutcome = null;
    _outcomeSignal++;
    notifyListeners();
  }

  /// §14.5a PULL — fetch the COMPREHENSIVE current-state offer set from
  /// `GET /api/offers/today` (现算: accumulation offers UNION 逾期待办 + 无时间习惯,
  /// ignoring the push ≤2/day throttle). Each returned offer is a real upserted
  /// Nudge with a stable id, so the deck's 执行(acted)/跳过(dismissed) still go
  /// through [outcome] by id. Replaces the offer deck on every call (idempotent
  /// server-side; excludes anything dismissed today).
  Future<void> loadOffers() async {
    final api = ApiClient();
    try {
      final res = await api.getJson('/api/offers/today');
      final list = (res is Map ? res['nudges'] : null) as List?;
      if (list == null) return;
      _offers
        ..clear()
        ..addAll(
          list.whereType<Map>().map(RekaNudge.fromJson).whereType<RekaNudge>(),
        );
      notifyListeners();
    } catch (_) {
      // best-effort — the offer screen degrades to its empty state on failure.
    } finally {
      api.close();
    }
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
        ..addAll(
          list.whereType<Map>().map(RekaNudge.fromJson).whereType<RekaNudge>(),
        );
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
  Future<bool> outcome(String id, String status, {ApiClient? api}) async {
    final revision = (_outcomeRevisions[id] ?? 0) + 1;
    _outcomeRevisions[id] = revision;
    final pendingIndex = _pending.indexWhere((item) => item.id == id);
    final offerIndex = _offers.indexWhere((item) => item.id == id);
    final previousPending = pendingIndex < 0 ? null : _pending[pendingIndex];
    final previousOffer = offerIndex < 0 ? null : _offers[offerIndex];
    final previousPeek = peek?.id == id ? peek : null;
    _applyLocalOutcome(id, status);
    final client = api ?? ApiClient();
    try {
      final response = await client.postJson('/api/nudges/$id/outcome', {
        'status': status,
      });
      final authoritativeStatus = _outcomeStatus(response) ?? status;
      if (_outcomeRevisions[id] != revision) {
        bumpData();
        return true;
      }
      if (authoritativeStatus != status) {
        _applyLocalOutcome(id, authoritativeStatus);
      }
      _publishOutcome(id, authoritativeStatus, committed: true);
      notifyListeners();
      bumpData();
      return true;
    } catch (_) {
      if (_outcomeRevisions[id] == revision) {
        _restoreOutcome(
          id: id,
          pending: previousPending,
          pendingIndex: pendingIndex,
          offer: previousOffer,
          offerIndex: offerIndex,
          previousPeek: previousPeek,
        );
      }
      return false;
    } finally {
      if (api == null) client.close();
    }
  }

  String? _outcomeStatus(dynamic response) {
    if (response is! Map) return null;
    final nudge = response['nudge'];
    if (nudge is! Map) return null;
    final status = nudge['status']?.toString().trim();
    return status == null || status.isEmpty ? null : status;
  }

  void _applyLocalOutcome(String id, String status) {
    final terminal = status == 'acted' || status == 'dismissed';
    if (terminal) {
      _pending.removeWhere((item) => item.id == id);
      _offers.removeWhere((item) => item.id == id);
      if (peek?.id == id) peek = null;
    } else {
      for (var index = 0; index < _pending.length; index++) {
        if (_pending[index].id == id) {
          _pending[index] = _pending[index].copyWith(status: status);
        }
      }
      for (var index = 0; index < _offers.length; index++) {
        if (_offers[index].id == id) {
          _offers[index] = _offers[index].copyWith(status: status);
        }
      }
      if (peek?.id == id) peek = peek!.copyWith(status: status);
    }
    _publishOutcome(id, status, committed: false);
    notifyListeners();
  }

  void _restoreOutcome({
    required String id,
    required RekaNudge? pending,
    required int pendingIndex,
    required RekaNudge? offer,
    required int offerIndex,
    required RekaNudge? previousPeek,
  }) {
    _pending.removeWhere((item) => item.id == id);
    _offers.removeWhere((item) => item.id == id);
    if (pending != null) {
      _pending.insert(pendingIndex.clamp(0, _pending.length), pending);
    }
    if (offer != null) {
      _offers.insert(offerIndex.clamp(0, _offers.length), offer);
    }
    if (peek?.id == id || previousPeek != null) peek = previousPeek;
    final restored = pending?.status ?? offer?.status;
    if (restored != null) {
      _publishOutcome(id, restored, committed: true);
    }
    notifyListeners();
  }

  void _publishOutcome(String id, String status, {required bool committed}) {
    _latestOutcome = (id: id, status: status, committed: committed);
    _outcomeSignal++;
  }
}
