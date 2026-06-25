import 'package:flutter/material.dart';

import 'next_action.dart' show NextActionPanel;
import 'reka_offer.dart' show RekaOfferScreen;
import 'today_data.dart' show ChainItem;
import 'today_palette.dart';

/// 首页 B「潮汐」前景 (spec/handoff-today-home-design.md · design bundle
/// spec/design-today-home/ B1 frame)。暖顶(早安 + 天气 + 今日一览 chips) +
/// 段控(今日安排 ⇄ Reka Offer,下划线指示) + 屏区(两屏切换)。气泡池在它后面
/// (today_page Stack 下层)从底部透出。
///
/// S1 = 脚手架(2 屏壳 + 段控 + 暖顶)。S2 = 今日安排重做成 B1 浮动 Tinder 叠卡
/// ([NextActionPanel]:event/todo 按类型卡 + 拖拽全局动作 icon + 底部双按钮 + 延后
/// popover + 空态)。屏切 = 段控点选 **或整屏 swipe**([screen] notifier 由 TodayPage
/// 持有,气泡池在空白区仲裁 swipe vs 气泡拖拽 = S2d)。Reka Offer 暂占位(S3 接
/// §14.5a offer);天气占位(QWeather 后端 = S5)。
class HomeForeground extends StatefulWidget {
  const HomeForeground({
    super.key,
    required this.chain,
    required this.noTimeTodos,
    required this.flashCount,
    required this.screen,
  });

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;
  final int flashCount;

  /// Foreground screen (0 = 今日安排, 1 = Reka Offer), owned by TodayPage so the
  /// bubble pool's background swipe (S2d) + the segment tap share one source.
  final ValueNotifier<int> screen;

  @override
  State<HomeForeground> createState() => _HomeForegroundState();
}

class _HomeForegroundState extends State<HomeForeground> {
  // Live horizontal travel while dragging the always-non-card top zone (暖顶 +
  // 段控); released in [_onTopSwipeEnd] to decide a switch. Reset per drag.
  double _topSwipeDx = 0;

  /// The single internal switch path: segment tap, the top-zone swipe, the
  /// pool's background swipe (via TodayPage.onSwipe), and Reka Offer's 「切回安排」
  /// all route here so the [AnimatedSwitcher] (keyed on [widget.screen]) glides.
  void _go(int i) => widget.screen.value = i.clamp(0, 1);

  /// Release of a top-zone horizontal drag → step the screen if the gesture is
  /// horizontal-dominant past a distance/fling threshold (mirrors the pool's
  /// background-swipe arbitration). dx<0 (drag left) → next screen, dx>0 → prev.
  void _onTopSwipeEnd(DragEndDetails dets, int screen) {
    final dx = _topSwipeDx;
    final vx = dets.primaryVelocity ?? 0;
    if (dx.abs() > 40 || vx.abs() > 320) {
      _go(screen + (dx < 0 ? 1 : -1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = TodayPalette.of(context);
    final events = widget.chain.where((c) => c.kind == 'event').length;
    final todos =
        widget.chain.where((c) => c.kind == 'todo').length +
        widget.noTimeTodos.length;
    return ValueListenableBuilder<int>(
      valueListenable: widget.screen,
      builder: (context, screen, _) => Column(
        children: [
          // 暖顶 + 段控 = the always-non-card top zone. A horizontal drag here
          // switches screens (§3.3 整屏 swipe), routed through [_go] so it shares
          // the segment-tap path + the AnimatedSwitcher animates. NB: we do NOT
          // wrap the screen content (card) below — the Tinder deck owns horizontal
          // pans there as its 'browse' gesture, so a full-card-area switch-swipe
          // would conflict with the deck. Net: swipe the top/empty space = switch
          // screens; swipe the card = browse the deck.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _topSwipeDx = 0,
            onHorizontalDragUpdate: (d) => _topSwipeDx += d.delta.dx,
            onHorizontalDragEnd: (dets) => _onTopSwipeEnd(dets, screen),
            child: Column(
              children: [_warmTop(p, events, todos), _segment(p, screen)],
            ),
          ),
          // The two foreground screens. AnimatedSwitcher = a 280ms horizontal
          // glide on segment tap OR the pool's background swipe (S2d). Natural
          // height so the pool shows + stays tappable in the Expanded gap below.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey(screen);
              final dx = incoming ? 0.06 : -0.06;
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(dx, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              );
            },
            layoutBuilder: (cur, prev) => Stack(
              alignment: Alignment.topCenter,
              children: [...prev, ?cur],
            ),
            child: screen == 0
                ? KeyedSubtree(
                    key: const ValueKey(0),
                    child: NextActionPanel(
                      chain: widget.chain,
                      noTimeTodos: widget.noTimeTodos,
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey(1),
                    // §3.4: Reka Offer 空态「切回安排」→ screen 0 (don't strand the
                    // user on a blank board). Same internal switch path as above.
                    child: RekaOfferScreen(onBackToSchedule: () => _go(0)),
                  ),
          ),
          // pool shows through here (today_page paints it behind this column)
          const Expanded(child: SizedBox()),
          // reserved gap so the bottom-most content clears the floating dock
          const SizedBox(height: 78),
        ],
      ),
    );
  }

  // ── 暖顶 (吸收晨报): 早安 + 天气(占位) + 今日一览 chips ───────────────────────
  Widget _warmTop(TodayPalette p, int events, int todos) {
    final (greet, icon) = _greeting();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              // TODO(S5): real weather (QWeather + IP) → ☀️ 26° 晴
              Text(
                greet,
                style: TextStyle(color: p.body, fontSize: 12.5, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            alignment: WrapAlignment.center,
            children: [
              _ovChip(p, '$events 日程', accent: false),
              _ovChip(p, '$todos 待办', accent: false),
              _ovChip(p, '⚡ ${widget.flashCount} 闪念 ›', accent: true),
            ],
          ),
        ],
      ),
    );
  }

  (String, String) _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return ('早安', '☀️');
    if (h < 18) return ('下午好', '🌤️');
    return ('晚上好', '🌙');
  }

  Widget _ovChip(TodayPalette p, String label, {required bool accent}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: accent
              ? p.accent.withValues(alpha: 0.2)
              : p.panelBg.withValues(alpha: p.dark ? 0.5 : 0.82),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent ? p.accent.withValues(alpha: 0.42) : p.panelBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent ? p.accentSoft : p.body,
            fontSize: 11.5,
            fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );

  // ── 段控: 今日安排 | Reka Offer (下划线指示 = 当前屏) ─────────────────────────
  Widget _segment(TodayPalette p, int screen) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _segTab(p, '今日安排', 0, screen),
        const SizedBox(width: 22),
        _segTab(p, 'Reka Offer', 1, screen),
      ],
    ),
  );

  Widget _segTab(TodayPalette p, String label, int i, int screen) {
    final active = screen == i;
    return GestureDetector(
      onTap: () => _go(i),
      behavior: HitTestBehavior.opaque,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active ? p.title : p.faint,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                color: active ? p.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
