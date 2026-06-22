import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../today/bubble_pool.dart';
import '../today/dashboard.dart';
import '../today/next_action.dart';
import '../today/today_data.dart';
import '../today/today_palette.dart';

/// 今日页 (首页 tab0 = landing). Two frosted panels — ① Next Action, ② Dashboard —
/// float over a ③ full-screen physics bubble pool (today's captured assets), with
/// the global Reka ball on top. Dark "atmosphere" surface (hifi truth =
/// spec/prototype-today-page.md; logic = §4.5.0; plan = spec/plan-today-page-landing.md).
///
/// Slice 1 = skeleton (3-layer Stack + atmosphere). Slice 2.2 = one [loadToday]
/// fetch wired through a FutureBuilder (chain → Next Action, pool → bubble pool,
/// pool+flash → Dashboard). The three sections themselves land in Slices 3–5.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.active = true});

  /// Whether this is the visible tab (tab0). Gates the bubble pool's ticker +
  /// tilt sensor so they idle when the user is on 日历/资产.
  final bool active;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final ApiClient _api = ApiClient();
  final Map<int, Future<TodayData>> _cache = {};
  String _filterKey =
      'all'; // dashboard chip → scopes summary/charts + dims pool
  String? _highlightId; // a bubble lit up from the dashboard's latest-row tap
  Timer? _hlTimer;

  Future<TodayData> _futureFor(int rev) =>
      _cache.putIfAbsent(rev, () => loadToday(_api));

  /// Light up [id]'s bubble briefly (dashboard latest-row tap).
  void _highlight(String id) {
    setState(() => _highlightId = id);
    _hlTimer?.cancel();
    _hlTimer = Timer(const Duration(milliseconds: 5000), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  @override
  void dispose() {
    _hlTimer?.cancel();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on any data change (flash capture / create / resume), like the
    // calendar's dataRevision wiring; one cached fetch per revision.
    return ValueListenableBuilder<int>(
      valueListenable: dataRevision,
      builder: (context, rev, _) {
        return FutureBuilder<TodayData>(
          future: _futureFor(rev),
          builder: (context, snap) =>
              _buildStack(context, snap.data ?? TodayData.empty),
        );
      },
    );
  }

  Widget _buildStack(BuildContext context, TodayData data) {
    final p = TodayPalette.of(context);
    return Stack(
      // expand to fill the tab area; otherwise the Stack sizes to its only
      // non-positioned child (a width-less Column) and collapses to a sliver.
      fit: StackFit.expand,
      children: [
        // ── Back: atmosphere (dark navy / warm light, per theme) ──
        Positioned.fill(child: ColoredBox(color: p.atmosphereBottom)),
        // Radial atmosphere overlay (prototype token:
        // radial-gradient(130% 60% at 50% -5%, top, bottom 60%)).
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.05),
                  radius: 1.3,
                  colors: [p.atmosphereTop, p.atmosphereBottom],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),
        ),
        // bubble pool (Slice 4) — above the atmosphere, behind the panels.
        Positioned.fill(
          child: BubblePool(
            pool: data.pool,
            active: widget.active,
            filterKey: _filterKey,
            highlightId: _highlightId,
          ),
        ),
        // ── Front: panels column (Slice 3 Next Action + Slice 5 Dashboard) ──
        Column(
          children: [
            NextActionPanel(chain: data.chain, noTimeTodos: data.noTimeTodos),
            // Dashboard hidden entirely when there are no records today.
            if (data.pool.isNotEmpty)
              Dashboard(
                pool: data.pool,
                trueCount: data.poolTrueCount,
                flashCount: data.flashCount,
                flashLatestId: data.flashLatestId,
                filterKey: _filterKey,
                onFilter: (k) =>
                    setState(() => _filterKey = k == _filterKey ? 'all' : k),
                onHighlight: _highlight,
              ),
            // the bubble pool (Slice 4) shows through this transparent gap.
            const Expanded(child: SizedBox()),
            // reserved gap so the bottom-most panel clears the floating dock.
            const SizedBox(height: 78),
          ],
        ),
      ],
    );
  }
}
