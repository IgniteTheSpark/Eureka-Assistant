import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_events.dart' show navigatorKey;
import '../pages/chat_page.dart';
import '../pages/pet_page.dart';
import '../pages/pet_spawn_page.dart';
import '../render/pet_view.dart';
import '../theme/app_theme.dart';
import 'pet_controller.dart';
import 'pet_cosmetics.dart' show rekaGlow;
import 'reka_chat.dart';
import 'reka_notifications.dart';
import 'reka_nudges.dart';
import 'reka_radial.dart';

/// Ref-counted suppression of the global REKA. Pages that *are* REKA (the spawn
/// takeover + the pet detail) raise this on mount so the floating ball doesn't
/// render over its own hero (and you can't recursively tap into them).
/// Decrement a suppressor, clamped at 0 so a stray/duplicate decrement can never
/// drive the counter negative (which would leave the ball visible the next time
/// a page legitimately suppresses it). Always use this to release.
void releaseMascotSuppress() {
  mascotSuppressed.value = (mascotSuppressed.value - 1).clamp(0, 1 << 30);
}

final ValueNotifier<int> mascotSuppressed = ValueNotifier<int>(0);

/// External trigger to open a REKA function bubble (`'summarize'` / `'create'` /
/// `'notifications'`) from anywhere — e.g. the 报告 list's 洞察 CTA. The mounted
/// FloatingMascot consumes it and opens the bubble anchored to the real ball, so
/// every insight entry funnels through the SAME REKA flow (closed loop) instead
/// of a separate page.
final ValueNotifier<String?> rekaFunctionRequest = ValueNotifier<String?>(null);

/// Convenience: open REKA's 洞察 (summarize) bubble from any page.
void openRekaInsight() => rekaFunctionRequest.value = 'summarize';

/// §9.2 v4 「飞入相框」coordinator. The board measures its hero's resting global
/// rect (transform-independent) and asks the floating ball to fly there; the ball
/// (overlay-resident, its controller always ticks) animates position+scale into
/// the frame, then fires [arrive] once → the board hides the ball + reveals its
/// hero + celebrates. `arrive()` is idempotent so the ball's completion AND the
/// board's safety-timeout can both call it without double-firing (no stuck state).
class RekaFly {
  RekaFly._();
  static final RekaFly instance = RekaFly._();
  final ValueNotifier<Rect?> target = ValueNotifier<Rect?>(null);
  void Function(bool flew)? _onArrived;
  bool _done = false;

  /// §9.2 「飞出相框」(leave 我的岛): the inverse of the board-owned fly-in. When the
  /// user switches away from the island tab, the board's hero is about to unmount,
  /// so the **overlay-resident floating ball** (which outlives the tab) renders a
  /// flight FROM the hero's last on-screen rect BACK to the ball's home spot, then
  /// resumes as the normal ball. Reliable because the ball is tab-independent and
  /// both endpoints are known synchronously at tab-tap time (no route transition).
  final ValueNotifier<Rect?> outFrom = ValueNotifier<Rect?>(null);
  void flyOut(Rect heroGlobalRect) => outFrom.value = heroGlobalRect;

  void flyInto(Rect globalTarget, void Function(bool flew) onArrived) {
    _done = false;
    _onArrived = onArrived;
    target.value = globalTarget;
  }

  /// [flew] = whether a real flight actually played (true) or this is a fallback
  /// landing (false → the board plays its own visible entrance instead).
  void arrive(bool flew) {
    if (_done) return;
    _done = true;
    final cb = _onArrived;
    _onArrived = null;
    target.value = null;
    cb?.call(flew);
  }

  void cancel() {
    _done = true;
    _onArrived = null;
    target.value = null;
  }
}

/// §9.2 全局浮动球球 — a draggable companion that floats over the home shell,
/// remembers its position, and is the emotional entry to the pet + agent:
/// - **短按** → agent 对话(未孵化则进孵化接管)
/// - **长按** → 子菜单(新建对话 / 快创 / 洞察·升华 / 我的岛)
///
/// Mount as `Positioned.fill(child: FloatingMascot())` inside a Stack: empty
/// areas stay transparent to touches (only the ball's GestureDetector is hit),
/// and the PetView canvas is wrapped in IgnorePointer so the gestures land here,
/// not in the WebView.
class FloatingMascot extends StatefulWidget {
  const FloatingMascot({super.key});

  @override
  State<FloatingMascot> createState() => _FloatingMascotState();
}

class _FloatingMascotState extends State<FloatingMascot> with TickerProviderStateMixin {
  static const _size = 66.0;
  static const _prefDx = 'pet_ball_dx';
  static const _prefDy = 'pet_ball_dy';

  final _pet = PetController.instance;
  final GlobalKey _ballKey = GlobalKey(); // to anchor the bubble menu to the ball
  // Fractional position (0..1) of the travel box, so it survives rotation /
  // different screen sizes. Default ≈ bottom-right, clear of the dock.
  Offset _frac = const Offset(0.94, 0.74);
  bool _loaded = false;

  // §9.2 v4 fly-into-frame: while flying, the ball renders at a global position
  // lerped from its spot to the hero frame, scaling to hero size. Driven by this
  // controller (the overlay always ticks). v4 timing: .62s 回弹.
  late final AnimationController _fly =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  Rect? _flyTarget; // global rect (the hero frame)
  Offset _flyFromCenter = Offset.zero; // global center the ball started from
  Rect? _flyOutFrom; // §9.2 飞出: hero rect the ball flies home FROM (leaving 我的岛)

  // §9.2 v4 完成事件反馈 — a new notification fires a pulse ring (2 cycles / 1s)
  // around the ball + a celebrate. `_ballCelebrate` bumps the ball PetView's
  // celebrate signal; `_pulse` drives the ring.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  int _ballCelebrate = 0;
  int _lastUnread = 0;

  // The currently-open radial/chat overlay's close fn (null = nothing open).
  // While a menu is open the ball can't open another / can't be dragged; a tap
  // on the ball closes it (the ball renders above the overlay's barrier).
  VoidCallback? _activeClose;
  bool get _menuOpen => _activeClose != null;

  // §14.7 主动 nudge — 到达 = 轻 bob(拍肩,不是 celebrate 彩纸)+ peek 气泡;
  // 点开 = 可动作面板([记一笔]/[知道了]);忽略 = 收成「...」安静 chip。
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  final _nudges = RekaNudges.instance;
  int _lastBob = 0;
  bool _nudgeExpanded = false;
  Timer? _peekTimer;

  @override
  void initState() {
    super.initState();
    _pet.ensureLoaded();
    _restore();
    RekaFly.instance.target.addListener(_onFlyTarget);
    RekaFly.instance.outFrom.addListener(_onFlyOut);
    _lastUnread = RekaNotifications.instance.unread;
    RekaNotifications.instance.addListener(_onNotif);
    rekaFunctionRequest.addListener(_onFunctionRequest);
    _lastBob = _nudges.bobSignal;
    _nudges.addListener(_onNudges);
  }

  void _onNudges() {
    if (!mounted) return;
    final isNew = _nudges.bobSignal != _lastBob;
    _lastBob = _nudges.bobSignal;
    if (_nudges.peek != null && isNew && mascotSuppressed.value == 0) {
      _bob.forward(from: 0); // 轻 bob — REKA 主动找你的签名 (§14.7)
    }
    setState(() => _nudgeExpanded = false);
    _restartPeekTimer();
  }

  // Peek auto-collapses to the quiet「...」after a few seconds — 醒目但不纠缠.
  void _restartPeekTimer() {
    _peekTimer?.cancel();
    if (_nudges.peek != null && !_nudgeExpanded) {
      _peekTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) _nudges.quiet();
      });
    }
  }

  void _expandNudge() {
    final n = _nudges.peek;
    if (n == null) return;
    _peekTimer?.cancel();
    _nudges.outcome(n.id, 'seen');
    setState(() => _nudgeExpanded = true);
  }

  void _nudgeAct(RekaNudge n) {
    _nudges.outcome(n.id, 'acted');
    setState(() => _nudgeExpanded = false);
    // [记一笔] → 同 radial「快创」的 REKA bubble(一键开记录流)
    if (_menuOpen) _activeClose?.call();
    final anchor = _anchorRect();
    if (anchor != null) _openFunction('create', anchor);
  }

  void _nudgeDismiss(RekaNudge n) {
    _nudges.outcome(n.id, 'dismissed');
    setState(() => _nudgeExpanded = false);
  }

  /// §14.5 Type B offer 接受 = 一键即做:标 acted → 直接进 REKA 洞察生成
  /// (prefillWish 跳过输入,显进度 → 出报告),用户不用打字。
  void _nudgeSynthesize(RekaNudge n) {
    _nudges.outcome(n.id, 'acted');
    setState(() => _nudgeExpanded = false);
    if (_menuOpen) _activeClose?.call();
    final anchor = _anchorRect();
    if (anchor != null) {
      _openFunction('summarize', anchor, prefillWish: _wishFor(n.ref));
    }
  }

  String _wishFor(String ref) {
    if (ref.startsWith('domain:')) {
      final d = ref.substring(7);
      return d == '灵感'
          ? '把我最近一周的灵感聚合成主题,做综合判断和下一步'
          : '帮我把最近一周「$d」领域的记录做一份小结';
    }
    if (ref == 'idea' || ref == 'ideas' || ref.contains('idea')) {
      return '把我最近一周的灵感聚合成主题,做综合判断和下一步';
    }
    if (ref == 'expense') return '把我最近一周的消费复盘一下,看看钱花哪了';
    return '帮我把最近一周的「$ref」记录做一份小结';
  }

  // An external surface (e.g. the 报告 list CTA) asked to open a REKA function
  // bubble — honor it through the same path as the radial menu (real ball anchor).
  void _onFunctionRequest() {
    final intent = rekaFunctionRequest.value;
    if (intent == null) return;
    rekaFunctionRequest.value = null; // consume
    if (_menuOpen || mascotSuppressed.value > 0) return;
    final anchor = _anchorRect();
    if (anchor != null) _openFunction(intent, anchor);
  }

  @override
  void dispose() {
    rekaFunctionRequest.removeListener(_onFunctionRequest);
    RekaFly.instance.target.removeListener(_onFlyTarget);
    RekaFly.instance.outFrom.removeListener(_onFlyOut);
    RekaNotifications.instance.removeListener(_onNotif);
    _nudges.removeListener(_onNudges);
    _peekTimer?.cancel();
    _bob.dispose();
    _pulse.dispose();
    _fly.dispose();
    super.dispose();
  }

  // New notification → pulse ring + celebrate (only on an unread *increase*).
  void _onNotif() {
    final u = RekaNotifications.instance.unread;
    if (u > _lastUnread && mounted) {
      _pulse.forward(from: 0);
      setState(() => _ballCelebrate++);
    }
    _lastUnread = u;
  }

  // The board asked the ball to fly into its hero frame.
  void _onFlyTarget() {
    final t = RekaFly.instance.target.value;
    if (t == null) {
      if (_flyTarget != null && mounted) setState(() => _flyTarget = null);
      return;
    }
    // capture the ball's current global top-left; if unavailable (not laid out /
    // suppressed), the ball can't fly → land immediately (board still reveals hero).
    final from = _anchorRect();
    if (from == null || mascotSuppressed.value > 0 || _pet.pet == null) {
      RekaFly.instance.arrive(false); // can't fly → board plays its own entrance
      return;
    }
    _flyFromCenter = from.center;
    setState(() => _flyTarget = t);
    _fly.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _flyTarget = null);
      RekaFly.instance.arrive(true); // flew
    });
  }

  // The user left 我的岛 — fly the ball from the hero's last rect home, then resume
  // as the normal ball. Renders even while suppressed (the board's hero is gone),
  // so there's always a visible「飞出」transition rather than a snap-back.
  void _onFlyOut() {
    final r = RekaFly.instance.outFrom.value;
    if (r == null) {
      if (_flyOutFrom != null && mounted) setState(() => _flyOutFrom = null);
      return;
    }
    if (_pet.pet == null) {
      RekaFly.instance.outFrom.value = null; // can't render → no flight
      return;
    }
    setState(() => _flyOutFrom = r);
    _fly.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _flyOutFrom = null);
      RekaFly.instance.outFrom.value = null;
    });
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    final dx = p.getDouble(_prefDx);
    final dy = p.getDouble(_prefDy);
    if (mounted) {
      setState(() {
        if (dx != null && dy != null) _frac = Offset(dx.clamp(0, 1), dy.clamp(0, 1));
        _loaded = true;
      });
    }
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_prefDx, _frac.dx);
    await p.setDouble(_prefDy, _frac.dy);
  }


  // §9.2 gestures (folded design): 短按 → 雷达功能菜单; 长按 → 续上次对话.
  // While a menu is open, a tap on REKA just closes it (no re-open / no stacking).
  void _onTap() {
    if (_menuOpen) {
      _activeClose?.call();
      return;
    }
    if (!_pet.spawned) {
      _push(const PetSpawnPage());
    } else {
      _openRadial();
    }
  }

  void _onLongPress() {
    if (_menuOpen) {
      _activeClose?.call();
      return;
    }
    if (!_pet.spawned) {
      _push(const PetSpawnPage());
    } else {
      _push(const ChatPage()); // resumes the last conversation (chat_controller)
    }
  }

  // REKA lives in the root overlay (above every route), so it navigates via the
  // global navigatorKey rather than its own (route-less) context.
  void _push(Widget page) {
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }

  Rect? _anchorRect() {
    final box = _ballKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // Track + remove the active overlay so the ball can close it and refuse to
  // stack a second one.
  OverlayEntry _track(OverlayEntry Function(VoidCallback close) build) {
    final overlay = navigatorKey.currentState!.overlay!;
    late OverlayEntry entry;
    void close() {
      if (entry.mounted) entry.remove();
      if (_activeClose != null) setState(() => _activeClose = null);
    }
    entry = build(close);
    _activeClose = close;
    overlay.insert(entry);
    // rebuild so the ball's gesture guards see _menuOpen immediately
    setState(() {});
    return entry;
  }

  // Short-press → the corner-aware radial function menu (root overlay).
  void _openRadial() {
    if (_menuOpen) return;
    final anchor = _anchorRect();
    if (navigatorKey.currentState?.overlay == null || anchor == null) return;
    final p = _pet.pet;
    final glow = p != null ? rekaGlow(p.skin, p.equipped['aura'] ?? 'soft') : const [Color(0xFF6F9EFF)];
    _track((close) => OverlayEntry(
          builder: (_) => RekaRadial(
            anchor: anchor,
            notifCount: RekaNotifications.instance.unread,
            glow: glow,
            onClose: close,
            onPick: (key) => _onPick(key, anchor),
          ),
        ));
  }

  // A radial item was chosen — functions resolve in REKA bubbles; navigation
  // items push; tasks are §7 (not built yet).
  void _onPick(String key, Rect anchor) {
    switch (key) {
      case 'create':
      case 'summarize':
      case 'notifications':
        _openFunction(key, anchor);
      case 'island':
        // Open 我的岛 — once the board lays out it measures its hero rect and asks
        // this ball to fly into the frame (RekaFly), then hides the ball.
        _push(const PetPage());
      // 'tasks' temporarily removed from the menu — returns with the 岛屿任务
      // (§7) spec (restore the _Item in reka_radial + a 'tasks' case here).
    }
  }

  void _openFunction(String intent, Rect anchor, {String? prefillWish}) {
    if (_menuOpen) return; // radial already closed itself before _onPick ran
    if (navigatorKey.currentState?.overlay == null) return;
    _track((close) => OverlayEntry(
          builder: (_) => RekaChat(
              anchor: anchor, intent: intent, prefillWish: prefillWish, onClose: close),
        ));
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: we do NOT swap to SizedBox when suppressed — on iOS the ball's
    // WKWebView platform view can leave a visible "ghost" when its widget is
    // removed. Instead we keep it mounted and move it OFF-SCREEN, which iOS
    // composites reliably (and avoids reload flicker when it returns).
    return ValueListenableBuilder<int>(
      valueListenable: mascotSuppressed,
      builder: (context, suppressed, _) => _mascot(context, hidden: suppressed > 0),
    );
  }

  Widget _mascot(BuildContext context, {required bool hidden}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pet, _fly, _bob]),
      builder: (context, _) {
        final p = _pet.pet;
        if (!_loaded || p == null) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final maxH = constraints.maxHeight;
            final travelW = (maxW - _size).clamp(0.0, double.infinity);
            final travelH = (maxH - _size).clamp(0.0, double.infinity);

            // §9.2 飞出相框 — leaving 我的岛: fly from the hero's last rect back home,
            // shrinking to ball size (eased, no overshoot). Renders even while the
            // ball is still suppressed (the board hero has unmounted), so the exit
            // always shows motion instead of a snap-to-home.
            if (_flyOutFrom != null) {
              final tt = Curves.easeInOutCubic.transform(_fly.value.clamp(0.0, 1.0));
              final homeCenter = Offset(
                _frac.dx * travelW + _size / 2,
                _frac.dy * travelH + _size / 2,
              );
              final c = Offset.lerp(_flyOutFrom!.center, homeCenter, tt)!;
              final from = _flyOutFrom!.width / _size;
              final scale = from + (1.0 - from) * tt;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: c.dx - _size / 2,
                  top: c.dy - _size / 2,
                  width: _size,
                  height: _size,
                  child: IgnorePointer(child: Transform.scale(scale: scale, child: _ball(context, p))),
                ),
              ]);
            }

            // §9.2 v4 飞入相框 — fly from the remembered spot into the hero frame,
            // scaling to hero size (.62s 回弹 cubic-bezier(.5,-.2,.25,1.3)).
            if (!hidden && _flyTarget != null) {
              final tt = const Cubic(0.5, -0.2, 0.25, 1.3).transform(_fly.value.clamp(0.0, 1.0));
              final c = Offset.lerp(_flyFromCenter, _flyTarget!.center, tt)!;
              final scale = 1 + (_flyTarget!.width / _size - 1) * tt;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: c.dx - _size / 2,
                  top: c.dy - _size / 2,
                  width: _size,
                  height: _size,
                  child: IgnorePointer(child: Transform.scale(scale: scale, child: _ball(context, p))),
                ),
              ]);
            }

            // off-screen when suppressed (a page that IS REKA is showing its hero)
            final left = hidden ? -10000.0 : _frac.dx * travelW;
            // §14.7 轻 bob — a single gentle hop on nudge arrival (拍肩,不开 party).
            final bobDy = _bob.isAnimating ? -9 * math.sin(math.pi * _bob.value) : 0.0;
            final top = _frac.dy * travelH + bobDy;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: _size,
                  height: _size,
                  child: IgnorePointer(
                    ignoring: hidden,
                    child: GestureDetector(
                      key: _ballKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: _onTap,
                      onLongPress: _onLongPress,
                      onPanUpdate: (d) {
                        if (_menuOpen || travelW == 0 || travelH == 0) return;
                        setState(() {
                          _frac = Offset(
                            (_frac.dx + d.delta.dx / travelW).clamp(0.0, 1.0),
                            (_frac.dy + d.delta.dy / travelH).clamp(0.0, 1.0),
                          );
                        });
                      },
                      onPanEnd: (_) => _persist(),
                      child: _ball(context, p),
                    ),
                  ),
                ),
                // §14.7 nudge surfaces (peek 气泡 / 可动作面板 / 「...」安静 chip) —
                // above the ball so the expanded panel's barrier wins taps.
                if (!hidden) ..._nudgeLayer(context, left, _frac.dy * travelH, maxW, maxH),
              ],
            );
          },
        );
      },
    );
  }

  // ── §14.7 nudge layer: peek bubble → action panel → quiet「...」chip ────────
  List<Widget> _nudgeLayer(
      BuildContext context, double ballLeft, double ballTop, double maxW, double maxH) {
    final eu = context.eu;
    final n = _nudges.peek;

    // 安静态: no peek, but un-acted nudges exist → a small glowing 💡 chip
    // (user feedback: bare「...」was too easy to miss — it should read as
    // 「REKA 有个想法等着你」, quiet but findable).
    if (n == null) {
      if (!_nudges.hasPending) return const [];
      return [
        Positioned(
          left: (ballLeft - 8).clamp(4.0, maxW - 30),
          top: (ballTop - 8).clamp(4.0, maxH - 28),
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final p = _nudges.pending;
              if (p.isNotEmpty) _nudges.reopen(p.first.id);
            },
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: eu.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: eu.brand.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                      color: eu.brand.withValues(alpha: 0.45),
                      blurRadius: 9,
                      spreadRadius: 1),
                ],
              ),
              child: const Text('💡', style: TextStyle(fontSize: 12, height: 1)),
            ),
          ),
          ),
        ),
      ];
    }

    const w = 232.0;
    final onRight = ballLeft + _size / 2 > maxW / 2;
    final bx = (onRight ? ballLeft - w - 8 : ballLeft + _size + 8).clamp(8.0, maxW - w - 8);

    if (!_nudgeExpanded) {
      // peek: 一句话气泡,点开变可动作;8s 不理会自动收成「...」(timer).
      return [
        Positioned(
          left: bx,
          top: (ballTop + _size / 2 - 22).clamp(8.0, maxH - 60),
          width: w,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _expandNudge,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: eu.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: eu.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: Text(n.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: eu.textHi, fontSize: 13.5, height: 1.35)),
            ),
          ),
          ),
        ),
      ];
    }

    // expanded: 可动作面板 — [记一笔] / [知道了]; outside tap = 忽略 → 安静「...」.
    return [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _nudges.quiet();
          },
        ),
      ),
      Positioned(
        left: bx,
        top: (ballTop - 36).clamp(8.0, maxH - 170),
        width: w,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: eu.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: eu.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(n.text,
                  style: TextStyle(
                      color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w700, height: 1.35)),
              if (n.body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(n.body,
                      style: TextStyle(color: eu.textMid, fontSize: 12.5, height: 1.4)),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (n.cta == 'log' || n.cta == 'synthesize')
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton(
                          onPressed: () => n.cta == 'synthesize'
                              ? _nudgeSynthesize(n)
                              : _nudgeAct(n),
                          style: FilledButton.styleFrom(
                            backgroundColor: eu.brand,
                            padding: EdgeInsets.zero,
                            textStyle:
                                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          child: Text(n.cta == 'synthesize' ? '✨ 帮我理一理' : '记一笔'),
                        ),
                      ),
                    ),
                  if (n.cta == 'log' || n.cta == 'synthesize') const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextButton(
                        onPressed: () => _nudgeDismiss(n),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text('知道了',
                            style: TextStyle(color: eu.textMid, fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    ];
  }

  Widget _ball(BuildContext context, Pet p) {
    final eu = context.eu;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none, // let the enlarged PetView fx spill past the 66 ball
      children: [
        // §9.2 v4 完成事件脉冲环 — expands + fades twice over 1s on a new notification.
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            if (!_pulse.isAnimating) return const SizedBox.shrink();
            final cycle = (_pulse.value * 2) % 1.0; // two pulses across the 1s
            final scale = 0.7 + cycle * 0.7;
            final op = (1 - cycle) * 0.6;
            return IgnorePointer(
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: eu.brandHi.withValues(alpha: op.clamp(0.0, 1.0)), width: 2),
                  ),
                ),
              ),
            );
          },
        ),
        // soft brand halo so the creature reads as a floating element on any page
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: eu.brand.withValues(alpha: 0.28),
                blurRadius: 16,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const SizedBox(width: _size - 12, height: _size - 12),
        ),
        IgnorePointer(
          // RepaintBoundary isolates the WebView's continuous RAF repaints.
          // OverflowBox: the PetView paints larger than the 66px ball so the
          // engine's listen-rings / celebrate-confetti spill out (toward the
          // bubble) instead of being clipped to the ball — hit area stays 66.
          child: RepaintBoundary(
            child: OverflowBox(
              maxWidth: 132,
              maxHeight: 132,
              child: SizedBox(
                width: 132,
                height: 132,
                child: PetView(
                  genome: p.genome,
                  egg: !p.spawned,
                  scale: 2.4,
                  // §9.2 REKA reacts when its menu/bubble opens — a little「在听」动效.
                  state: _menuOpen ? 'listen' : 'idle',
                  // celebrate on a new notification (bumped by _onNotif).
                  celebrateSignal: _ballCelebrate,
                ),
              ),
            ),
          ),
        ),
        // §9.2 通知角标 — unread count from the REKA feed.
        Positioned(
          right: 6,
          top: 8,
          child: AnimatedBuilder(
            animation: RekaNotifications.instance,
            builder: (context, _) {
              final u = RekaNotifications.instance.unread;
              if (u == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: eu.accentRed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: eu.bg, width: 1.5),
                ),
                child: Text(u > 99 ? '99+' : '$u',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              );
            },
          ),
        ),
      ],
    );
  }
}
