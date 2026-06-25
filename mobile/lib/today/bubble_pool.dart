import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../render/asset_detail_sheet.dart' show showAssetDetail;
import '../render/render_spec.dart' show RenderSpec, buildCard, synthesizeSpec;
import '../render/skill_card.dart' show renderSpecsProvider;
import '../theme/app_theme.dart'; // context.eu
import '../theme/domains.dart' show domainColor;
import '../timeline/timeline.dart' show SkillMeta, resolveMeta;
import 'bubble_physics.dart';
import 'today_data.dart';
import 'today_palette.dart';

/// Part 2 (back layer) — the physics bubble pool. Each of today's captured assets
/// is a falling/colliding/settling bubble behind the frosted panels. Domain =
/// fill color (§8), type = centered glyph. Driven by one [Ticker] that sleeps
/// when every body sleeps and stops when the page is hidden/backgrounded
/// (battery). Physics = forge2d (Box2D) in bubble_physics.dart. Plan: Slice 4.
class BubblePool extends StatefulWidget {
  const BubblePool({
    super.key,
    required this.pool,
    this.skills = const {},
    this.active = true,
    this.onSwipe,
  });

  final List<PoolAsset> pool;

  /// skill_name → {icon, label}; the bubble glyph resolves through this so a
  /// custom skill shows ITS icon, not a hardcoded guess (resolveMeta fallback).
  final Map<String, SkillMeta> skills;

  /// Whether the today tab is the visible one. When false the ticker + the
  /// accelerometer are suspended even if bodies are still moving.
  final bool active;

  /// Background horizontal swipe (a pan that does NOT start on a bubble) → switch
  /// the foreground screen (dir -1 = 今日安排 / +1 = Reka Offer). The pool owns the
  /// background gesture, so it arbitrates bubble-drag vs screen-swipe here (S2d).
  final void Function(int dir)? onSwipe;

  @override
  State<BubblePool> createState() => _BubblePoolState();
}

class _BubblePoolState extends State<BubblePool>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Ticker? _ticker;
  BubbleField? _field;
  Size _box = Size.zero;
  String _poolKey = '';
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final Map<String, PoolAsset> _byId = {};
  StreamSubscription<AccelerometerEvent>? _accel;
  Offset _gravity = const Offset(
    0,
    20,
  ); // current (tilt-driven) gravity (world)

  // background-swipe arbitration: a pan starting off any bubble = a screen swipe
  // (→ widget.onSwipe), not a bubble drag.
  bool _swiping = false;
  Offset _swipeDelta = Offset.zero;

  // S4: long-press a bubble → focus its type (dim others + ring matches) while a
  // frosted overlay lists that type's records today.
  String? _focusType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(BubblePool old) {
    super.didUpdateWidget(old);
    if (_keyOf(widget.pool) != _poolKey) _rebuildField(_box);
    _syncRunning();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncRunning();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accel?.cancel();
    _ticker?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  String _keyOf(List<PoolAsset> p) => p.map((a) => a.id).join(',');

  /// §B4 long-press a bubble → frosted overlay of that [type]'s records captured
  /// today; the pool dims all but that type (ringed) until the sheet closes.
  Future<void> _openTypeSheet(String type) async {
    final items = widget.pool.where((a) => a.type == type).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (items.isEmpty) return;
    setState(() => _focusType = type); // dim others + ring matches in the pool
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x80070B14), // §B4 dim over the highlighted pool
      builder: (_) =>
          _TypeSheet(type: type, items: items, skills: widget.skills),
    );
    if (mounted) setState(() => _focusType = null);
  }

  void _onTick(Duration _) {
    final f = _field;
    if (f == null) return;
    if (f.anyAwake) {
      f.step();
      _repaint.value++;
    } else {
      _ticker?.stop(); // settled → stop (no idle frames)
    }
  }

  /// Gate the ticker + tilt sensor on tab-active + app-foreground. The ticker
  /// additionally needs ≥1 awake body; the accelerometer stays subscribed while
  /// live (to catch a fresh tilt) but only a meaningful tilt wakes the pool.
  void _syncRunning() {
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
        WidgetsBinding.instance.lifecycleState == null;
    final live = widget.active && foreground;
    _syncAccel(live);
    final shouldRun = live && (_field?.anyAwake ?? false);
    if (shouldRun) {
      if (!(_ticker?.isActive ?? false)) _ticker?.start();
    } else {
      if (_ticker?.isActive ?? false) _ticker?.stop();
    }
  }

  void _syncAccel(bool on) {
    if (on) {
      _accel ??= accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 66),
      ).listen(_onAccel);
    } else {
      _accel?.cancel();
      _accel = null;
    }
  }

  /// Map device tilt → screen-space gravity: constant magnitude (≈ the default
  /// .44) pointing "downhill", so bodies roll as the phone tilts and rise when
  /// it's flipped. Near-flat (on a desk) falls back to straight down so the pool
  /// still settles at the bottom instead of floating off-screen. Micro-jitter is
  /// ignored so a steady hold lets the pool sleep.
  static const double _gMag = 20.0;
  void _onAccel(AccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y);
    final g = mag < 1.2
        ? const Offset(0, _gMag)
        : Offset(-e.x / mag, e.y / mag) * _gMag;
    if ((g - _gravity).distance < 0.04) return;
    _gravity = g;
    final f = _field;
    if (f != null) {
      f.gravity = g;
      f.wakeAll();
      _syncRunning();
    }
  }

  void _rebuildField(Size box) {
    final reuse =
        _field != null && box == _box; // same world, pool just changed
    _box = box;
    _poolKey = _keyOf(widget.pool);
    _byId
      ..clear()
      ..addEntries(widget.pool.map((a) => MapEntry(a.id, a)));
    if (box == Size.zero || widget.pool.isEmpty) {
      _field = null;
      return;
    }
    if (!reuse) {
      // fresh world: stagger the bodies across the top, let them fall + settle.
      final f = BubbleField(box: box, dock: _dockRect(box), gravity: _gravity);
      final pos = _spawnPositions(widget.pool.length, box);
      for (var i = 0; i < widget.pool.length; i++) {
        f.addBubble(widget.pool[i].id, pos[i], 23);
      }
      _field = f;
    } else {
      // same world: drop new records in from the top; remove gone ones.
      final f = _field!;
      final ids = widget.pool.map((a) => a.id).toSet();
      for (final b in [...f.bubbles]) {
        if (!ids.contains(b.id)) f.removeBubble(b);
      }
      for (var i = 0; i < widget.pool.length; i++) {
        final a = widget.pool[i];
        if (!f.has(a.id)) {
          // drop in just BELOW the ceiling (y>0), never above it — a body spawned
          // above the ceiling edge gets blocked by it and sticks to the top.
          f.addBubble(
            a.id,
            Offset(box.width * (0.3 + 0.4 * ((i % 5) / 4)), 26),
            23,
          );
        }
      }
    }
    _syncRunning();
  }

  /// Staggered spawn positions (px) across the upper area; gravity settles them.
  List<Offset> _spawnPositions(int n, Size box) {
    const r = 23.0;
    final cols = math.max(1, (box.width / (r * 2.6)).floor());
    final span = (box.width - r * 3) / math.max(1, cols - 1);
    return [
      for (var i = 0; i < n; i++)
        Offset(
          r * 1.5 + (cols == 1 ? 0 : (i % cols) * span) + (i.isEven ? 5 : -5),
          r * 2 + (i ~/ cols) * (r * 1.5),
        ),
    ];
  }

  /// The floating dock pill in pool coords (matches FloatingDock: bottom-centered,
  /// ~180×52, ~14 above the bottom). BubbleField turns it into a solid box collider.
  Rect _dockRect(Size box) =>
      Rect.fromLTWH(box.width / 2 - 90, box.height - 66, 180, 52);

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    // Empty pool = silent: the foreground screen's empty state (今日安排空 /
    // Reka Offer 空, with its own guidance) owns the messaging, so we don't stack
    // a second 「今天还没有记录」 prompt behind it on a blank day.
    if (widget.pool.isEmpty) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        if (box != _box || _field == null) {
          // first layout (or rotation): (re)build the field at this size.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (box != _box || _field == null)) {
              setState(() => _rebuildField(box));
            }
          });
        }
        final field = _field;
        if (field == null) return const SizedBox.expand();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final b = field.hit(d.localPosition);
            if (b != null) openAssetSheet(context, _byId[b.id]!);
          },
          onLongPressStart: (d) {
            final b = field.hit(d.localPosition);
            if (b != null) _openTypeSheet(_byId[b.id]!.type);
          },
          onPanStart: (d) {
            final b = field.hit(d.localPosition);
            if (b != null) {
              _swiping = false;
              field.grab(b);
              _syncRunning();
            } else {
              // off any bubble → a screen swipe, arbitrated against bubble-drag.
              _swiping = widget.onSwipe != null;
              _swipeDelta = Offset.zero;
            }
          },
          onPanUpdate: (d) {
            if (_swiping) {
              _swipeDelta += d.delta;
              return;
            }
            field.dragTo(d.localPosition);
            _syncRunning();
          },
          onPanEnd: (dets) {
            if (_swiping) {
              _swiping = false;
              final dx = _swipeDelta.dx;
              final dy = _swipeDelta.dy;
              final vx = dets.velocity.pixelsPerSecond.dx;
              // Switch only when dx CLEARLY dominates dy (1.5×), so a diagonal
              // drag reads as a vertical flick (pool toss) instead of mis-firing
              // a switch; still requires a distance OR fling threshold.
              if (dx.abs() > dy.abs() * 1.5 &&
                  (dx.abs() > 64 || vx.abs() > 600)) {
                widget.onSwipe!(dx < 0 ? 1 : -1);
              }
              return;
            }
            field.release();
          },
          child: CustomPaint(
            size: box,
            painter: _BubblePainter(
              field: field,
              repaint: _repaint,
              // S4 long-press is now the SOLE dim/ring driver (null = nothing
              // focused → every bubble painted full). Dashboard filter/highlight
              // props are gone.
              focusType: _focusType,
              colorOf: (id) => domainColor(eu, _byId[id]?.domain ?? ''),
              glyphOf: (id) =>
                  resolveMeta(_byId[id]?.type ?? '', widget.skills).icon,
              typeOf: (id) => _byId[id]?.type ?? '',
            ),
          ),
        );
      },
    );
  }

}

// NB: the pool bubble glyph + the dashboard category icon/name now resolve a
// skill's real render_spec.icon + display_name via resolveMeta(type, skills)
// (timeline.dart) — so a CUSTOM skill (e.g. 'running') shows ITS icon/name, not
// a hardcoded guess. The old glyphForType/typeName maps lived here.

/// Open the SAME global asset-detail sheet the calendar/library use, from a pool
/// bubble or the dashboard's latest row — builds CardData via buildCard so the
/// sheet (hero + fields + actions, theme-aware) renders identically. No bespoke
/// today-page sheet.
void openAssetSheet(BuildContext context, PoolAsset a) {
  final specs =
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(renderSpecsProvider).valueOrNull ??
      const <String, RenderSpec>{};
  final spec = specs[a.type] ?? synthesizeSpec(a.type);
  final data = buildCard(
    payload: a.payload,
    spec: spec,
    displayName: a.type,
  ).copyWith(domain: a.domain.isEmpty ? null : a.domain);
  showAssetDetail(
    context,
    data: data,
    payload: a.payload,
    cardType: a.type,
    assetId: a.id,
    spec: spec,
  );
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.field,
    required this.colorOf,
    required this.glyphOf,
    required this.typeOf,
    required this.focusType,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BubbleField field;
  final Color Function(String id) colorOf;
  final String Function(String id) glyphOf;
  final String Function(String id) typeOf;

  /// S4: the long-pressed bubble's type (others dim + matches ringed), or null
  /// when nothing is focused → every bubble painted at full.
  final String? focusType;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in field.bubbles) {
      final c = Offset(b.x, b.y);
      final col = colorOf(b.id);
      // S4: a type is focused (long-press) → recede every other type to a faint
      // disc so 同类球 read as highlighted; nothing focused = no dim.
      final dim = focusType != null && typeOf(b.id) != focusType;
      if (dim) {
        // recede non-matching bubbles to a faint disc (no gloss/glyph).
        canvas.drawCircle(c, b.r, Paint()..color = col.withValues(alpha: .14));
        continue;
      }
      // drop shadow
      canvas.drawCircle(
        c.translate(0, 3),
        b.r,
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // body: solid domain color
      final rect = Rect.fromCircle(center: c, radius: b.r);
      canvas.drawCircle(c, b.r, Paint()..color = col);
      // glossy highlight: white top-left → transparent
      canvas.drawCircle(
        c,
        b.r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.32, -0.4),
            radius: 0.95,
            colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
            stops: [0.0, 0.8],
          ).createShader(rect),
      );
      // specular dot
      canvas.drawCircle(
        c.translate(-b.r * 0.32, -b.r * 0.4),
        b.r * 0.16,
        Paint()
          ..color = const Color(0x88FFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      // S4: a type is focused → ring the matching (non-dimmed) bubbles so 同类球
      // read as highlighted (the rest already receded to faint discs above).
      if (focusType != null) {
        canvas.drawCircle(
          c,
          b.r + 1.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = const Color(0xCC6F9EFF),
        );
      }
      // type glyph
      final tp = TextPainter(
        text: TextSpan(
          text: glyphOf(b.id),
          style: TextStyle(fontSize: b.r * 0.85),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  // Per-frame repaint is driven by the Listenable; also repaint when the focused
  // type flips (the painter instance changes without a Listenable tick).
  @override
  bool shouldRepaint(_BubblePainter old) => old.focusType != focusType;
}

/// §B4 长按球 → 同类毛玻璃浮层. Rises from the bottom listing every record of one
/// [type] captured today; the pool behind dims all but that type (ring on the
/// matches). Tapping a row opens the same global detail sheet.
class _TypeSheet extends StatelessWidget {
  const _TypeSheet({
    required this.type,
    required this.items,
    required this.skills,
  });

  final String type;
  final List<PoolAsset> items;
  final Map<String, SkillMeta> skills;

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = TodayPalette.of(context);
    final eu = context.eu;
    final meta = resolveMeta(type, skills);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: p.panelBg,
            border: Border(top: BorderSide(color: p.panelBorder)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.faint,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(meta.icon, style: const TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${meta.label} · 今天 ${items.length} 条',
                          style: TextStyle(
                            color: p.title,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '同类球已在池里高亮',
                          style: TextStyle(color: p.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = items[i];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openAssetSheet(context, a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: p.inset,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.panelBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: domainColor(eu, a.domain),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.body, fontSize: 13),
                              ),
                            ),
                            Text(
                              _hm(a.createdAt),
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
