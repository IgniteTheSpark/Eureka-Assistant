import 'package:flutter/material.dart';

import '../pet/floating_mascot.dart' show mascotSuppressed, releaseMascotSuppress;
import '../pet/pet_controller.dart';
import '../pet/pet_cosmetics.dart';
import '../render/pet_view.dart';
import '../render/sprite_factory.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../widgets/toast.dart';
import 'pet_spawn_page.dart';

/// §9 Reka — pushed detail route. Thin wrapper over [PetBoard] (the same board
/// the 「我的岛」tab embeds). Reached from REKA's radial 我的岛 + after hatch.
class PetPage extends StatefulWidget {
  const PetPage({super.key});

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> {
  // Suppression of the floating ball is handled by [PetBoard] (covers both this
  // pushed page and the 我的岛 tab), so the fly-in handoff works in both paths.
  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        elevation: 0,
        foregroundColor: eu.textHi,
        title: const Text('我的岛', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: const SafeArea(top: false, child: PetBoard(bottomInset: 28)),
    );
  }
}

/// §9.2–9.4 / dressup.html — engagement board: REKA hero pod (name + sub +
/// equipped chips) → 周岛/任务 占位 → 换装(slot tabs + 4-col 背包 grid + 徽色 colorbar)
/// → 成就·里程碑(progress cards). Scrolls itself; handles the un-hatched egg inline.
class PetBoard extends StatefulWidget {
  final double bottomInset;
  const PetBoard({super.key, this.bottomInset = 28});

  @override
  State<PetBoard> createState() => PetBoardState();
}

/// A wardrobe slot (mirrors reka-system.js SLOTS — 7 cosmetic slots).
class _Slot {
  final String key; // skin | emblem | head | leftItem | rightItem | carrier | aura
  final String label;
  const _Slot(this.key, this.label);
}

const _slots = <_Slot>[
  _Slot('skin', '身色'),
  _Slot('emblem', '徽记'),
  _Slot('head', '头部'),
  _Slot('leftItem', '左手'),
  _Slot('rightItem', '右手'),
  _Slot('carrier', '承载'),
  _Slot('aura', '光环'),
];

class PetBoardState extends State<PetBoard> with SingleTickerProviderStateMixin {
  final _pet = PetController.instance;
  int _celebrate = 0;

  // §9.2 v4 「飞入相框」(true cross-overlay): on mount the hero is invisible
  // (heroCtl=0) but laid out, so we can measure its resting rect; the floating
  // ball flies into that rect; on arrival we hide the ball + reveal this hero +
  // celebrate. A safety timeout guarantees arrival even if the flight glitches —
  // so it can never get stuck (parked ball + empty frame).
  final GlobalKey _petKey = GlobalKey();
  // §9.2 board-owned fly-in (reliable): the floating ball is hidden the instant the
  // board mounts, and the hero **flies up into the frame** — driven by this on-stage
  // controller, so it ALWAYS animates (no cross-overlay coordination, no delay, no
  // measurement; the prior cross-overlay flight wouldn't animate on-device).
  late final AnimationController _heroCtl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 640));
  bool _didSuppress = false;

  @override
  void initState() {
    super.initState();
    // 我的岛 is an IndexedStack *tab*, so this initState runs INSIDE the shell's
    // build pass. Mutating Listenables here (mascotSuppressed / PetController)
    // notifies the floating ball mid-build → "setState() called during build".
    // Defer every side-effect to after this frame so the notifies land on a
    // settled tree (also lets the hero entrance animate cleanly).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pet.refresh();
      mascotSuppressed.value++; // ball off-screen while the board IS Reka
      _didSuppress = true;
      _heroCtl.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _celebrate++); // celebrate as it lands
      });
    });
  }

  @override
  void dispose() {
    _heroCtl.dispose();
    // Release AFTER the frame: dispose runs while the IndexedStack is unmounting
    // (tree locked), and releasing notifies the floating ball → "markNeedsBuild
    // when widget tree was locked". The notifier is a top-level singleton, so a
    // post-frame release is safe even though this State is gone.
    if (_didSuppress) {
      _didSuppress = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => releaseMascotSuppress());
    }
    super.dispose();
  }

  /// §9.2 飞出相框: the hero's current on-screen rect (global), measured the moment
  /// the user taps away from 我的岛 (board still laid out). The floating ball flies
  /// home from here. Null if the hero is scrolled off-screen / not laid out → the
  /// shell just lets the ball reappear at home without a flight.
  Rect? measureHeroRect() {
    final box = _petKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _pet.pet?.name ?? 'Reka');
    final eu = context.eu;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text('给Reka改名', style: TextStyle(color: eu.textHi, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 8,
          style: TextStyle(color: eu.textHi),
          decoration: const InputDecoration(counterText: '', hintText: 'Reka'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != _pet.pet?.name) {
      try {
        await _pet.rename(name);
      } catch (e) {
        if (mounted) showToast(context, '改名失败：$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return AnimatedBuilder(
      animation: _pet,
      builder: (context, _) {
        final p = _pet.pet;
        if (p == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: eu.brand)),
          );
        }
        if (!p.spawned) return _egg(eu, p);
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomInset),
          children: [
            // (sprite-factory host is mounted app-wide in main.dart)
            _heroPod(eu, p),
            const SizedBox(height: 14),
            _islandPlaceholder(eu),
            const SizedBox(height: 14),
            _milestoneSummary(eu),
          ],
        );
      },
    );
  }

  // ── un-hatched egg ────────────────────────────────────────────────────────
  Widget _egg(EurekaColors eu, Pet p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
      children: [
        SizedBox(height: 220, child: PetView(genome: p.genome, egg: true, scale: 6)),
        const SizedBox(height: 22),
        Text('一颗灵感蛋正在孵化',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textHi, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text('唤醒它,成为你的灵感伙伴 · Reka。',
            textAlign: TextAlign.center, style: TextStyle(color: eu.textMid, fontSize: 14, height: 1.5)),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetSpawnPage())),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
              decoration: BoxDecoration(
                color: eu.brand,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: eu.brand.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 8))],
              ),
              child: const Text('轻点唤醒  →',
                  style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  // ── hero pod (reka-system v3 .dress-hero) — anatomy callouts replace chips ───
  Widget _heroPod(EurekaColors eu, Pet p) {
    final sub = '${skinLabel[p.skin] ?? p.skin} · ${emblemComponentOf(p.emblem, p.emblemColor).name}';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: RadialGradient(
          center: const Alignment(0, -0.55),
          radius: 0.9,
          colors: [
            (skinSwatch[p.skin] ?? eu.brand).withValues(alpha: 0.18),
            eu.surface.withValues(alpha: 0.0),
          ],
        ),
        color: eu.surface,
        border: Border.all(color: eu.border),
      ),
      child: Column(
        children: [
          // name + sub, top-left (over the callout layer)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _rename,
                        behavior: HitTestBehavior.opaque,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(p.name, style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 5),
                          Icon(Icons.edit_outlined, size: 14, color: eu.textLo),
                        ]),
                      ),
                      const SizedBox(height: 1),
                      Text(sub, style: TextStyle(color: eu.textLo, fontSize: 11)),
                    ],
                  ),
                ),
                // §9.4 换装入口:打开换装二级面板(bottom sheet)。
                GestureDetector(
                  onTap: () => showWardrobe(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: eu.brand.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: eu.brand.withValues(alpha: 0.42)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.checkroom, size: 15, color: eu.brand),
                      const SizedBox(width: 5),
                      Text('换装',
                          style: TextStyle(color: eu.brand, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          // §9.4 v3 anatomy callouts: Reka centered, each equipped part labeled at
          // the pod edge with a dashed leader line + dot. Hero pops in (回到框内).
          _HeroCallouts(
            pet: p,
            petKey: _petKey,
            celebrate: _celebrate,
            entrance: _heroCtl,
            onTapPet: () => setState(() => _celebrate++),
          ),
        ],
      ),
    );
  }

  // ── 周岛/任务 placeholder ───────────────────────────────────────────────────
  Widget _islandPlaceholder(EurekaColors eu) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: eu.surfaceRaised, borderRadius: BorderRadius.circular(16), border: Border.all(color: eu.border)),
      child: Row(children: [
        Icon(Icons.landscape_outlined, size: 22, color: eu.textLo),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('周岛 · 每日任务', style: TextStyle(color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('REKA 接住的记录会在这里长成你的岛 · 敬请期待',
                style: TextStyle(color: eu.textLo, fontSize: 12, height: 1.4)),
          ]),
        ),
      ]),
    );
  }

  // ── milestones —収敛到换装(§9.5). The board only shows a compact summary that
  // opens the wardrobe straight to its 🏆 里程碑 tab (the full 40-rung grid lives
  // there now, beside the cosmetics those milestones unlock). ───────────────────
  Widget _milestoneSummary(EurekaColors eu) {
    final total = _pet.milestones.length;
    final achieved = _pet.milestonesAchieved;
    final pct = total > 0 ? (achieved / total).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      onTap: () => showWardrobe(context, tab: _kMilestoneTab),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: eu.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: eu.border),
        ),
        child: Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('成就 · 里程碑',
                    style: TextStyle(color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (total > 0)
                  Text('$achieved/$total',
                      style: TextStyle(color: eu.brand, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: eu.surfaceRaised,
                  valueColor: AlwaysStoppedAnimation(eu.brand),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right, color: eu.textLo, size: 20),
        ]),
      ),
    );
  }

}

// ── §9.4 v3 anatomy callouts ──────────────────────────────────────────────────
enum _Side { l, r }

/// One callout: category (头部) + value + tier, a side+row for its edge label, and
/// a fractional anchor point on Reka's sprite.
class _CO {
  final String k;
  final String v;
  final String tier;
  final _Side side;
  final int row;
  final double ax, ay;
  const _CO(this.k, this.v, this.tier, this.side, this.row, this.ax, this.ay);
}

/// Reka centered in the pod with anatomy-style callouts: each equipped part gets
/// a glass label at the pod edge, joined to its point on Reka by a dashed leader
/// line + dot (mirrors reka-system.js renderCallouts). The hero pops in (回到框内).
class _HeroCallouts extends StatefulWidget {
  final Pet pet;
  final GlobalKey petKey; // on the untransformed slot → measured as the fly target
  final int celebrate;
  final Animation<double> entrance; // 0 = hidden (during fly) · 1 = shown (on arrival)
  final VoidCallback onTapPet;
  const _HeroCallouts({
    required this.pet,
    required this.petKey,
    required this.celebrate,
    required this.entrance,
    required this.onTapPet,
  });

  @override
  State<_HeroCallouts> createState() => _HeroCalloutsState();
}

class _HeroCalloutsState extends State<_HeroCallouts> {
  static const double _h = 300;
  final List<GlobalKey> _keys = List.generate(6, (_) => GlobalKey());
  List<Size?> _sizes = List.filled(6, null);

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant _HeroCallouts old) {
    super.didUpdateWidget(old);
    _scheduleMeasure(); // values changed → labels may resize → re-measure for lines
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var changed = false;
      final next = List<Size?>.from(_sizes);
      for (var i = 0; i < _keys.length; i++) {
        final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && next[i] != box.size) {
          next[i] = box.size;
          changed = true;
        }
      }
      if (changed) setState(() => _sizes = next);
    });
  }

  List<_CO> _callouts(Pet p) {
    final ec = emblemComponentOf(p.emblem, p.emblemColor);
    return [
      _CO('头部', headLabel[p.equipped['head']] ?? '不戴', tierOf('head', p.equipped['head'] ?? 'none'), _Side.l, 0, 0.50, 0.12),
      _CO('左手', itemLabel[p.equipped['leftItem']] ?? '空手', tierOf('leftItem', p.equipped['leftItem'] ?? 'none'), _Side.l, 1, 0.21, 0.52),
      _CO('承载', carrierLabel[p.equipped['carrier']] ?? '无', tierOf('carrier', p.equipped['carrier'] ?? 'none'), _Side.l, 2, 0.50, 0.90),
      _CO('徽记', ec.name, ec.tier, _Side.r, 0, 0.52, 0.40),
      _CO('右手', itemLabel[p.equipped['rightItem']] ?? '空手', tierOf('rightItem', p.equipped['rightItem'] ?? 'none'), _Side.r, 1, 0.79, 0.52),
      _CO('光环', auraLabel[p.equipped['aura']] ?? '柔光', tierOf('aura', p.equipped['aura'] ?? 'soft'), _Side.r, 2, 0.74, 0.66),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final cos = _callouts(widget.pet);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const h = _h;
      // Match the scale-6 canvas exactly (CW·6=156, CH·6=132) so it fills the box
      // and the callout anchor fractions land precisely on each part.
      const petW = 156.0, petH = 132.0;
      final petRect = Rect.fromLTWH((w - petW) / 2, (h - petH) / 2 - 6, petW, petH);
      final rows = {
        _Side.l: [h * 0.30, h * 0.55, h * 0.83],
        _Side.r: [h * 0.17, h * 0.52, h * 0.83],
      };
      const pad = 10.0;

      final lines = <_CalloutLine>[];
      final labels = <Widget>[];
      for (var i = 0; i < cos.length; i++) {
        final co = cos[i];
        final sz = _sizes[i];
        final rowY = rows[co.side]![co.row];
        final anchor = Offset(petRect.left + co.ax * petW, petRect.top + co.ay * petH);
        labels.add(Positioned(
          top: rowY - (sz?.height ?? 38) / 2,
          left: co.side == _Side.l ? pad : null,
          right: co.side == _Side.r ? pad : null,
          child: _label(eu, co, _keys[i]),
        ));
        if (sz != null) {
          final edgeX = co.side == _Side.l ? (pad + sz.width) : (w - pad - sz.width);
          final elbow = Offset(edgeX + (co.side == _Side.l ? 9 : -9), rowY);
          lines.add(_CalloutLine(Offset(edgeX, rowY), elbow, anchor));
        }
      }

      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: petRect,
              child: GestureDetector(
                key: widget.petKey, // untransformed slot → measured as fly target
                onTap: widget.onTapPet,
                // hidden (opacity 0) until the ball flies in; then heroCtl=1 shows it.
                child: AnimatedBuilder(
                  animation: widget.entrance,
                  // OverflowBox so the engine's celebrate confetti / listen rings
                  // (which spill beyond the canvas) aren't clipped to the pet box.
                  // IgnorePointer → taps fall to the GestureDetector above.
                  child: IgnorePointer(
                    child: OverflowBox(
                      maxWidth: 230,
                      maxHeight: 210,
                      child: SizedBox(
                        width: 230,
                        height: 210,
                        child: PetView(genome: widget.pet.genome, scale: 6, celebrateSignal: widget.celebrate),
                      ),
                    ),
                  ),
                  builder: (context, child) {
                    final v = widget.entrance.value;
                    // Clearly READS as a fly-in: rises ~110px + grows from small,
                    // with an overshoot (回弹) so REKA pops into the frame. Opacity
                    // ramps fast (first 35%) so it's visible the whole flight.
                    final pos = Curves.easeOutCubic.transform(v);
                    final scl = Curves.easeOutBack.transform(v);
                    return Opacity(
                      opacity: (v / 0.35).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - pos) * 110),
                        child: Transform.scale(scale: 0.3 + 0.7 * scl, child: child),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CalloutPainter(lines,
                      line: eu.textMid.withValues(alpha: 0.55), dot: eu.brandHi, node: eu.textLo),
                ),
              ),
            ),
            ...labels,
          ],
        ),
      );
    });
  }

  Widget _label(EurekaColors eu, _CO co, Key key) {
    final t = kTiers[co.tier];
    final showTier = co.tier != 'normal' && t != null;
    return IgnorePointer(
      child: Container(
        key: key,
        constraints: const BoxConstraints(maxWidth: 126),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: eu.surfaceRaised.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: showTier ? Color.alphaBlend(t.color.withValues(alpha: 0.5), eu.border) : eu.border),
        ),
        child: Column(
          crossAxisAlignment: co.side == _Side.l ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(co.k, style: TextStyle(color: eu.textLo, fontSize: 9, letterSpacing: 1.0)),
            const SizedBox(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(co.v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: eu.textHi, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
                if (showTier) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(color: t.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4)),
                    child: Text(t.label, style: TextStyle(color: t.color, fontSize: 8, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalloutLine {
  final Offset edge, elbow, anchor;
  const _CalloutLine(this.edge, this.elbow, this.anchor);
}

class _CalloutPainter extends CustomPainter {
  final List<_CalloutLine> lines;
  final Color line, dot, node;
  _CalloutPainter(this.lines, {required this.line, required this.dot, required this.node});

  @override
  void paint(Canvas canvas, Size size) {
    final lp = Paint()
      ..color = line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dp = Paint()..color = dot;
    final np = Paint()..color = node;
    for (final l in lines) {
      _dashed(canvas, l.edge, l.elbow, lp);
      _dashed(canvas, l.elbow, l.anchor, lp);
      canvas.drawCircle(l.anchor, 2.6, dp);
      canvas.drawCircle(l.edge, 1.7, np);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 2.5, gap = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = (d + dash).clamp(0.0, total);
      canvas.drawLine(a + dir * d, a + dir * end, p);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_CalloutPainter old) => true;
}

/* ── §9.4 换装 全屏二级页 ──────────────────────────────────────────────────── */

/// The wardrobe tab key for the §9.5 milestone grid (sits after the 7 cosmetic
/// slots; selecting it swaps the inventory for the 40-rung milestone grid).
const String _kMilestoneTab = '__milestones__';

/// Open the wardrobe as a **full-screen page** (the hero's 换装 entry calls this).
/// Full-screen avoids the bottom-sheet's tab-dependent height jumps, and lets the
/// **main hero view come along** — so there's a single REKA, not two. [tab] opens
/// straight to a given tab (e.g. [_kMilestoneTab] from the board's 成就 summary).
void showWardrobe(BuildContext context, {String? tab}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _WardrobePage(initialTab: tab)));
}

/// The wardrobe: the **same anatomy-callout hero** brought in (one REKA) + slot
/// tabs + OWNED-only inventory. Uses the PetController singleton; equipping
/// updates the hero here AND the board's hero (both listen to the controller).
class _WardrobePage extends StatefulWidget {
  const _WardrobePage({this.initialTab});
  final String? initialTab;

  @override
  State<_WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<_WardrobePage> {
  final _pet = PetController.instance;
  late String _slotKey = widget.initialTab ?? 'skin';
  int _celebrate = 0;
  final GlobalKey _petKey = GlobalKey();
  // No fly-in on this page — the hero is shown fully (entrance held at 1).
  static const Animation<double> _entrance = AlwaysStoppedAnimation<double>(1.0);

  Future<void> _equip(String slot, String value, {required bool locked}) async {
    if (locked) {
      showToast(context, '还没解锁哦 · 多记录几条就有机会啦');
      return;
    }
    try {
      await _pet.equip(slot, value);
      if (mounted) setState(() => _celebrate++);
    } catch (e) {
      if (mounted) showToast(context, '换装失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: const Text('REKA · 换装', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('只增不减 · 无 EXP', style: TextStyle(color: eu.textLo, fontSize: 10.5)),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _pet,
        builder: (context, _) {
          final p = _pet.pet;
          if (p == null) {
            return Center(child: CircularProgressIndicator(color: eu.brand));
          }
          return Column(
            children: [
              // §9.4 主视图带进来:同一套解剖式 callouts hero —— 全屏里只有这一个 REKA。
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 0.9,
                    colors: [
                      (skinSwatch[p.skin] ?? eu.brand).withValues(alpha: 0.18),
                      eu.surface.withValues(alpha: 0.0),
                    ],
                  ),
                  color: eu.surface,
                  border: Border.all(color: eu.border),
                ),
                child: _HeroCallouts(
                  pet: p,
                  petKey: _petKey,
                  celebrate: _celebrate,
                  entrance: _entrance,
                  onTapPet: () => setState(() => _celebrate++),
                ),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _slotTabs(eu, p)),
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _rarityLegend(eu)),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottomInset),
                  child: _slotKey == _kMilestoneTab ? _milestoneGrid(eu) : _inventory(eu, p),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rarityLegend(EurekaColors eu) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final entry in kTiers.entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: entry.value.color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 5),
            Text(entry.value.label, style: TextStyle(color: eu.textLo, fontSize: 10.5)),
          ]),
      ],
    );
  }

  Widget _slotTabs(EurekaColors eu, Pet p) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // +1: the 🏆 里程碑 tab trails the 7 cosmetic slots (§9.5 收敛到换装).
        itemCount: _slots.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final bool isMs = i == _slots.length;
          final String key = isMs ? _kMilestoneTab : _slots[i].key;
          final String label = isMs ? '🏆 里程碑' : _slots[i].label;
          final on = key == _slotKey;
          return GestureDetector(
            onTap: () => setState(() => _slotKey = key),
            behavior: HitTestBehavior.opaque,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: on ? eu.brand.withValues(alpha: 0.14) : eu.surfaceRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? eu.brand : eu.border, width: on ? 1.4 : 1),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: on ? eu.brand : eu.textMid,
                      fontSize: 12.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
            ),
          );
        },
      ),
    );
  }

  // ── §9.5 里程碑 grid (收敛到换装) — compact 5-col chips: each shows only the
  // reward sprite ringed by its progress; tap a chip for the task + reward.
  // The 40-rung ladder = backend core/milestones.py (single source of truth). ──
  Widget _milestoneGrid(EurekaColors eu) {
    final list = _pet.milestones;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text('里程碑加载中…', style: TextStyle(color: eu.textLo, fontSize: 12))),
      );
    }
    const cols = 5, gap = 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text('已达成 ${_pet.milestonesAchieved} / ${list.length} · 点一下看任务',
              style: TextStyle(color: eu.textLo, fontSize: 11.5)),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: 16,
              children: [
                for (final m in list) SizedBox(width: cellW, child: _milestoneChip(eu, m)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _milestoneChip(EurekaColors eu, Map<String, dynamic> m) {
    final slot = (m['reward_slot'] as String?) ?? '';
    final key = (m['reward_key'] as String?) ?? '';
    final cur = (m['current'] as num?)?.toInt() ?? 0;
    final tgt = (m['threshold'] as num?)?.toInt() ?? 1;
    final done = m['achieved'] == true;
    final tier = (m['tier'] as String?) ?? 'normal';
    final pct = (cur / (tgt == 0 ? 1 : tgt)).clamp(0.0, 1.0);
    final ringColor = done ? eu.accentGreen : (kTiers[tier]?.color ?? eu.border);
    return GestureDetector(
      onTap: () => _showMilestoneSheet(eu, m),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(
                    value: done ? 1.0 : pct,
                    strokeWidth: 3,
                    backgroundColor: eu.surfaceRaised,
                    valueColor: AlwaysStoppedAnimation(ringColor),
                  ),
                ),
                Opacity(opacity: done ? 1.0 : 0.5, child: _rewardSprite(slot, key, 30)),
                if (done)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: eu.accentGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: eu.bg, width: 1.5),
                      ),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text('$cur/$tgt',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  color: done ? eu.accentGreen : eu.textLo, fontSize: 9.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// The reward's real engine part sprite (pixel-exact) where the engine can
  /// render it; aura has no isolated part so it falls back to its glyph.
  Widget _rewardSprite(String slot, String key, double size) {
    if (slot == 'aura') {
      return Text(rewardGlyph(slot, key), style: TextStyle(fontSize: size * 0.62));
    }
    final kind = (slot == 'leftItem' || slot == 'rightItem') ? 'item' : slot;
    final opts = slot == 'skin'
        ? <String, dynamic>{'fit': size.toInt(), 'glow': false}
        : <String, dynamic>{'fit': size.toInt() + 2};
    return SpritePreview(
      size: size + 6,
      cacheKey: 'reward:$slot:$key',
      render: () => SpriteFactory.instance.part(kind, key, opts),
      fallback: Center(child: Text(rewardGlyph(slot, key), style: TextStyle(fontSize: size * 0.55))),
    );
  }

  void _showMilestoneSheet(EurekaColors eu, Map<String, dynamic> m) {
    final slot = (m['reward_slot'] as String?) ?? '';
    final key = (m['reward_key'] as String?) ?? '';
    final cur = (m['current'] as num?)?.toInt() ?? 0;
    final tgt = (m['threshold'] as num?)?.toInt() ?? 1;
    final done = m['achieved'] == true;
    final tier = (m['tier'] as String?) ?? 'normal';
    final exclusive = m['exclusive'] == true;
    final label = (m['label'] as String?) ?? '';
    final reward = rewardLabel(slot, key);
    final pct = (cur / (tgt == 0 ? 1 : tgt)).clamp(0.0, 1.0);
    final tierColor = kTiers[tier]?.color ?? eu.border;
    final green = eu.accentGreen;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: eu.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: eu.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: done ? green.withValues(alpha: 0.5) : tierColor.withValues(alpha: 0.45)),
                  ),
                  child: _rewardSprite(slot, key, 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        style: TextStyle(color: eu.textHi, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(style: TextStyle(color: eu.textMid, fontSize: 12), children: [
                        const TextSpan(text: '奖励 '),
                        TextSpan(
                            text: reward,
                            style: TextStyle(
                                color: done ? green : eu.brandHi, fontWeight: FontWeight.w700)),
                        if (tier != 'normal')
                          TextSpan(
                              text: '  ${kTiers[tier]?.label ?? ''}',
                              style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.w700)),
                        if (exclusive)
                          TextSpan(text: '  · 专属', style: TextStyle(color: eu.textLo, fontSize: 11)),
                      ]),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: done ? 1.0 : pct,
                      minHeight: 7,
                      backgroundColor: eu.surfaceRaised,
                      valueColor: AlwaysStoppedAnimation(done ? green : eu.brand),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(done ? '已达成 ✓' : '$cur / $tgt',
                    style: TextStyle(
                        color: done ? green : eu.textMid, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inventory(EurekaColors eu, Pet p) {
    final slot = _slotKey;
    final List<Widget> cells;
    if (slot == 'emblem') {
      final ownedShapes = {'star', ...(p.unlocked['emblem'] ?? const [])};
      cells = [
        for (final c in kEmblemComponents)
          if (ownedShapes.contains(c.emblem))
            _emblemCell(eu, c, p.emblem == c.emblem && p.emblemColor == c.color),
      ];
    } else {
      List<String> owned;
      switch (slot) {
        case 'skin':
          owned = [...(p.unlocked['skin'] ?? const [])];
          if (owned.isEmpty) owned = [p.skin];
        case 'head':
          owned = ['none', ...(p.unlocked['head'] ?? const [])];
        case 'carrier':
          owned = ['none', ...(p.unlocked['carrier'] ?? const [])];
        case 'aura':
          owned = ['none', 'soft', ...(p.unlocked['aura'] ?? const [])];
        default:
          owned = ['none', ...(p.unlocked['item'] ?? const [])];
      }
      final seen = <String>{};
      owned = [for (final k in owned) if (seen.add(k)) k];
      final selected = switch (slot) {
        'skin' => p.skin,
        'head' => p.equipped['head'] ?? 'none',
        'leftItem' => p.equipped['leftItem'] ?? 'none',
        'rightItem' => p.equipped['rightItem'] ?? 'none',
        'carrier' => p.equipped['carrier'] ?? 'none',
        _ => p.equipped['aura'] ?? 'soft',
      };
      cells = [for (final k in owned) _cell(eu, p, slot, k, selected == k)];
    }
    const cols = 4, gap = 10.0;
    return LayoutBuilder(
      builder: (context, c) {
        final cellW = ((c.maxWidth - gap * (cols - 1)) / cols).clamp(64.0, 110.0);
        return Wrap(
          alignment: WrapAlignment.start,
          spacing: gap,
          runSpacing: gap,
          children: [for (final cell in cells) SizedBox(width: cellW, height: cellW / 0.82, child: cell)],
        );
      },
    );
  }

  Map<String, dynamic> _previewOpts(Pet p, String slot, String key) {
    const bare = {
      'head': 'none', 'leftItem': 'none', 'rightItem': 'none',
      'emblem': 'none', 'carrier': 'none', 'aura': 'soft', 'scale': 3,
    };
    switch (slot) {
      case 'skin':
        return {...bare, 'skin': key};
      case 'emblem':
        return {...bare, 'skin': 'sky', 'emblem': key, 'emblemColor': p.emblemColor};
      case 'head':
        return {...bare, 'skin': p.skin, 'head': key};
      case 'leftItem':
        return {...bare, 'skin': p.skin, 'leftItem': key};
      case 'rightItem':
        return {...bare, 'skin': p.skin, 'rightItem': key};
      case 'carrier':
        return {...bare, 'skin': p.skin, 'carrier': key, 'aura': 'none'};
      case 'aura':
        return {...bare, 'skin': p.skin, 'emblem': 'star', 'aura': key};
      default:
        return {...bare, 'skin': p.skin};
    }
  }

  Widget _cell(EurekaColors eu, Pet p, String slot, String key, bool on) {
    return _cellChrome(
      eu,
      on: on,
      tier: tierOf(slot, key),
      preview: _cellPreview(eu, p, slot, key),
      name: _cellName(slot, key),
      onTap: () => _equip(slot, key, locked: false),
    );
  }

  Widget _emblemCell(EurekaColors eu, EmblemComponent c, bool on) {
    final preview = SpritePreview(
      size: 40,
      cacheKey: 'emblem:${c.emblem}:${c.color}',
      render: () => SpriteFactory.instance.sprite({
        'skin': 'sky', 'emblem': c.emblem, 'emblemColor': c.color,
        'head': 'none', 'leftItem': 'none', 'rightItem': 'none', 'carrier': 'none', 'aura': 'none', 'scale': 3,
      }),
      fallback: Center(child: Text(emblemEmoji[c.emblem] ?? '✨', style: const TextStyle(fontSize: 20))),
    );
    return _cellChrome(
      eu,
      on: on,
      tier: c.tier,
      preview: preview,
      name: c.name,
      onTap: () async {
        try {
          await _pet.equipAll({'emblem': c.emblem, 'emblem_color': c.color});
          if (mounted) setState(() => _celebrate++);
        } catch (e) {
          if (mounted) showToast(context, '换装失败：$e', error: true);
        }
      },
    );
  }

  Widget _cellChrome(EurekaColors eu,
      {required bool on, required String tier, required Widget preview, required String name, required VoidCallback onTap}) {
    final t = kTiers[tier];
    final showTier = tier != 'normal' && t != null;
    final Color bg, border;
    if (on) {
      bg = eu.brand.withValues(alpha: 0.14);
      border = eu.brandHi;
    } else if (showTier) {
      bg = t.color.withValues(alpha: 0.10);
      border = Color.alphaBlend(t.color.withValues(alpha: 0.42), eu.border);
    } else {
      bg = eu.surface;
      border = eu.border;
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: on ? 2 : 1),
          boxShadow: on
              ? [BoxShadow(color: eu.brandHi.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 1.5)]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      preview,
                      const SizedBox(height: 4),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: on ? eu.brand : eu.textMid,
                              fontSize: 10,
                              fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
            if (showTier)
              Positioned(
                top: 4,
                left: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: t.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(t.label, style: TextStyle(color: t.color, fontSize: 7, fontWeight: FontWeight.w700)),
                ),
              ),
            if (on)
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: eu.brandHi,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
                  ),
                  child: const Text('✓',
                      style: TextStyle(color: Color(0xFF07101F), fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cellPreview(EurekaColors eu, Pet p, String slot, String key) {
    final Widget fallback = slot == 'skin'
        ? Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: skinSwatch[key] ?? eu.brand,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          )
        : Center(child: Text(_cellGlyph(slot, key), style: const TextStyle(fontSize: 20)));
    if (slot == 'carrier') {
      if (key == 'none') return fallback;
      return SpritePreview(
        size: 40,
        cacheKey: 'carrier:$key',
        render: () => SpriteFactory.instance.part('carrier', key, {'fit': 30}),
        fallback: fallback,
      );
    }
    final preview = SpritePreview(
      size: 40,
      cacheKey: '$slot:$key:${p.skin}',
      render: () => SpriteFactory.instance.sprite(_previewOpts(p, slot, key)),
      fallback: fallback,
    );
    if (slot == 'aura') {
      final cols = auraGlow[key] ?? const <Color>[];
      return Container(
        decoration: cols.isEmpty
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [for (final c in cols) BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 11, spreadRadius: 1)],
              ),
        child: preview,
      );
    }
    return preview;
  }

  String _cellGlyph(String slot, String key) => switch (slot) {
        'emblem' => emblemEmoji[key] ?? '✨',
        'head' => headEmoji[key] ?? '🎩',
        'carrier' => carrierEmoji[key] ?? '☁️',
        'aura' => auraEmoji[key] ?? '🌈',
        _ => itemEmoji[key] ?? '🎁',
      };

  String _cellName(String slot, String key) => switch (slot) {
        'skin' => skinLabel[key] ?? key,
        'emblem' => emblemLabel[key] ?? key,
        'head' => headLabel[key] ?? key,
        'carrier' => carrierLabel[key] ?? key,
        'aura' => auraLabel[key] ?? key,
        _ => itemLabel[key] ?? key,
      };
}
