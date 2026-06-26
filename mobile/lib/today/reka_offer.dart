import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_events.dart' show openNotificationTarget;
import '../data_revision.dart';
import '../pet/floating_mascot.dart' show rekaNudgeActRequest;
import '../pet/reka_nudges.dart';
import '../theme/app_theme.dart'; // context.eu
import '../theme/domains.dart' show domainColor, isDomain;
import 'card_frame.dart';
import 'today_palette.dart';

/// Reka Offer — the B「潮汐」second screen (spec §14.5a · design bundle B2/B3).
/// A PULL view of today's proactive offers: the COMPREHENSIVE 现算 set from
/// [RekaNudges.instance] `offers` (GET /api/offers/today — accumulation offers
/// UNION 逾期待办 / 无时间习惯, ignoring the push ≤2/day throttle). A **consuming**
/// Tinder deck: 右滑 ✓ 执行 (Reka does it now → the mascot's anchored 记一笔/出报告
/// flow via [rekaNudgeActRequest]) / 左滑 ✕ 跳过 (软「今天不想做」+ 压一天 → outcome
/// dismissed, stays in the feed). Finish → ↻ 重新生成 (re-show this session's skips).
/// Bottom ✕/✓ twin buttons mirror the swipe; a mid-drag global icon (green
/// execute / red dismiss) tells the action. Empty deck → 「Reka Offer 空」.
class RekaOfferScreen extends StatefulWidget {
  /// Jump the global foreground back to【今日安排】(handoff §6 — the empty state
  /// must offer 一键切回 so users never land on a blank board). Wired at the call
  /// site (home_foreground); null = no-op (pill hidden).
  final VoidCallback? onBackToSchedule;

  const RekaOfferScreen({super.key, this.onBackToSchedule});

  @override
  State<RekaOfferScreen> createState() => _RekaOfferScreenState();
}

class _RekaOfferScreenState extends State<RekaOfferScreen>
    with SingleTickerProviderStateMixin {
  static const _execGreen = Color(0xFF84C9A0);
  static const _skipRed = Color(0xFFF08A8A);

  final RekaNudges _store = RekaNudges.instance;
  final List<RekaNudge> _deck = []; // working list; focal = _deck.first
  final List<RekaNudge> _skipped = []; // this session's skips (for ↻ 重新生成)

  // Tinder-style consume swipe.
  Offset _drag = Offset.zero;
  late final AnimationController _fly;
  Offset _flyFrom = Offset.zero, _flyTo = Offset.zero;
  String? _pendingStatus; // 'acted' | 'dismissed', applied on fly complete
  RekaNudge? _pendingNudge;
  late TodayPalette _p;

  @override
  void initState() {
    super.initState();
    // §14.5a PULL: seed from the COMPREHENSIVE offer set (现算), not the push feed.
    _deck.addAll(_store.offers);
    _store.addListener(_onStore);
    // 完成 a todo from the detail sheet (opened via 去看看) bumps dataRevision →
    // recompute the offer set so the completed todo's card drops out here too.
    dataRevision.addListener(_onDataRev);
    // Recompute on entry → the on-demand comprehensive set (accumulation offers
    // UNION 逾期待办 / 无时间习惯, ignoring the push ≤2/day throttle) via the new
    // GET /api/offers/today. Each card is a real upserted Nudge with an id, so the
    // 执行/跳过 paths below (outcome by id) keep working unchanged.
    _store.loadOffers();
    _fly =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 240),
          )
          ..addListener(() {
            final t = Curves.easeOut.transform(_fly.value);
            setState(() => _drag = Offset.lerp(_flyFrom, _flyTo, t)!);
          })
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) _onFlyDone();
          });
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    dataRevision.removeListener(_onDataRev);
    _fly.dispose();
    super.dispose();
  }

  void _onDataRev() {
    if (mounted) _store.loadOffers();
  }

  /// Keep the deck loosely in sync with the shared store's §14.5a PULL set: drop
  /// cards acted / dismissed elsewhere (e.g. from the ball peek), add freshly
  /// computed offers (e.g. when loadOffers resolves). The card currently flying
  /// off is exempt (removed on fly-complete); this-session skips aren't re-added
  /// (they live in _skipped for ↻ 重新生成).
  void _onStore() {
    if (!mounted) return;
    final offerIds = _store.offers.map((n) => n.id).toSet();
    final known = {..._deck.map((n) => n.id), ..._skipped.map((n) => n.id)};
    setState(() {
      _deck.removeWhere(
        (n) => !offerIds.contains(n.id) && n.id != _pendingNudge?.id,
      );
      for (final n in _store.offers) {
        if (!known.contains(n.id)) _deck.add(n);
      }
    });
  }

  // ── consume (swipe release / twin button) ───────────────────────────────────
  void _release(double vx) {
    if (_deck.isEmpty) return;
    final exec = _drag.dx > 96 || vx > 700;
    final skip = _drag.dx < -96 || vx < -700;
    _flyFrom = _drag;
    if (exec || skip) {
      _pendingStatus = exec ? 'acted' : 'dismissed';
      _pendingNudge = _deck.first;
      _flyTo = Offset((exec ? 1 : -1) * 520, _drag.dy + 40);
      _fly.duration = const Duration(milliseconds: 230);
    } else {
      _pendingStatus = null;
      _pendingNudge = null;
      _flyTo = Offset.zero;
      _fly.duration = const Duration(milliseconds: 280);
    }
    _fly.forward(from: 0);
  }

  void _consume(bool exec) {
    if (_fly.isAnimating || _deck.isEmpty) return;
    _flyFrom = _drag;
    _pendingStatus = exec ? 'acted' : 'dismissed';
    _pendingNudge = _deck.first;
    _flyTo = Offset((exec ? 1 : -1) * 520, 40);
    _fly.duration = const Duration(milliseconds: 230);
    _fly.forward(from: 0);
  }

  void _onFlyDone() {
    final status = _pendingStatus;
    final n = _pendingNudge;
    _pendingStatus = null;
    _pendingNudge = null;
    _drag = Offset.zero;
    if (status == null || n == null) {
      setState(() {});
      return;
    }
    setState(() => _deck.removeWhere((x) => x.id == n.id));
    if (status == 'acted') {
      if (n.cta == 'view') {
        // 右滑 on a 逾期/提醒 offer = 完成 its todo (the user is done with it) →
        // the recomputed offer set drops it.
        _completeOffer(n);
      } else {
        // offer (给我看看 / 记一笔) → the mascot's anchored flow (outcome acted +
        // 出报告/快记 with prefillWish) — the same path the peek action buttons use.
        rekaNudgeActRequest.value = n;
      }
    } else {
      _skipped.add(n);
      _store.outcome(n.id, 'dismissed'); // 压一天 (+ stays in the feed)
    }
  }

  void _regenerate() {
    if (_skipped.isEmpty) return;
    setState(() {
      _deck
        ..clear()
        ..addAll(_skipped);
      _skipped.clear();
      _drag = Offset.zero;
    });
  }

  // §3.2 逾期/提醒 offer「去看看」(cta=view) → open the entity's detail sheet WITHOUT
  // consuming the card (look first; the sheet's 完成 / a right-swipe consumes it).
  void _openDetail(RekaNudge n) {
    if (n.ref.isEmpty) return;
    openNotificationTarget('reminder', _viewLink(n.ref));
  }

  // ref → a valid `reminder:<kind>:<id>` for the router (mirrors floating_mascot's
  // _nudgeView; must not double the `todo:` prefix).
  String _viewLink(String ref) => ref.startsWith('reminder:')
      ? ref
      : (ref.startsWith('todo:') || ref.startsWith('evt:'))
      ? 'reminder:$ref'
      : 'reminder:todo:$ref';

  // 完成 a 逾期 offer's todo (right-swipe; mirrors the detail sheet's 完成 / 资产库
  // card): PUT status=done + mark the offer acted; bumpData → _onDataRev reloads
  // the offer set, which then omits the now-completed todo.
  Future<void> _completeOffer(RekaNudge n) async {
    final id = n.ref.startsWith('todo:') ? n.ref.substring(5) : n.ref;
    _store.outcome(n.id, 'acted');
    final api = ApiClient();
    try {
      await api.putJson('/api/assets/$id', {
        'payload_patch': {'status': 'done'},
      });
    } catch (_) {
    } finally {
      api.close();
    }
    bumpData();
  }

  @override
  Widget build(BuildContext context) {
    _p = TodayPalette.of(context);
    if (_deck.isEmpty) {
      return _skipped.isEmpty ? _emptyState() : _regenState();
    }
    // The ✕/✓ actions now live INSIDE the focal card (see _offerCard), so the
    // deck branch is just the stack — it reads as one integrated card, not a
    // top component with buttons floating below.
    return _deckStack();
  }

  // ── deck stack ──────────────────────────────────────────────────────────────
  Widget _deckStack() {
    // 3-zone CardFrame (mockup): header 118 (tint + big ⏰ emoji + tag pill) +
    // body (Reka 帮你 line · title · up-to-2-line body · 去看看 CTA pill) + the
    // in-card ✕/✓ action row (~72 with the 2-line hint). 392 leaves the body's
    // Spacer headroom without a RenderFlex overflow.
    const cardH = kCardHeight;
    final dir = _drag.dx > 4 ? 1 : (_drag.dx < -4 ? -1 : 0); // 1 exec / -1 skip
    final iconProg = (_drag.dx.abs() / 120).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: SizedBox(
        height: cardH + 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_deck.length > 2) _shell(2, cardH),
            if (_deck.length > 1) _shell(1, cardH),
            Transform.translate(
              offset: _drag,
              child: Transform.rotate(
                angle: _drag.dx / 1500,
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    if (_fly.isAnimating) return;
                    setState(() => _drag += d.delta);
                  },
                  onPanEnd: (d) => _release(d.velocity.pixelsPerSecond.dx),
                  child: _offerCard(_deck.first, cardH),
                ),
              ),
            ),
            // mid-drag global action icon (green execute / red dismiss).
            if (dir != 0 && iconProg > 0.04)
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

  Widget _shell(int depth, double cardH) => Positioned(
    top: depth * 12.0,
    left: 0,
    right: 0,
    child: Transform.scale(
      scale: 1 - depth * 0.05,
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: 1 - depth * 0.08,
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
          ),
        ),
      ),
    ),
  );

  // ── offer card = the shared 3-zone CardFrame ─────────────────────────────────
  // [A] header tint + big per-type emoji + tag pill (kind label) · [B] body =
  // Reka 帮你 line + title + body + 去看看/CTA pill · [C] action row = ✕/hint/✓.
  // 别做 (handoff §8): 绿/红 只给 swipe ACTION 揭示 + 全局图标,NOT 卡 chrome —— 卡的
  // resting border 用中性/域色;域只用一个色点表达(单色 + 域点,不堆底色)。
  Widget _offerCard(RekaNudge n, double height) {
    final (_, label) = _kindMeta(n.kind);
    final (emoji, base) = cardKindMeta(n.kind);
    final eu = context.eu;
    final domain = _domainOf(n);
    final dot = domain != null ? domainColor(eu, domain) : null;
    // resting border = neutral panel border, faintly tinted toward the 域色 when
    // known (never green — green is reserved for the execute reveal).
    final border = dot != null
        ? Color.alphaBlend(dot.withValues(alpha: 0.30), _p.cardBorder)
        : _p.cardBorder;
    return CardFrame(
      emoji: emoji,
      base: base,
      tagLabel: label,
      height: height,
      dark: _p.dark,
      surfaceTop: _p.cardTop,
      surfaceBottom: _p.cardBottom,
      border: border,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Reka 帮你 · $label',
                style: TextStyle(fontSize: 11.5, color: _p.muted),
              ),
              const Spacer(),
              // 域色点 (右上角,呼应 B2/B3 mockup) — 单色表达领域,不占底色。
              if (dot != null)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            n.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _p.title,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              n.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _p.muted, fontSize: 12.5, height: 1.35),
            ),
          ],
          const Spacer(),
          // Tapping the CTA pill = execute (same as right-swipe / the ✓ button).
          // B2「给我看看」/逾期「去看看」is the primary affordance, not decoration.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 去看看 (cta=view, 逾期/提醒) = open the entity detail ONLY, NON-consuming
            // — the card stays; 完成 in that sheet (or a right-swipe) is what consumes
            // it. Other CTAs (给我看看 / 记一笔) = execute, same as right-swipe.
            onTap: () => n.cta == 'view' ? _openDetail(n) : _consume(true),
            child: _ctaPill(n.cta),
          ),
        ],
      ),
      actionRow: _actionRow(),
    );
  }

  // [C] in-card action row: ✕ (left, red → 跳过) · centered 2-line hint · ✓
  // (right, green → 执行). They act on _deck.first via _consume — correct, since
  // they only render on the focal card. A tap fires onTap; a drag still pans the
  // card (these are children of the card's pan GestureDetector).
  Widget _actionRow() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
    child: Row(
      children: [
        CardActionButton(
          icon: Icons.close_rounded,
          tint: _skipRed,
          onTap: () => _consume(false),
        ),
        Expanded(
          child: Text(
            '左滑跳过\n右滑执行',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.35, color: _p.faint),
          ),
        ),
        CardActionButton(
          icon: Icons.check_rounded,
          tint: _execGreen,
          onTap: () => _consume(true),
        ),
      ],
    ),
  );

  // B2 填充 CTA 药丸「给我看看 ✨」(bg linear-gradient(rgba(111,158,255,.3)→.15),
  // border rgba(111,158,255,.45), radius 10). Action-blue token, 与主题解耦
  // (这是「执行」动作色,不是卡 chrome / 域色)。
  static const _ctaBlue = Color(0xFF6F9EFF);
  Widget _ctaPill(String cta) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 9),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _ctaBlue.withValues(alpha: 0.30),
          _ctaBlue.withValues(alpha: 0.15),
        ],
      ),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _ctaBlue.withValues(alpha: 0.45)),
    ),
    child: Text(
      '${_ctaLabel(cta)} ✨',
      style: TextStyle(
        color: _p.dark ? const Color(0xFFDCE8FF) : const Color(0xFF2C4C8C),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  /// Derive the offer's 领域 for the color dot. RekaNudge carries no domain field,
  /// so read it off `ref` (`domain:工作`) else map by `kind` (灵感/学习/消费 genres).
  /// Returns null when unknown → no dot (don't fake a domain).
  String? _domainOf(RekaNudge n) {
    if (n.ref.startsWith('domain:')) {
      final d = n.ref.substring(7);
      return isDomain(d) ? d : null;
    }
    switch (n.kind) {
      case 'idea_synthesis':
        return '灵感';
      case 'quiz':
        return '学习';
      case 'consumption_summary':
        return '生活'; // 记账归生活域(域色 §8.3)
      default:
        return null;
    }
  }

  /// kind → (emoji, 中文标签). kind is the nudge's offer genre (§14.3); falls back
  /// to a generic 💡 when the server omits it.
  (String, String) _kindMeta(String kind) {
    switch (kind) {
      case 'consumption_summary':
        return ('💰', '消费总结');
      case 'idea_synthesis':
        return ('💡', '整理灵感');
      case 'offer':
        return ('💡', '整理');
      case 'quiz':
        return ('📝', '学习测验');
      case 'briefing':
        return ('🔍', '会前调研');
      case 'habit_reminder':
        return ('🔥', '习惯');
      case 'overdue':
        return ('⏰', '逾期');
      case 'rhythm_gap':
        return ('🐾', '记一笔');
      case 'reminder':
        return ('❗', '提醒');
      default:
        return ('💡', 'Reka');
    }
  }

  // CTA 药丸文案 (与「✨」连读 · B2「给我看看 ✨」/ B3「帮我查 ✨」)。
  String _ctaLabel(String cta) => switch (cta) {
    'synthesize' => '给我看看',
    'log' => '记一笔',
    'research' => '帮我查',
    'view' => '去看看',
    _ => '执行',
  };

  // ── mid-drag global icon (green execute / red dismiss) ──────────────────────
  Widget _actionIcon(bool exec) {
    final c = exec ? _execGreen : _skipRed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 82,
          height: 82,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: 0.22),
            border: Border.all(color: c, width: 4),
          ),
          child: Icon(
            exec ? Icons.check_rounded : Icons.close_rounded,
            size: 44,
            color: c,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          exec ? '执行' : '跳过',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: c,
          ),
        ),
      ],
    );
  }

  // ── finished (↻ 重新生成) + empty ────────────────────────────────────────────
  Widget _regenState() => _centered(
    '💫',
    '看完了',
    pill: '↻ 重新生成',
    pillColor: _execGreen,
    onPill: _regenerate,
    sub: '把刚跳过的再过一遍',
  );

  // handoff §6 暖空态:「今天没有新建议,记点啥都行」+ 一键切回安排(别让用户切过去
  // 看到白板)。pill 仅在 onBackToSchedule 接好时出现。
  Widget _emptyState() => _centered(
    '💡',
    'Reka Offer 空',
    sub: '今天没有新建议，记点啥都行',
    pill: widget.onBackToSchedule != null ? '← 切回今日安排' : null,
    onPill: widget.onBackToSchedule,
  );

  Widget _centered(
    String emoji,
    String title, {
    String? sub,
    String? pill,
    Color? pillColor,
    VoidCallback? onPill,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: _p.title,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 5),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: _p.muted, fontSize: 12, height: 1.4),
            ),
          ],
          if (pill != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onPill,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: (pillColor ?? _p.accent).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (pillColor ?? _p.accent).withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  pill,
                  style: TextStyle(
                    color: pillColor ?? _p.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
