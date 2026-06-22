import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart'; // context.eu
import '../theme/domains.dart' show domainColor;
import 'bubble_physics.dart';
import 'today_data.dart';

/// Part 2 (back layer) — the physics bubble pool. Each of today's captured assets
/// is a falling/colliding/settling bubble behind the frosted panels. Domain =
/// fill color (§8), type = centered glyph. Driven by one [Ticker] that sleeps
/// when every body sleeps and stops when the page is hidden/backgrounded
/// (battery). Solver = bubble_physics.dart (unit-tested). Plan: Slice 4.
class BubblePool extends StatefulWidget {
  const BubblePool({super.key, required this.pool, this.active = true});

  final List<PoolAsset> pool;

  /// Whether the today tab is the visible one. When false the ticker + (later)
  /// the accelerometer are suspended even if bodies are still moving.
  final bool active;

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

  /// Run the ticker only while: the tab is active, the app is foregrounded, and
  /// ≥1 body is awake. Otherwise stop it.
  void _syncRunning() {
    final foreground = WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed ||
        WidgetsBinding.instance.lifecycleState == null;
    final shouldRun =
        widget.active && foreground && (_field?.anyAwake ?? false);
    if (shouldRun) {
      if (!(_ticker?.isActive ?? false)) _ticker?.start();
    } else {
      if (_ticker?.isActive ?? false) _ticker?.stop();
    }
  }

  void _rebuildField(Size box) {
    _box = box;
    _poolKey = _keyOf(widget.pool);
    _byId
      ..clear()
      ..addEntries(widget.pool.map((a) => MapEntry(a.id, a)));
    if (box == Size.zero || widget.pool.isEmpty) {
      _field = null;
      return;
    }
    _field = BubbleField(
      box: box,
      bubbles: _spawn(widget.pool, box),
      navAabb: _navAabb(box),
    );
    _field!.wakeAll();
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
          x: r * 1.5 + (cols == 1 ? 0 : (i % cols) * span) + (i.isEven ? 5 : -5),
          y: r * 2 + (i ~/ cols) * (r * 1.5),
          r: r,
        ),
    ];
  }

  /// The floating dock pill, in pool coordinates (bottom-centered), as an AABB
  /// collider so bodies slide past its sides instead of piling behind it.
  Rect _navAabb(Size box) => Rect.fromCenter(
        center: Offset(box.width / 2, box.height - 54),
        width: 220,
        height: 66,
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
        return CustomPaint(
          size: box,
          painter: _BubblePainter(
            field: field,
            repaint: _repaint,
            colorOf: (id) => domainColor(eu, _byId[id]?.domain ?? ''),
            glyphOf: (id) => _glyphFor(_byId[id]?.type ?? ''),
          ),
        );
      },
    );
  }

  Widget _empty() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🫧', style: TextStyle(fontSize: 34)),
            SizedBox(height: 10),
            Text('今天还没有记录',
                style: TextStyle(
                    color: Color(0xD0FFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('记一笔、拍张名片、说个念头，都会落到这里',
                style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),
          ],
        ),
      );
}

/// type (skill name) → glyph. Matches the app's canonical built-ins (todo 📋,
/// notes ✍️) so a bubble reads the same as the item does elsewhere.
String _glyphFor(String type) {
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

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.field,
    required this.colorOf,
    required this.glyphOf,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BubbleField field;
  final Color Function(String id) colorOf;
  final String Function(String id) glyphOf;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in field.bubbles) {
      final c = Offset(b.x, b.y);
      final col = colorOf(b.id);
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
            text: glyphOf(b.id), style: TextStyle(fontSize: b.r * 0.85)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false; // repaint via Listenable
}
