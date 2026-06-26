import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/asset_detail_sheet.dart' show showAssetDetail;
import '../render/render_spec.dart' show RenderSpec, buildCard, synthesizeSpec;
import '../render/skill_card.dart' show renderSpecsProvider;
import '../theme/app_theme.dart'; // context.eu
import '../theme/domains.dart' show domainColor;
import '../theme/eureka_colors.dart';
import 'card_frame.dart';
import 'today_data.dart';
import 'today_palette.dart';

/// Format a countdown [d] for the focal card: "1 时 05 分" once ≥1h, else
/// "23 分 00 秒". Clamps negatives to zero. Pure → unit-tested
/// (test/next_action_fmt_test.dart).
String fmtCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '$h 时 ${two(m)} 分' : '${two(m)} 分 ${two(s)} 秒';
}

/// Serialize [d] as Beijing +08:00 — mirror of `isoBeijing` (pages/create_asset
/// .dart) = the backend tz convention; avoids the local-toIso off-by-one day.
String _isoBeijing(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}'
      'T${two(d.hour)}:${two(d.minute)}:00+08:00';
}

/// 今日安排 — the B1「潮汐」floating Tinder deck (spec/design-today-home/ B1).
/// Per-type cards (event = countdown + auto-reminder line; todo = ⏰延后 + ✓完成)
/// float over the bubble pool; left/right swipe **browses only** (‹上一个 /
/// 下一个›, never consumes) with a mid-drag global action icon + bottom twin
/// buttons; finish → ↻ 回到当前. [chain] is upcoming-timed (sorted), [noTimeTodos]
/// the no-clock todos (appended live). Both come from [loadToday];
/// completing/advancing calls [bumpData] so TodayPage re-fetches. logic = §4.5.0.
class NextActionPanel extends ConsumerStatefulWidget {
  const NextActionPanel({
    super.key,
    required this.chain,
    required this.noTimeTodos,
  });

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;

  @override
  ConsumerState<NextActionPanel> createState() => _NextActionPanelState();
}

class _NextActionPanelState extends ConsumerState<NextActionPanel>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  int _index = 0;
  int _itemCount = 0; // live deck length: timed chain + live no-time todos
  // The 1s clock drives ONLY the focal event's countdown text + bar (via a
  // ValueListenableBuilder), never a whole-panel setState. It runs only while
  // the focal item is a not-yet-ended event (see _syncTicker).
  final ValueNotifier<DateTime> _clock = ValueNotifier(DateTime.now());
  Timer? _tick;
  final Set<String> _completing = {}; // ids mid-PUT (avoid double-tap)
  final GlobalKey _snoozeKey = GlobalKey(); // anchors the 延后 popover
  OverlayEntry? _snoozeOverlay;

  // Tinder-style swipe on the focal card.
  Offset _drag = Offset.zero;
  late final AnimationController _fly;
  Offset _flyFrom = Offset.zero, _flyTo = Offset.zero;
  int _pendingDelta = 0; // index change applied when a fly-off finishes
  late TodayPalette _p; // light/dark token set, refreshed each build

  @override
  void initState() {
    super.initState();
    // Ticker is started/stopped by _syncTicker (called from build) so it only
    // runs when the focal item is a live event — no idle 1s rebuilds on 待办.
    _fly =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 260),
          )
          ..addListener(() {
            final t = Curves.easeOut.transform(_fly.value);
            setState(() => _drag = Offset.lerp(_flyFrom, _flyTo, t)!);
          })
          ..addStatusListener((s) {
            if (s != AnimationStatus.completed) return;
            setState(() {
              if (_pendingDelta != 0) {
                final n = _itemCount;
                // allow n = the end card (one past the last); 0 = first.
                if (n > 0) _index = (_index + _pendingDelta).clamp(0, n);
              }
              _drag = Offset.zero;
              _pendingDelta = 0;
            });
          });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _clock.dispose();
    _fly.dispose();
    _snoozeOverlay?.remove();
    _api.close();
    super.dispose();
  }

  /// Run the 1s clock only while the focal item is a not-yet-ended event (the
  /// only thing with a live countdown). Called from build after the focal is
  /// known, so swiping onto / off an event flips the ticker on / off. Bumps the
  /// clock once on start so the freshly-shown countdown is current immediately.
  void _syncTicker(bool wantTick) {
    if (wantTick == (_tick != null)) return; // already in the desired state
    if (wantTick) {
      _clock.value = DateTime.now();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        _clock.value = DateTime.now(); // notifies only the countdown listener
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  /// True when [it] is the focal item and an event that has not yet ended — i.e.
  /// it still has a counting-down or 进行中 timer. Mirrors _eventProgress's
  /// 已结束 cut-off so a finished event stops the ticker.
  bool _isLiveEvent(ChainItem it) {
    if (it.kind != 'event') return false;
    final now = DateTime.now();
    if (now.isBefore(it.at)) return true; // ⏳ 后开始
    final dur = it.dur;
    if (dur == null || dur.inSeconds <= 0) return false; // no duration → no end ticking
    return now.isBefore(it.at.add(dur)); // 进行中 until end; 已结束 stops it
  }

  /// On release: past the threshold (or a flick), fly the focal off-screen then
  /// browse (non-consuming); otherwise spring it back to center. Direction (per
  /// the mockup's ‹/› action row): 右滑 (dx>0 / fling right) → NEXT item, 左滑
  /// (dx<0 / fling left) → PREVIOUS item. The card flies off in the drag's own
  /// direction. idx == chain.length is the 暂时没有了 end card (one past the last).
  void _releaseDrag(List<ChainItem> chain, int idx, double vx) {
    final goNext = (_drag.dx > 90 || vx > 700) && idx < chain.length;
    final goPrev = (_drag.dx < -90 || vx < -700) && idx > 0;
    _flyFrom = _drag;
    if (goNext || goPrev) {
      _pendingDelta = goNext ? 1 : -1;
      // fly off in the drag's direction: 右滑→next exits right, 左滑→prev exits left.
      _flyTo = Offset((goNext ? 1 : -1) * 460, _drag.dy + 40);
      _fly.duration = const Duration(milliseconds: 220);
    } else {
      _pendingDelta = 0;
      _flyTo = Offset.zero;
      _fly.duration = const Duration(milliseconds: 280);
    }
    _fly.forward(from: 0);
  }

  Future<void> _setDone(String id, bool done) async {
    if (_completing.contains(id)) return;
    setState(() => _completing.add(id));
    try {
      await _api.putJson('/api/assets/$id', {
        'payload_patch': {'status': done ? 'done' : 'pending'},
      });
      bumpData(); // TodayPage re-fetches; timed todos advance, 待安排 stay (struck)
      // Success-path clear: a 待安排 todo re-renders in place (struck, not gone),
      // so without this its id would stay in _completing → 完成 dead forever.
      if (mounted) setState(() => _completing.remove(id));
    } catch (_) {
      if (mounted) setState(() => _completing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    _p = TodayPalette.of(context);
    // B1 deck = the timed chain + today's live no-time todos (so nothing is lost
    // now that the old 无时间待办 list is gone); done no-time todos drop out.
    final items = <ChainItem>[
      ...widget.chain,
      ...widget.noTimeTodos.where((t) => !t.done),
    ];
    _itemCount = items.length;
    if (items.isEmpty) {
      _syncTicker(false); // nothing focal → no countdown to tick
      return _emptyState();
    }
    final idx = _index.clamp(0, items.length); // == length → the end card
    // Tick only when the focal card is a live (not-yet-ended) event; the end
    // card (idx == length) and any todo focal need no per-second rebuild.
    _syncTicker(idx < items.length && _isLiveEvent(items[idx]));

    // Transparent (no panel): the cards float over the pool, framed by the
    // segment above + the dock below. Self-contained card like the Reka Offer
    // screen — the in-card action row (‹ 上一个 / 左右滑浏览 / 下一个 ›) carries the
    // browse affordance, so the old standalone hint line below the deck is gone.
    return _deck(items, idx);
  }

  // ── mid-drag action icon (Tinder feel) ──────────────────────────────────────
  /// The big centered icon that fades in over the stack mid-drag — tells you the
  /// pending action (browse-only here: ‹ 上一个 / 下一个 ›, blue).
  Widget _actionIcon(bool next) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 82,
        height: 82,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _p.accent.withValues(alpha: 0.22),
          border: Border.all(color: _p.accent, width: 4),
        ),
        child: Text(
          next ? '›' : '‹',
          style: TextStyle(fontSize: 42, height: 1, color: _p.accentSoft),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        next ? '下一个' : '上一个',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: _p.accentSoft,
        ),
      ),
    ],
  );

  // ── deck: stacked cards + draggable focal + mid-drag action icon ────────────
  Widget _deck(List<ChainItem> items, int idx) {
    final progress = (_drag.dx.abs() / 130).clamp(0.0, 1.0);
    // B1 cards are the shared 3-zone CardFrame now; both kinds share one height
    // so the event bar + todo buttons both fit under the 118 header without a
    // RenderFlex overflow, mirroring the Reka Offer card so both screens read as
    // the same card presentation. header 118 + body + the ~60 action row.
    const cardH = kCardHeight;
    // which way the drag heads, and whether that move is allowed (head/end caps).
    // 右滑 (dx>0) = next, 左滑 (dx<0) = prev (matches _releaseDrag + the ‹/› row).
    final dir = _drag.dx > 4 ? 1 : (_drag.dx < -4 ? -1 : 0); // 1=next, -1=prev
    final canGo = dir == 1 ? idx < items.length : (dir == -1 && idx > 0);
    final iconProg = canGo ? (_drag.dx.abs() / 120).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: SizedBox(
        height: cardH + 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // the visible stack behind the focal; the next shell rises toward the
            // focal as the focal is dragged away.
            if (idx + 2 < items.length) _stackShell(2, 0, cardH),
            if (idx + 1 < items.length) _stackShell(1, progress, cardH),
            // focal — draggable: follows the finger, tilts, flies off on release.
            // Tap → the global detail sheet; swipe → browse (never consumes).
            Transform.translate(
              offset: _drag,
              child: Transform.rotate(
                angle: _drag.dx / 1500,
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: idx < items.length
                      ? () => _openDetail(items[idx])
                      : null,
                  onPanUpdate: (d) {
                    if (_fly.isAnimating) return;
                    setState(() => _drag += d.delta);
                  },
                  onPanEnd: (d) =>
                      _releaseDrag(items, idx, d.velocity.pixelsPerSecond.dx),
                  child: idx < items.length
                      ? _focalCard(items[idx], cardH)
                      : _endCard(),
                ),
              ),
            ),
            // Tinder global action icon, fading in over the stack mid-drag.
            if (iconProg > 0.04)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: iconProg,
                      child: _actionIcon(dir == 1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A card shell behind the focal (the visible stack). [t] (0→1) rises the
  /// depth-1 shell toward the focal as the focal is dragged away.
  Widget _stackShell(int depth, double t, double cardH) {
    final scale = (1 - depth * 0.05) + (depth == 1 ? t * 0.05 : 0);
    final dy = depth * 12.0 - (depth == 1 ? t * 12.0 : 0);
    return Positioned(
      top: dy,
      left: 0,
      right: 0,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: Opacity(
          // solid (not see-through) so the stack reads as finished cards, not a
          // translucent placeholder; just a touch dimmer per depth.
          opacity: 1 - depth * 0.07,
          child: Container(
            height: cardH,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_p.shellTop, _p.shellBottom],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _p.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _p.dark ? 0.3 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── per-type focal card (B1) ────────────────────────────────────────────────
  /// Focal = a bespoke card rendered by kind, single-color body + one §8 domain
  /// dot. Opaque (cardTop/cardBottom) so the stack behind doesn't bleed through.
  /// The deck owns tap + swipe; the todo's 延后/完成 buttons catch their own taps
  /// (a drag starting on a button still falls through to the deck). event =
  /// per-type 小图 + countdown + imminence/elapsed bar + passive auto-reminder
  /// line (no buttons); todo = 小图 + ⏰延后 + ✓完成 (延后 popover lands in S2b).
  Widget _focalCard(ChainItem it, double height) {
    final eu = context.eu;
    return it.kind == 'event'
        ? _eventCard(it, height, eu)
        : _todoCard(it, height, eu);
  }

  /// The shared 3-zone [CardFrame] for a focal item: [A] header tint + big
  /// per-type emoji + tag pill ("日程"/"待办"); [B] the per-type [body]; [C] the
  /// shared browse action row (‹ 上一个 / 左右滑浏览 / 下一个 ›). [kind] picks the
  /// emoji + base color + tag label.
  Widget _frame(String kind, double height, Widget body) {
    final (emoji, base) = cardKindMeta(kind);
    return CardFrame(
      emoji: emoji,
      base: base,
      tagLabel: kind == 'event' ? '日程' : '待办',
      height: height,
      dark: _p.dark,
      surfaceTop: _p.cardTop,
      surfaceBottom: _p.cardBottom,
      border: _p.cardBorder,
      body: body,
      actionRow: _browseActionRow(),
    );
  }

  /// [C] in-card browse row (BOTH event + todo): circular ‹ (left → previous,
  /// neutral) · centered "左右滑浏览" hint · circular › (right → next, accent like
  /// the mockup). Non-consuming — these just step the deck via [_step].
  Widget _browseActionRow() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
    child: Row(
      children: [
        CardActionButton(
          icon: Icons.chevron_left_rounded,
          tint: _p.muted,
          onTap: () => _step(-1),
        ),
        Expanded(
          child: Text(
            '左右滑浏览',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: _p.faint),
          ),
        ),
        CardActionButton(
          icon: Icons.chevron_right_rounded,
          tint: _p.accent,
          onTap: () => _step(1),
        ),
      ],
    ),
  );

  /// Step the deck by [delta] (‹ = -1 previous, › = +1 next) via the same
  /// fly-off the swipe uses — non-consuming. Clamped to [0, _itemCount] (the end
  /// card is one past the last); a no-op at the caps.
  void _step(int delta) {
    if (_fly.isAnimating) return;
    final next = (_index + delta).clamp(0, _itemCount);
    if (next == _index) return; // at a cap → nothing to do
    _flyFrom = _drag;
    _pendingDelta = delta;
    _flyTo = Offset(delta.sign * 460, 40); // fly off in the step's direction
    _fly.duration = const Duration(milliseconds: 220);
    _fly.forward(from: 0);
  }

  /// §8 domain identity dot — the card's only color (per the locked rule).
  Widget _dot(Color c, {double size = 8}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 7)],
    ),
  );

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// kind · meta row: domain dot + "事件 · 地点" / "待办 · 截止" + optional trailing
  /// (the event's start clock).
  Widget _kindRow(Color dom, String meta, {String? trailing}) => Row(
    children: [
      _dot(dom),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: _p.muted, height: 1),
        ),
      ),
      if (trailing != null)
        Text(
          trailing,
          style: TextStyle(
            fontSize: 11.5,
            color: _p.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
    ],
  );

  Widget _cardTitle(String t) => Text(
    t,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: _p.title,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
  );

  // event: countdown text + imminence/elapsed bar + passive 「🔔 到点自动提醒」.
  // Only the countdown text + bar tick (per-second) — they live in a
  // ValueListenableBuilder on [_clock] so the 1s update rebuilds just those two
  // widgets, not the whole panel. Everything else (meta/title/提醒) is static.
  Widget _eventCard(ChainItem it, double height, EurekaColors eu) {
    final dom = domainColor(eu, it.domain);
    final meta = it.sub == '事件' ? '事件' : '事件 · ${it.sub}';
    return _frame(
      it.kind,
      height,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kindRow(dom, meta, trailing: _hm(it.at)),
          const SizedBox(height: 9),
          _cardTitle(it.title),
          const Spacer(),
          ValueListenableBuilder<DateTime>(
            valueListenable: _clock,
            builder: (_, now, _) {
              final (label, frac) = _eventProgress(it, now);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: _p.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 5,
                      backgroundColor: _p.accent.withValues(alpha: 0.14),
                      valueColor: AlwaysStoppedAnimation(_p.accent),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text('🔔 到点自动提醒', style: TextStyle(fontSize: 11, color: _p.faint)),
        ],
      ),
    );
  }

  /// (label, 0..1 bar) for an event at [now]: imminence over the last hour
  /// before start, then elapsed fraction once 进行中. Re-evaluated each 1s tick
  /// via [_clock] (see _eventCard); _isLiveEvent mirrors the 已结束 cut-off.
  (String, double) _eventProgress(ChainItem it, DateTime now) {
    final started = !now.isBefore(it.at);
    if (!started) {
      final d = it.at.difference(now);
      return (
        '⏳ ${fmtCountdown(d)} 后开始',
        (1 - d.inSeconds / 3600).clamp(0.0, 1.0).toDouble(),
      );
    }
    final dur = it.dur;
    if (dur != null && dur.inSeconds > 0) {
      final end = it.at.add(dur);
      if (now.isBefore(end)) {
        return (
          '进行中 · 还剩 ${fmtCountdown(end.difference(now))}',
          (1 - end.difference(now).inSeconds / dur.inSeconds)
              .clamp(0.0, 1.0)
              .toDouble(),
        );
      }
      return ('已结束', 1.0);
    }
    return ('进行中', 1.0);
  }

  // todo: due line + ⏰延后 / ✓完成 buttons (延后 = on-card, never a swipe).
  Widget _todoCard(ChainItem it, double height, EurekaColors eu) {
    final dom = domainColor(eu, it.domain);
    final meta = it.timed ? '待办 · ${_hm(it.at)} 截止' : '待办';
    // Todos have no live countdown (coarse "X 后到期"), so they read the clock at
    // build time only — no per-second tick. Re-evaluates on any rebuild (swipe /
    // action / data bump), flipping to 已到期 after the due moment.
    final now = DateTime.now();
    final started = !now.isBefore(it.at);
    final due = it.timed
        ? (started ? '已到期' : '⏳ ${fmtCountdown(it.at.difference(now))} 后到期')
        : '无截止时间';
    return _frame(
      it.kind,
      height,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kindRow(dom, meta),
          const SizedBox(height: 9),
          _cardTitle(it.title),
          const Spacer(),
          Text(
            due,
            style: TextStyle(
              color: _p.muted,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _snoozeButton(it),
              const SizedBox(width: 8),
              Expanded(child: _doneButton(it)),
            ],
          ),
        ],
      ),
    );
  }

  // ── S2b · 延后 = on-card quick reschedule (never a swipe) ────────────────────
  /// ⏰ 延后 — amber on-card button. Tap → quick-reschedule popover above it
  /// (1小时 / 明天 / 后天 / 自定义…); long-press → straight to the precise picker.
  Widget _snoozeButton(ChainItem it) {
    const amber = Color(0xFFF5C977);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showSnoozePopover(it),
      onLongPress: () => _pickCustom(it),
      child: Container(
        key: _snoozeKey,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: amber.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: amber.withValues(alpha: 0.42)),
        ),
        child: const Text(
          '⏰ 延后',
          style: TextStyle(
            color: Color(0xFFF5D99A),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Pop the quick-reschedule card just above the 延后 button (its [_snoozeKey]
  /// render box); a full-screen barrier dismisses on any outside tap.
  void _showSnoozePopover(ChainItem it) {
    _dismissSnooze();
    final ctx = _snoozeKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(context).size.height;
    _snoozeOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissSnooze,
            ),
          ),
          Positioned(
            left: pos.dx,
            bottom: screenH - pos.dy + 8, // sit 8px above the button
            child: _snoozeCard(it),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_snoozeOverlay!);
  }

  void _dismissSnooze() {
    _snoozeOverlay?.remove();
    _snoozeOverlay = null;
  }

  Widget _snoozeCard(ChainItem it) {
    const amber = Color(0xFFF5C977);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: _p.cardTop,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: amber.withValues(alpha: 0.34)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _p.dark ? 0.6 : 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('改到什么时候？', style: TextStyle(fontSize: 10.5, color: _p.muted)),
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _snoozeChip(
                  '1 小时',
                  () => _rescheduleBy(it, const Duration(hours: 1)),
                ),
                _snoozeChip('明天', () => _rescheduleByDays(it, 1)),
                _snoozeChip('后天', () => _rescheduleByDays(it, 2)),
                _snoozeChip('自定义…', () => _pickCustom(it)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _snoozeChip(String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: _p.panelBg.withValues(alpha: _p.dark ? 0.6 : 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _p.panelBorder),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: _p.body)),
    ),
  );

  void _rescheduleBy(ChainItem it, Duration d) {
    _dismissSnooze();
    _reschedule(it, DateTime.now().add(d));
  }

  /// Push [days] forward, keeping the original due's time-of-day (a no-time todo
  /// defaults to 09:00). 延到哪天就去哪天 → it leaves today's chain on re-fetch.
  void _rescheduleByDays(ChainItem it, int days) {
    _dismissSnooze();
    final now = DateTime.now(); // action-time read (no cached _now anymore)
    final tod = it.timed ? it.at : DateTime(now.year, now.month, now.day, 9);
    final day = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: days));
    _reschedule(it, DateTime(day.year, day.month, day.day, tod.hour, tod.minute));
  }

  Future<void> _pickCustom(ChainItem it) async {
    _dismissSnooze();
    final now = DateTime.now(); // action-time read (no cached _now anymore)
    final base = it.timed ? it.at : now;
    final day = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    _reschedule(
      it,
      DateTime(
        day.year,
        day.month,
        day.day,
        time?.hour ?? base.hour,
        time?.minute ?? base.minute,
      ),
    );
  }

  /// PUT the new due_date (Beijing ISO) → bumpData re-fetches; if it moved off
  /// today, the deck drops it. Guarded by [_completing] like 完成.
  Future<void> _reschedule(ChainItem it, DateTime newDue) async {
    if (_completing.contains(it.id)) return;
    setState(() => _completing.add(it.id));
    try {
      await _api.putJson('/api/assets/${it.id}', {
        'payload_patch': {'due_date': _isoBeijing(newDue)},
      });
      bumpData();
      // Success-path clear: a same-day reschedule (延后 to later TODAY) keeps the
      // todo in today's chain, so it re-renders with its id still in _completing
      // → 完成 dead forever. Clear it; off-today reschedules just drop out anyway.
      if (mounted) setState(() => _completing.remove(it.id));
    } catch (_) {
      if (mounted) setState(() => _completing.remove(it.id));
    }
  }

  /// ✓ 完成 — accent-filled; completing a timed todo drops it from the chain
  /// (loadToday filters done timed todos) so the deck advances on bumpData.
  Widget _doneButton(ChainItem it) {
    final busy = _completing.contains(it.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : () => _setDone(it.id, true),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _p.accent.withValues(alpha: 0.3),
              _p.accent.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _p.accent.withValues(alpha: 0.45)),
        ),
        child: busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: _p.accentSoft,
                ),
              )
            : Text(
                '✓ 完成',
                style: TextStyle(
                  color: _p.accentSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  /// Open the same detail sheet a SkillCard tap opens: resolve the skill spec
  /// from the registry (entities use a synthesized spec), then showAssetDetail.
  void _openDetail(ChainItem it) {
    final specs =
        ref.read(renderSpecsProvider).valueOrNull ??
        const <String, RenderSpec>{};
    final card = it.card;
    final type = card['card_type'] as String?;
    final isEntity = type == 'event' || type == 'contact' || type == 'task';
    final payload = isEntity
        ? card
        : ((card['payload'] as Map?)?.cast<String, dynamic>() ?? const {});
    final cardType = type ?? (card['user_skill_name'] as String?) ?? 'asset';
    final skill = card['user_skill_name'] as String?;
    final spec = skill != null ? specs[skill] : null;
    var data = isEntity
        ? buildCard(
            payload: card,
            spec: synthesizeSpec(type!),
            displayName: type,
          )
        : buildCard(payload: payload, spec: spec, displayName: cardType);
    data = data.copyWith(domain: card['domain'] as String?);
    showAssetDetail(
      context,
      data: data,
      payload: payload,
      cardType: cardType,
      assetId: (card['asset_id'] ?? card['id']) as String?,
      sessionId: card['session_id'] as String?,
      spec: spec,
    );
  }

  /// Past-the-last end state. Swipe right returns to the last card; the ↻ pill
  /// returns to the current (nearest) action.
  Widget _endCard() {
    return Container(
      height: 128,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_p.cardTop, _p.cardBottom],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            '暂时没有了',
            style: TextStyle(
              color: _p.title,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() {
              _index = 0;
              _drag = Offset.zero;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _p.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _p.accent.withValues(alpha: 0.42)),
              ),
              child: Text(
                '↻ 回到当前',
                style: TextStyle(
                  color: _p.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── empty (S2e · 今日安排空) ─────────────────────────────────────────────────
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🌤️', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          Text(
            '今日安排空',
            style: TextStyle(
              color: _p.title,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '今天没安排，随便记 —— 说一句 Reka 帮你记下',
            textAlign: TextAlign.center,
            style: TextStyle(color: _p.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
