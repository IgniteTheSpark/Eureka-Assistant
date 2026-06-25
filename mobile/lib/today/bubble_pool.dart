import 'dart:async';
import 'dart:math' as math;

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
    this.filterKey = 'all',
    this.highlightId,
    this.onSwipe,
  });

  final List<PoolAsset> pool;

  /// skill_name → {icon, label}; the bubble glyph resolves through this so a
  /// custom skill shows ITS icon, not a hardcoded guess (resolveMeta fallback).
  final Map<String, SkillMeta> skills;

  /// Whether the today tab is the visible one. When false the ticker + the
  /// accelerometer are suspended even if bodies are still moving.
  final bool active;

  /// Dashboard filter — bubbles whose type doesn't match are dimmed ('all' =
  /// none dimmed).
  final String filterKey;

  /// A bubble to light up (tapped from the dashboard's latest row); null = none.
  final String? highlightId;

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
              final vx = dets.velocity.pixelsPerSecond.dx;
              // horizontal-dominant past a distance or fling threshold → switch.
              if (dx.abs() > _swipeDelta.dy.abs() &&
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
              filterKey: widget.filterKey,
              highlightId: widget.highlightId,
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
    required this.filterKey,
    required this.highlightId,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BubbleField field;
  final Color Function(String id) colorOf;
  final String Function(String id) glyphOf;
  final String Function(String id) typeOf;
  final String filterKey;
  final String? highlightId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in field.bubbles) {
      final c = Offset(b.x, b.y);
      final col = colorOf(b.id);
      // When a bubble is highlighted (dashboard latest-row tap) recede every
      // other bubble so it visibly lights up; otherwise honor the filter dim.
      final dim = highlightId != null
          ? b.id != highlightId
          : (filterKey != 'all' && typeOf(b.id) != filterKey);
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
    // Highlight (dashboard latest-row tap): a glowing accent ring on top of the
    // pile so the tapped record's bubble lights up.
    if (highlightId != null) {
      for (final b in field.bubbles) {
        if (b.id != highlightId) continue;
        final c = Offset(b.x, b.y);
        // glowing ring (thick + blurred) — reads as "lit up" over the pile.
        canvas.drawCircle(
          c,
          b.r + 8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = const Color(0xFF8AB4FF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        // crisp bright ring hugging the bubble
        canvas.drawCircle(
          c,
          b.r + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFFEAF2FF),
        );
        break;
      }
    }
  }

  // Per-frame repaint is driven by the Listenable; repaint on a filter or
  // highlight change (the painter instance changes without a Listenable tick).
  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.filterKey != filterKey || old.highlightId != highlightId;
}
