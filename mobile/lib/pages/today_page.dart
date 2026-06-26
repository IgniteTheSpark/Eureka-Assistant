import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../today/bubble_pool.dart';
import '../today/home_foreground.dart';
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
  // foreground screen (0 = 今日安排, 1 = Reka Offer), shared so the bubble pool's
  // background swipe (S2d) and HomeForeground's segment both drive one source.
  final ValueNotifier<int> _screen = ValueNotifier(0);

  Future<TodayData> _futureFor(int rev) =>
      _cache.putIfAbsent(rev, () => loadToday(_api));

  @override
  void dispose() {
    _screen.dispose();
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
        // Radial atmosphere overlay — a soft glow sitting mid-screen BEHIND the
        // cards. center y=-0.1 + radius 0.9 means the top edge (y=-1) is 0.9 out
        // = exactly atmosphereBottom, so the page's top edge equals the nav
        // color (= the bg) in both light and dark → no nav-bar seam; the glow
        // (atmosphereTop) only blooms in the card area.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 0.9,
                  colors: [p.atmosphereTop, p.atmosphereBottom],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        // bubble pool (Slice 4) — above the atmosphere, behind the panels.
        Positioned.fill(
          child: BubblePool(
            pool: data.pool,
            skills: data.skills,
            active: widget.active,
            // S2d: a horizontal swipe on the empty pool (off any bubble) flips
            // the foreground screen; the pool arbitrates this vs bubble-drag.
            onSwipe: (dir) => _screen.value = (_screen.value + dir).clamp(0, 1),
          ),
        ),
        // ── Front: B「潮汐」foreground — 暖顶 + 段控(今日安排 ⇄ Reka Offer) + 屏区.
        // Floats above the pool; the pool shows through the Expanded gap inside
        // HomeForeground. (Replaces the old Next Action panel + 3-chart dashboard,
        // both 废 per spec/handoff-today-home-design.md.)
        HomeForeground(
          chain: data.chain,
          noTimeTodos: data.noTimeTodos,
          flashCount: data.flashCount,
          todoDone: data.todoDone,
          todoTotal: data.todoTotal,
          screen: _screen,
        ),
      ],
    );
  }
}
