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
import 'bubble_physics.dart';
import 'today_data.dart';
import 'today_palette.dart';

/// Part 2 (back layer) — the physics bubble pool. Each of today's captured assets
/// is a falling/colliding/settling bubble behind the frosted panels. Domain =
/// fill color (§8), type = centered glyph. Driven by one [Ticker] that sleeps
/// when every body sleeps and stops when the page is hidden/backgrounded
/// (battery). Solver = bubble_physics.dart (unit-tested). Plan: Slice 4.
class BubblePool extends StatefulWidget {
  const BubblePool({
    super.key,
    required this.pool,
    this.active = true,
    this.filterKey = 'all',
    this.highlightId,
  });

  final List<PoolAsset> pool;

  /// Whether the today tab is the visible one. When false the ticker + the
  /// accelerometer are suspended even if bodies are still moving.
  final bool active;

  /// Dashboard filter — bubbles whose type doesn't match are dimmed ('all' =
  /// none dimmed).
  final String filterKey;

  /// A bubble to light up (tapped from the dashboard's latest row); null = none.
  final String? highlightId;

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
  Bubble? _held; // bubble currently dragged
  Offset _lastDelta = Offset.zero; // recent finger delta → throw velocity
  StreamSubscription<AccelerometerEvent>? _accel;
  Offset _gravity = const Offset(0, 0.44); // current (tilt-driven) gravity

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
  static const double _gMag = 0.44;
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
        _field != null && box == _box; // same field, pool just changed
    _box = box;
    _poolKey = _keyOf(widget.pool);
    _byId
      ..clear()
      ..addEntries(widget.pool.map((a) => MapEntry(a.id, a)));
    if (box == Size.zero || widget.pool.isEmpty) {
      _field = null;
      return;
    }
    final existing = reuse
        ? {for (final b in _field!.bubbles) b.id: b}
        : const <String, Bubble>{};
    final spawned = _spawn(widget.pool, box);
    final bubbles = <Bubble>[
      for (var i = 0; i < widget.pool.length; i++)
        existing[widget.pool[i].id] ??
            // a new record drops in from above the ceiling (reuse), or joins the
            // initial staggered layout (first build / resize).
            (Bubble(
              id: widget.pool[i].id,
              x: spawned[i].x,
              y: reuse ? -23.0 : spawned[i].y,
              r: 23,
            )..wake()),
    ];
    _field = BubbleField(
      box: box,
      bubbles: bubbles,
      navAabb: _navAabb(box),
      gravity: _gravity,
    );
    if (!reuse) _field!.wakeAll();
    _syncRunning();
  }

  /// Stagger bodies across the upper area; gravity settles them into a pile.
  List<Bubble> _spawn(List<PoolAsset> pool, Size box) {
    const r = 23.0;
    final cols = math.max(1, (box.width / (r * 2.6)).floor());
    final span = (box.width - r * 3) / math.max(1, cols - 1);
    return [
      for (var i = 0; i < pool.length; i++)
        Bubble(
          id: pool[i].id,
          x:
              r * 1.5 +
              (cols == 1 ? 0 : (i % cols) * span) +
              (i.isEven ? 5 : -5),
          y: r * 2 + (i ~/ cols) * (r * 1.5),
          r: r,
        ),
    ];
  }

  /// The floating dock pill, in pool coordinates, as an AABB collider so bodies
  /// slide past its sides instead of piling behind it. Matches FloatingDock:
  /// bottom-centered, ~14 above the bottom, ~180×52 (the solver inflates by r).
  Rect _navAabb(Size box) => Rect.fromCenter(
    center: Offset(box.width / 2, box.height - 40),
    width: 180,
    height: 52,
  );

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    if (widget.pool.isEmpty) return _empty();
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
            final b = _hit(field, d.localPosition);
            if (b != null) openAssetSheet(context, _byId[b.id]!);
          },
          onPanStart: (d) {
            final b = _hit(field, d.localPosition);
            if (b != null) {
              _held = b;
              field.held = b;
              b
                ..wake()
                ..vx = 0
                ..vy = 0;
              _syncRunning();
            }
          },
          onPanUpdate: (d) {
            final h = _held;
            if (h == null) return;
            h.x = d.localPosition.dx.clamp(h.r, box.width - h.r);
            h.y = d.localPosition.dy.clamp(h.r, box.height - h.r);
            _lastDelta = d.delta;
            h.wake();
            _syncRunning();
            _repaint.value++;
          },
          onPanEnd: (_) {
            final h = _held;
            if (h == null) return;
            const mx = BubbleField.maxSpeed;
            h
              ..vx = _lastDelta.dx.clamp(-mx, mx)
              ..vy = _lastDelta.dy.clamp(-mx, mx);
            field.held = null;
            _held = null;
            _syncRunning();
          },
          child: CustomPaint(
            size: box,
            painter: _BubblePainter(
              field: field,
              repaint: _repaint,
              filterKey: widget.filterKey,
              highlightId: widget.highlightId,
              colorOf: (id) => domainColor(eu, _byId[id]?.domain ?? ''),
              glyphOf: (id) => glyphForType(_byId[id]?.type ?? ''),
              typeOf: (id) => _byId[id]?.type ?? '',
            ),
          ),
        );
      },
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🫧', style: TextStyle(fontSize: 34)),
        const SizedBox(height: 10),
        Text(
          '今天还没有记录',
          style: TextStyle(
            color: TodayPalette.of(context).body,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  /// Nearest bubble to [p] within its radius (+ slop), else null.
  Bubble? _hit(BubbleField field, Offset p) {
    Bubble? best;
    var bestD = double.infinity;
    for (final b in field.bubbles) {
      final dx = b.x - p.dx, dy = b.y - p.dy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= b.r + 6 && d < bestD) {
        best = b;
        bestD = d;
      }
    }
    return best;
  }
}

/// type (skill name) → glyph. Matches the app's canonical built-ins (todo 📋,
/// notes ✍️) so a bubble reads the same as the item does elsewhere.
String glyphForType(String type) {
  switch (type) {
    case 'todo':
      return '📋';
    case 'expense':
      return '💰';
    case 'contact':
      return '👤';
    case 'notes':
    case 'idea':
    case 'misc':
      return '✍️';
    case 'running':
      return '🎾';
    default:
      return '•';
  }
}

/// type (skill name) → display name for the detail sheet's type pill.
String typeName(String type) {
  switch (type) {
    case 'todo':
      return '待办';
    case 'expense':
      return '记账';
    case 'contact':
      return '名片';
    case 'notes':
    case 'idea':
    case 'misc':
      return '随记';
    case 'running':
      return '运动';
    default:
      return type;
  }
}

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
