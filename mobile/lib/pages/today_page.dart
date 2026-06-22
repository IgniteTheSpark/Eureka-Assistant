import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../today/bubble_pool.dart';
import '../today/next_action.dart';
import '../today/today_data.dart';

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

/// Temporary on-device verification of the data fetch (counts parsed from the 3
/// GETs). Committed `false`; flip locally to screenshot Slice 2.2. Replaced by
/// the real panels in Slices 3–5.
const bool _kDebugTodayCounts = false;

class _TodayPageState extends State<TodayPage> {
  final ApiClient _api = ApiClient();
  final Map<int, Future<TodayData>> _cache = {};

  Future<TodayData> _futureFor(int rev) =>
      _cache.putIfAbsent(rev, () => loadToday(_api));

  @override
  void dispose() {
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
              _buildStack(snap.data ?? TodayData.empty),
        );
      },
    );
  }

  Widget _buildStack(TodayData data) {
    return Stack(
      // expand to fill the tab area; otherwise the Stack sizes to its only
      // non-positioned child (a width-less Column) and collapses to a sliver.
      fit: StackFit.expand,
      children: [
        // ── Back: full-screen bubble field (Slice 4 fills this) ──
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0B1220))),
        // Radial atmosphere overlay (prototype token:
        // radial-gradient(130% 60% at 50% -5%, #13203a, #0b1220 60%)).
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.05),
                  radius: 1.3,
                  colors: [Color(0xFF13203A), Color(0xFF0B1220)],
                  stops: [0.0, 0.6],
                ),
              ),
            ),
          ),
        ),
        // bubble pool (Slice 4) — above the atmosphere, behind the panels.
        Positioned.fill(child: BubblePool(pool: data.pool, active: widget.active)),
        // ── Front: panels column (Slice 3 Next Action + Slice 5 Dashboard) ──
        Column(
          children: [
            NextActionPanel(
              chain: data.chain,
              noTimeTodos: data.noTimeTodos,
            ),
            // the bubble pool (Slice 4) shows through this transparent gap.
            const Expanded(child: SizedBox()),
            // reserved gap so the bottom-most panel clears the floating dock.
            const SizedBox(height: 78),
          ],
        ),
        if (_kDebugTodayCounts)
          Positioned(
            top: 12,
            left: 14,
            child: Text(
              '链 ${data.chain.length} · 无时 ${data.noTimeTodos.length} · '
              '池 ${data.pool.length}/${data.poolTrueCount} · ⚡${data.flashCount}',
              style: const TextStyle(color: Color(0xFF8AB4FF), fontSize: 12),
            ),
          ),
      ],
    );
  }
}
