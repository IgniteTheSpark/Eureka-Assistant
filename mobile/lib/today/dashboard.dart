import 'package:flutter/material.dart';

import '../pages/session_detail_page.dart';
import '../theme/app_theme.dart'; // context.eu
import '../timeline/timeline.dart' show SkillMeta, resolveMeta;
import 'bubble_pool.dart' show openAssetSheet;
import 'charts.dart';
import 'today_data.dart';
import 'today_palette.dart';
import 'today_summary.dart';

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
    required this.onHighlight,
    this.flashLatestId,
    this.skills = const {},
  });

  final List<PoolAsset> pool;

  /// skill_name → {icon, label}; chips / legend / chart header resolve through
  /// this (resolveMeta) so custom skills show their real icon + name.
  final Map<String, SkillMeta> skills;
  final int trueCount;
  final int flashCount;
  final String? flashLatestId;
  final String filterKey;
  final void Function(String) onFilter;

  /// Light up a bubble in the pool (when its summary row is tapped).
  final void Function(String) onHighlight;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _open = true;
  late TodayPalette _p; // light/dark token set, refreshed each build

  @override
  Widget build(BuildContext context) {
    _p = TodayPalette.of(context);
    final counts = <String, int>{};
    for (final a in widget.pool) {
      counts.update(a.type, (v) => v + 1, ifAbsent: () => 1);
    }
    final types = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final summary = summaryFor(widget.filterKey, widget.pool);
    final latest = _latestAsset();
    final groups = chartGroups(
      context.eu,
      widget.filterKey,
      widget.pool,
      widget.skills,
    );
    final scopeLabel = widget.filterKey == 'all'
        ? '今日构成 · 按类型'
        : '${resolveMeta(widget.filterKey, widget.skills).label} · 按领域';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      decoration: BoxDecoration(
        color: _p.panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _p.panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          if (_open) ...[
            _chips(counts, types),
            _summaryStrip(summary, latest),
            ChartView(groups: groups, scopeLabel: scopeLabel, palette: _p),
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
          Text(
            '今天 ${widget.trueCount} 颗',
            style: TextStyle(
              color: _p.faint,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (widget.flashCount > 0) _flashPill(),
          const SizedBox(width: 8),
          Icon(
            _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 20,
            color: _p.faint,
          ),
        ],
      ),
    ),
  );

  Widget _flashPill() => GestureDetector(
    onTap: widget.flashLatestId == null
        ? null
        : () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionDetailPage(
                sessionId: widget.flashLatestId!,
                title: '今日闪念',
              ),
            ),
          ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_p.accent, _p.accentSoft]),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '⚡ ${widget.flashCount}',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
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
            color: active
                ? _p.accent.withValues(alpha: 0.22)
                : _p.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? _p.accent.withValues(alpha: 0.5) : _p.panelBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? _p.accentSoft : _p.muted,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
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
            chip(
              t,
              '${resolveMeta(t, widget.skills).icon} ${resolveMeta(t, widget.skills).label} ${counts[t]}',
            ),
        ],
      ),
    );
  }

  /// The most-recent asset in the current filter — the one the summary's
  /// "latest" line refers to; tapping the strip opens + highlights it.
  PoolAsset? _latestAsset() {
    final items = widget.filterKey == 'all'
        ? widget.pool
        : widget.pool.where((a) => a.type == widget.filterKey).toList();
    if (items.isEmpty) return null;
    return items.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  }

  Widget _summaryStrip(SummaryStrip s, PoolAsset? latest) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: latest == null
        ? null
        : () {
            openAssetSheet(context, latest);
            widget.onHighlight(latest.id);
          },
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _p.accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.filterKey == 'all'
                  ? '📊'
                  : resolveMeta(widget.filterKey, widget.skills).icon,
              style: TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _p.title,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s.sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _p.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (s.metric.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              s.metric,
              style: TextStyle(
                color: _p.accentSoft,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (latest != null)
            Icon(Icons.chevron_right, size: 18, color: _p.faint),
        ],
      ),
    ),
  );
}
