import 'package:flutter/material.dart';

import '../data_revision.dart';

/// 今日页 (首页 tab0 = landing). Two frosted panels — ① Next Action, ② Dashboard —
/// float over a ③ full-screen physics bubble pool (today's captured assets), with
/// the global Reka ball on top. Dark "atmosphere" surface (hifi truth =
/// spec/prototype-today-page.md; logic = §4.5.0; plan = spec/plan-today-page-landing.md).
///
/// Slice 1 = this skeleton (3-layer Stack + atmosphere). Data + the three sections
/// land in Slices 2–5.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  @override
  Widget build(BuildContext context) {
    // Rebuild on any data change (flash capture / create / resume), like the
    // calendar's dataRevision wiring. The fetch itself lands in Slice 2.
    return ValueListenableBuilder<int>(
      valueListenable: dataRevision,
      builder: (context, _, _) {
        return const Stack(
          // expand to fill the tab area; otherwise the Stack sizes to its only
          // non-positioned child (a width-less Column) and collapses to a sliver.
          fit: StackFit.expand,
          children: [
            // ── Back: full-screen bubble field (Slice 4 fills this) ──
            Positioned.fill(
              child: ColoredBox(color: Color(0xFF0B1220)),
            ),
            // Radial atmosphere overlay (prototype token:
            // radial-gradient(130% 60% at 50% -5%, #13203a, #0b1220 60%)).
            Positioned.fill(
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
            // ── Front: panels column (Slice 3 Next Action + Slice 5 Dashboard) ──
            Column(
              children: [
                Expanded(child: SizedBox()),
                // reserved gap so the bottom-most panel clears the floating dock.
                SizedBox(height: 78),
              ],
            ),
          ],
        );
      },
    );
  }
}
