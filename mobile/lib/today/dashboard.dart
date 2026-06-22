import 'package:flutter/material.dart';

import '../pages/session_detail_page.dart';
import 'bubble_pool.dart' show glyphForType, typeName;
import 'today_data.dart';
import 'today_summary.dart';

// prototype dark tokens (shared with the other today panels)
const _panelBg = Color(0xA80F1728);
const _panelBorder = Color(0x17FFFFFF);
const _accent = Color(0xFF8AB4FF);
const _accentLight = Color(0xFFCFE0FF);
const _title = Color(0xFFE6EDF3);
const _muted = Color(0x80FFFFFF);
const _muted40 = Color(0x66FFFFFF);

/// Part 2 (dashboard) — today's records summary, scoped by a type filter. Header
/// count + ⚡flash pill, filter chips, a summary strip (记账 sums, else latest one),
/// and (Slice 5.2) the rose/bar/treemap charts. Tapping a chip re-scopes the
/// summary + charts and dims the non-matching bubbles. Hidden when no records
/// (TodayPage gates it). Tokens = prototype; summary calc = today_summary.dart.
class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.pool,
    required this.trueCount,
    required this.flashCount,
    required this.filterKey,
    required this.onFilter,
    this.flashLatestId,
  });

  final List<PoolAsset> pool;
  final int trueCount;
  final int flashCount;
  final String? flashLatestId;
  final String filterKey;
  final void Function(String) onFilter;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final a in widget.pool) {
      counts.update(a.type, (v) => v + 1, ifAbsent: () => 1);
    }
    final types = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final summary = summaryFor(widget.filterKey, widget.pool);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          if (_open) ...[
            _chips(counts, types),
            _summaryStrip(summary),
          ],
        ],
      ),
    );
  }

  Widget _header() => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            children: [
              Text('今天 ${widget.trueCount} 颗',
                  style: const TextStyle(
                      color: _muted40,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (widget.flashCount > 0) _flashPill(),
              const SizedBox(width: 8),
              Icon(
                  _open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: _muted40),
            ],
          ),
        ),
      );

  Widget _flashPill() => GestureDetector(
        onTap: widget.flashLatestId == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionDetailPage(
                    sessionId: widget.flashLatestId!, title: '今日闪念'))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6F9EFF), Color(0xFF8AB4FF)]),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('⚡ ${widget.flashCount}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _chips(Map<String, int> counts, List<String> types) {
    Widget chip(String key, String label) {
      final active = widget.filterKey == key;
      return GestureDetector(
        onTap: () => widget.onFilter(key),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0x336F9EFF) : const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: active ? const Color(0x806F9EFF) : _panelBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? _accentLight : _muted,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          chip('all', '全部 ${widget.pool.length}'),
          for (final t in types)
            chip(t, '${glyphForType(t)} ${typeName(t)} ${counts[t]}'),
        ],
      ),
    );
  }

  Widget _summaryStrip(SummaryStrip s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                  widget.filterKey == 'all'
                      ? '📊'
                      : glyphForType(widget.filterKey),
                  style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _title,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (s.sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(s.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (s.metric.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(s.metric,
                  style: const TextStyle(
                      color: _accentLight,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      );
}
