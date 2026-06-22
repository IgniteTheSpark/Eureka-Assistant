import '../api/api_client.dart';
import '../timeline/timeline.dart' show TimelineItem;

/// Today-page data models + the pure chain splitter + the one network fetch.
///
/// [loadToday] gathers all three sections in one shot — the timeline chain
/// (by effective_at), the created-today asset pool (by created_at), and the
/// flash-session count. The models + [splitChain] are pure and unit-tested
/// (test/today_data_test.dart). Plan: spec/plan-today-page-landing.md.

/// A forward-looking action in Part 1 (Next Action). `timed` = has a clock time
/// (events always do; todos when `has_clock_time`). No-clock todos go to the
/// "无时间待办" list instead of the timed chain.
class ChainItem {
  const ChainItem({
    required this.kind, // 'event' | 'todo'
    required this.id,
    required this.title,
    required this.at,
    required this.timed,
    this.sub = '',
    this.domain = '',
    this.dur,
    this.note,
    this.done = false,
    this.card = const {},
  });

  final String kind;
  final String id;
  final String title;
  final String sub;
  final String domain;
  final DateTime at;
  final Duration? dur;
  final String? note;
  final bool done;
  final bool timed;

  /// SkillCard-ready map so Next Action renders the *same* global unified card
  /// as 资产库 / 日历 (event → card_type:'event'; todo → user_skill_name+payload),
  /// instead of a bespoke focal card. Built in [_loadChain].
  final Map<String, dynamic> card;
}

/// One captured asset = one bubble in Part 2's pool. `domain` drives the fill
/// color (§8), `type` (skill name) the glyph.
class PoolAsset {
  const PoolAsset({
    required this.id,
    required this.type,
    required this.domain,
    required this.title,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String domain;
  final String title;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

/// Everything the today page needs in one fetch.
class TodayData {
  const TodayData({
    required this.chain,
    required this.noTimeTodos,
    required this.pool,
    required this.poolTrueCount,
    required this.flashCount,
    this.flashLatestId,
  });

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;
  final List<PoolAsset> pool; // capped (≤50) physics bodies
  final int poolTrueCount; // true count today (dashboard header)
  final int flashCount;
  final String? flashLatestId; // newest flash session today (⚡ pill target)

  static const empty = TodayData(
    chain: [],
    noTimeTodos: [],
    pool: [],
    poolTrueCount: 0,
    flashCount: 0,
  );
}

/// Split mapped action candidates into the **upcoming-timed** [chain] (sorted
/// ascending by time) and the no-clock [noTime] todos. Past timed items are
/// dropped — Next Action is forward-looking; overdue / 记录 live in 日历 / 资产.
/// Pure → unit-tested.
({List<ChainItem> chain, List<ChainItem> noTime}) splitChain(
  List<ChainItem> all,
  DateTime now,
) {
  final chain = <ChainItem>[];
  final noTime = <ChainItem>[];
  for (final it in all) {
    if (!it.timed) {
      if (it.kind == 'todo') noTime.add(it);
      continue;
    }
    // Drop only once the action is *over*: an event keeps until its end (so an
    // in-progress meeting stays the focal action with a progress bar); a todo
    // (no duration) keeps until its due moment passes.
    final end = it.dur != null ? it.at.add(it.dur!) : it.at;
    if (!end.isBefore(now)) chain.add(it);
  }
  chain.sort((a, b) => a.at.compareTo(b.at));
  return (chain: chain, noTime: noTime);
}

// ── network fetch ────────────────────────────────────────────────────────────

/// Beijing (+08:00) day-bound ISO string for [day] (the backend stores/compares
/// in +08). `end` → 23:59:59 (inclusive upper bound), else 00:00:00.
String _bound(DateTime day, {required bool end}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = '${day.year}-${two(day.month)}-${two(day.day)}';
  return end ? '${d}T23:59:59+08:00' : '${d}T00:00:00+08:00';
}

bool _todoDone(Map<String, dynamic> p) =>
    p['status'] == 'done' || p['done'] == true;

/// A human title for a pool bubble's summary preview (the detail sheet reuses
/// showAssetDetail for full rendering). Mirrors the timeline's fallback chain
/// minus render_spec.primary_field (which the asset list doesn't carry).
String _poolTitle(Map<String, dynamic> p, String type) {
  final cand =
      p['content'] ??
      p['title'] ??
      p['name'] ??
      (p['amount'] != null ? '¥${p['amount']}' : null);
  if (cand is String) {
    final t = cand.trim();
    if (t.isNotEmpty) return t;
  } else if (cand != null) {
    return cand.toString();
  }
  return type;
}

/// One fetch feeding all three of today's sections. Resilient: a failure in any
/// one sub-fetch degrades that section to empty rather than blanking the whole
/// landing. The three GETs run concurrently (started before the first await).
Future<TodayData> loadToday(ApiClient api, {DateTime? nowOverride}) async {
  final now = nowOverride ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = _bound(today, end: false);
  final to = _bound(today, end: true);

  final chainF = _loadChain(api, from, to, now);
  final poolF = _loadPool(api, from, to);
  final flashF = _loadFlashCount(api, today);

  final split = await chainF;
  final poolRes = await poolF;
  final flash = await flashF;

  return TodayData(
    chain: split.chain,
    noTimeTodos: split.noTime,
    pool: poolRes.pool,
    poolTrueCount: poolRes.trueCount,
    flashCount: flash.count,
    flashLatestId: flash.latestId,
  );
}

/// GET /api/timeline?from&to → today's events + todos, mapped + split into the
/// upcoming-timed chain and the no-clock todo list. Done todos drop out (the
/// chain is forward-looking; overdue / records live in 日历 / 资产).
Future<({List<ChainItem> chain, List<ChainItem> noTime})> _loadChain(
  ApiClient api,
  String from,
  String to,
  DateTime now,
) async {
  try {
    final res = await api.getJson(
      '/api/timeline',
      query: {'from': from, 'to': to, 'limit': 500},
    );
    final items = (res is Map ? res['items'] : null) as List? ?? const [];
    final candidates = <ChainItem>[];
    for (final raw in items.whereType<Map>()) {
      final it = TimelineItem.fromJson(raw.cast<String, dynamic>());
      if (it.kind == 'event') {
        candidates.add(
          ChainItem(
            kind: 'event',
            id: it.eventId ?? it.id,
            title: it.title,
            at: it.effectiveAt,
            timed: true, // events always have a clock time
            sub: (it.location?.isNotEmpty ?? false) ? it.location! : '事件',
            domain: it.domain,
            dur: it.endAt?.difference(it.effectiveAt),
            card: {
              'card_type': 'event',
              'title': it.title,
              'start_at': it.effectiveAt.toIso8601String(),
              'location': it.location ?? '',
              'domain': it.domain,
              'asset_id': it.eventId ?? it.id,
            },
          ),
        );
      } else if (it.kind == 'asset' && it.skillName == 'todo') {
        // A todo is "timed" (→ chain with a countdown) when its due_date carries
        // a clock time (ISO with a `T…` part); a date-only due → no-time list.
        // has_clock_time is occurred_at-based, which a not-yet-done todo lacks.
        final due = it.payload['due_date'];
        final dueTimed = due is String && due.contains('T');
        candidates.add(
          ChainItem(
            kind: 'todo',
            id: it.id,
            title: it.title,
            at: it.effectiveAt,
            timed: it.hasClockTime || dueTimed,
            sub: it.subtitle,
            domain: it.domain,
            note: it.subtitle.isEmpty ? null : it.subtitle,
            done: _todoDone(it.payload),
            card: {
              'user_skill_name': it.skillName,
              'payload': it.payload,
              'asset_id': it.id,
              'session_id': it.sessionId,
              'domain': it.domain,
            },
          ),
        );
      }
    }
    // Keep done *no-time* todos — they stay in the 待安排 list struck-through
    // (R7). Only drop done *timed* todos from the forward-looking chain.
    final live = candidates
        .where((c) => !(c.timed && c.kind == 'todo' && c.done))
        .toList();
    return splitChain(live, now);
  } catch (_) {
    return (chain: <ChainItem>[], noTime: <ChainItem>[]);
  }
}

/// GET /api/assets?created_from&created_to → today's captures (by created_at).
/// True count is the full list; the physics pool is capped at 50 bodies.
Future<({List<PoolAsset> pool, int trueCount})> _loadPool(
  ApiClient api,
  String from,
  String to,
) async {
  try {
    final res = await api.getJson(
      '/api/assets',
      query: {'created_from': from, 'created_to': to, 'limit': 500},
    );
    final list = (res is Map ? res['assets'] : null) as List? ?? const [];
    final all = <PoolAsset>[];
    for (final raw in list.whereType<Map>()) {
      final m = raw.cast<String, dynamic>();
      final payload =
          (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
      final type = m['user_skill_name'] as String? ?? '';
      all.add(
        PoolAsset(
          id: m['id'] as String? ?? '',
          type: type,
          domain: m['domain'] as String? ?? '',
          title: _poolTitle(payload, type),
          payload: payload,
          createdAt:
              DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
              now0(),
        ),
      );
    }
    return (pool: all.take(50).toList(), trueCount: all.length);
  } catch (_) {
    return (pool: <PoolAsset>[], trueCount: 0);
  }
}

/// GET /api/sessions?session_type=flash&date=today → flash count (server filters
/// by DBSession.date, so no client-side date math needed).
Future<({int count, String? latestId})> _loadFlashCount(
  ApiClient api,
  DateTime today,
) async {
  try {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = '${today.year}-${two(today.month)}-${two(today.day)}';
    final res = await api.getJson(
      '/api/sessions',
      query: {'session_type': 'flash', 'date': d},
    );
    final list = (res is Map ? res['sessions'] : null) as List? ?? const [];
    // sessions come ordered created_at desc → first is the newest.
    final latest = list.isNotEmpty && list.first is Map
        ? (list.first as Map)['id'] as String?
        : null;
    return (count: list.length, latestId: latest);
  } catch (_) {
    return (count: 0, latestId: null);
  }
}

/// Fallback timestamp when an asset's created_at fails to parse (rare). Isolated
/// so the rest of the file stays free of direct clock reads.
DateTime now0() => DateTime.now();
