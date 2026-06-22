import 'today_data.dart';

/// The dashboard's summary strip content, scoped to the active filter.
class SummaryStrip {
  const SummaryStrip(
      {required this.title, required this.sub, required this.metric});
  final String title;
  final String sub;
  final String metric;
}

/// Summary for the dashboard, scoped to [filter] ('all' or a skill type). Only
/// 记账 (expense) is specialized (sum + max + count); every other type — including
/// custom skills — shows just "今天最新一条", because we can't know which custom
/// field is the key number. Charts are unaffected (they count by type/domain).
/// Pure → unit-tested (test/today_summary_test.dart).
SummaryStrip summaryFor(String filter, List<PoolAsset> pool) {
  final items =
      filter == 'all' ? pool : pool.where((a) => a.type == filter).toList();
  if (items.isEmpty) {
    return const SummaryStrip(title: '今天还没有记录', sub: '', metric: '');
  }
  if (filter == 'expense') {
    num sum = 0, maxV = 0;
    for (final a in items) {
      final v = a.payload['amount'] is num ? a.payload['amount'] as num : 0;
      sum += v;
      if (v > maxV) maxV = v;
    }
    return SummaryStrip(
      title: '今日记账汇总',
      sub: '最大 ¥${_n(maxV)} · 共 ${items.length} 笔',
      metric: '¥${_n(sum)}',
    );
  }
  if (filter == 'all') {
    final latest = _latest(items);
    return SummaryStrip(
      title: '今日概览',
      sub: '最新:${latest.title}',
      metric: '共 ${pool.length} 条',
    );
  }
  // default: the latest single record of this type (no aggregation).
  final latest = _latest(items);
  return SummaryStrip(title: latest.title, sub: _hm(latest.createdAt), metric: '');
}

PoolAsset _latest(List<PoolAsset> items) =>
    items.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _n(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
