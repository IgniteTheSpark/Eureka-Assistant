import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/domains.dart' show domainColor;
import '../theme/eureka_colors.dart';
import 'bubble_pool.dart' show typeName;
import 'today_data.dart';
import 'today_palette.dart';

/// Treemap cell layout — slice-along-the-longer-side (a squarified approximation):
/// guarantees area ∝ value, full union of [rect], and no overlap, while keeping
/// aspect ratios reasonable for the small group counts the dashboard charts use.
/// Returns one Rect per input value, in input order. Pure → unit-tested
/// (test/charts_squarify_test.dart).
List<Rect> squarify(List<double> values, Rect rect) {
  if (values.isEmpty) return const [];
  final total = values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return List<Rect>.filled(values.length, Rect.zero);

  final out = <Rect>[];
  var free = rect;
  var remaining = total;
  for (var i = 0; i < values.length; i++) {
    if (i == values.length - 1) {
      out.add(free); // last cell takes all remaining free area
      break;
    }
    final frac = values[i] / remaining;
    if (free.width >= free.height) {
      final w = free.width * frac;
      out.add(Rect.fromLTWH(free.left, free.top, w, free.height));
      free = Rect.fromLTWH(
        free.left + w,
        free.top,
        free.width - w,
        free.height,
      );
    } else {
      final h = free.height * frac;
      out.add(Rect.fromLTWH(free.left, free.top, free.width, h));
      free = Rect.fromLTWH(
        free.left,
        free.top + h,
        free.width,
        free.height - h,
      );
    }
    remaining -= values[i];
  }
  return out;
}

/// One chart slice: a label, a count, and its color.
class ChartGroup {
  const ChartGroup(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}

// Type-grouping palette (domain grouping uses domainColor instead).
const _palette = [
  Color(0xFF8AB4FF),
  Color(0xFF84C9A0),
  Color(0xFFF5C977),
  Color(0xFFB89CF0),
  Color(0xFF6FD0D8),
  Color(0xFFF08A8A),
  Color(0xFFEBA6C9),
];

/// Count-based grouping with drill-down: filter=='all' groups by **type** (palette
/// colors); a specific type groups by **domain** (§8 colors). Sorted desc by count.
List<ChartGroup> chartGroups(
  EurekaColors eu,
  String filterKey,
  List<PoolAsset> pool,
) {
  final counts = <String, int>{};
  if (filterKey == 'all') {
    for (final a in pool) {
      counts.update(a.type, (v) => v + 1, ifAbsent: () => 1);
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (var i = 0; i < entries.length; i++)
        ChartGroup(
          typeName(entries[i].key),
          entries[i].value,
          _palette[i % _palette.length],
        ),
    ];
  }
  for (final a in pool.where((x) => x.type == filterKey)) {
    final d = a.domain.isEmpty ? '其他' : a.domain;
    counts.update(d, (v) => v + 1, ifAbsent: () => 1);
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in entries)
      ChartGroup(
        e.key,
        e.value,
        e.key == '其他' ? const Color(0xFF6B7280) : domainColor(eu, e.key),
      ),
  ];
}

void _text(
  Canvas c,
  String s,
  Offset at, {
  required Color color,
  double size = 11,
  FontWeight weight = FontWeight.w500,
  double maxWidth = 240,
  bool centerX = false,
  bool rightX = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: color, fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  var dx = at.dx;
  if (centerX) dx -= tp.width / 2;
  if (rightX) dx -= tp.width;
  tp.paint(c, Offset(dx, at.dy));
}

class _RosePainter extends CustomPainter {
  _RosePainter(this.g, this.palette);
  final List<ChartGroup> g;
  final TodayPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    if (g.isEmpty) return;
    final roseW = size.height; // square rose region on the left
    final cx = roseW / 2, cy = size.height / 2;
    final maxR = size.height / 2 - 4;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.chartStroke;
    if (g.length == 1) {
      // a single group is a full pie disc (a 360° wedge degenerates to nothing).
      canvas.drawCircle(Offset(cx, cy), maxR, Paint()..color = g[0].color);
      canvas.drawCircle(Offset(cx, cy), maxR, stroke);
    } else {
      final maxCount = g.map((e) => e.count).reduce(math.max);
      final sweep = 2 * math.pi / g.length;
      for (var i = 0; i < g.length; i++) {
        final r = maxR * (0.32 + 0.68 * g[i].count / maxCount);
        final start = -math.pi / 2 + i * sweep;
        final path = Path()
          ..moveTo(cx, cy)
          ..arcTo(
            Rect.fromCircle(center: Offset(cx, cy), radius: r),
            start,
            sweep,
            false,
          )
          ..close();
        canvas.drawPath(path, Paint()..color = g[i].color);
        canvas.drawPath(path, stroke);
      }
    }
    // Legend fills the right area: chip + label (left), count right-aligned to
    // the panel edge — so there's no big dead gap between rose and text.
    const rowH = 22.0;
    final legendLeft = roseW + 14;
    var ly = (size.height - g.length * rowH) / 2 + 3;
    for (final e in g) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legendLeft, ly + 1, 11, 11),
          const Radius.circular(3),
        ),
        Paint()..color = e.color,
      );
      _text(
        canvas,
        e.label,
        Offset(legendLeft + 18, ly),
        color: palette.body,
        maxWidth: size.width - legendLeft - 52,
      );
      _text(
        canvas,
        '${e.count}',
        Offset(size.width, ly),
        color: palette.body,
        weight: FontWeight.w700,
        rightX: true,
      );
      ly += rowH;
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.g, this.palette);
  final List<ChartGroup> g;
  final TodayPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    if (g.isEmpty) return;
    final n = g.length;
    const gap = 12.0;
    final barW = ((size.width - gap * (n + 1)) / n).clamp(8.0, 64.0);
    final maxCount = g.map((e) => e.count).reduce(math.max);
    final chartH = size.height - 30; // room for count above + label below
    for (var i = 0; i < n; i++) {
      final h = (chartH * g[i].count / maxCount).clamp(3.0, chartH);
      final x = gap + i * (barW + gap);
      final y = 16 + (chartH - h);
      final rect = Rect.fromLTWH(x, y, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [g[i].color, Color.lerp(g[i].color, Colors.black, 0.22)!],
          ).createShader(rect),
      );
      _text(
        canvas,
        '${g[i].count}',
        Offset(x + barW / 2, y - 15),
        color: palette.body,
        centerX: true,
        weight: FontWeight.w700,
      );
      _text(
        canvas,
        g[i].label,
        Offset(x + barW / 2, 16 + chartH + 4),
        color: palette.body,
        size: 10,
        centerX: true,
        maxWidth: barW + gap,
      );
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _TreemapPainter extends CustomPainter {
  _TreemapPainter(this.g, this.palette);
  final List<ChartGroup> g;
  final TodayPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    if (g.isEmpty) return;
    final cells = squarify(
      g.map((e) => e.count.toDouble()).toList(),
      Offset.zero & size,
    );
    for (var i = 0; i < g.length; i++) {
      final r = cells[i].deflate(1.5);
      if (r.width <= 0 || r.height <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        Paint()..color = g[i].color.withValues(alpha: .82),
      );
      if (r.width > 34 && r.height > 22) {
        _text(
          canvas,
          g[i].label,
          Offset(r.left + 6, r.top + 5),
          color: Colors.white,
          size: 11,
          maxWidth: r.width - 10,
        );
        _text(
          canvas,
          '${g[i].count}',
          Offset(r.right - 6, r.bottom - 17),
          color: const Color(0xCCFFFFFF),
          size: 12,
          weight: FontWeight.w700,
          rightX: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

/// The dashboard's chart: rose / bar / treemap over [groups], with a scope label,
/// a selector, and swipe-to-cycle. Empty groups → a quiet placeholder.
class ChartView extends StatefulWidget {
  const ChartView({
    super.key,
    required this.groups,
    required this.scopeLabel,
    required this.palette,
  });
  final List<ChartGroup> groups;
  final String scopeLabel;
  final TodayPalette palette;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  int _type = 0; // 0 rose · 1 bar · 2 tree
  static const _names = ['✿ 玫瑰', '▥ 柱状', '◳ 树图'];

  @override
  Widget build(BuildContext context) {
    final g = widget.groups;
    final p = widget.palette;
    final painter = switch (_type) {
      1 => _BarPainter(g, p),
      2 => _TreemapPainter(g, p),
      _ => _RosePainter(g, p),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Text(
            widget.scopeLabel,
            style: TextStyle(color: p.faint, fontSize: 11),
          ),
        ),
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -100) setState(() => _type = (_type + 1) % 3);
            if (v > 100) setState(() => _type = (_type + 2) % 3);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
                  child: child,
                ),
              ),
              child: SizedBox(
                key: ValueKey(_type),
                height: 118,
                width: double.infinity,
                child: g.isEmpty
                    ? Center(
                        child: Text(
                          '暂无可视化数据',
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      )
                    : CustomPaint(painter: painter),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                GestureDetector(
                  onTap: () => setState(() => _type = i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _type == i
                          ? p.accent.withValues(alpha: 0.22)
                          : p.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _names[i],
                      style: TextStyle(
                        color: _type == i ? p.accentSoft : p.muted,
                        fontSize: 11,
                        fontWeight: _type == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
