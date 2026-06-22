/// Today-page data models + the pure chain splitter.
///
/// `loadToday()` (the network fetch: timeline chain + created-today asset pool +
/// flash-session count) lands in Slice 2.2, where it can be verified end-to-end on
/// device. The models + [splitChain] here are pure and unit-tested
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
  });

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;
  final List<PoolAsset> pool; // capped (≤50) physics bodies
  final int poolTrueCount; // true count today (dashboard header)
  final int flashCount;

  static const empty = TodayData(
      chain: [], noTimeTodos: [], pool: [], poolTrueCount: 0, flashCount: 0);
}

/// Split mapped action candidates into the **upcoming-timed** [chain] (sorted
/// ascending by time) and the no-clock [noTime] todos. Past timed items are
/// dropped — Next Action is forward-looking; overdue / 记录 live in 日历 / 资产.
/// Pure → unit-tested.
({List<ChainItem> chain, List<ChainItem> noTime}) splitChain(
    List<ChainItem> all, DateTime now) {
  final chain = <ChainItem>[];
  final noTime = <ChainItem>[];
  for (final it in all) {
    if (!it.timed) {
      if (it.kind == 'todo') noTime.add(it);
    } else if (!it.at.isBefore(now)) {
      chain.add(it);
    }
  }
  chain.sort((a, b) => a.at.compareTo(b.at));
  return (chain: chain, noTime: noTime);
}
