import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TodayDitherShape { circle, strip, field }

const _bayer4 = <int>[0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

int bayer4(int x, int y) => _bayer4[(y % 4) * 4 + (x % 4)];

Offset todayDitherDrift({
  required int seed,
  required double phase,
  required double flow,
}) {
  if (flow == 0) return Offset.zero;
  final offset = (seed & 0xFF) / 255;
  final angle = (phase + offset) * math.pi * 2;
  return Offset(math.sin(angle), math.cos(angle * .73)) * flow;
}

class TodayDitherMaterial extends StatelessWidget {
  const TodayDitherMaterial({
    super.key,
    required this.shape,
    required this.color,
    required this.strength,
    this.seed = 0,
    this.step = 4,
    this.dotSize = 2.2,
    this.motion,
    this.flow = 0,
    this.child,
  });

  final TodayDitherShape shape;
  final Color color;
  final double strength;
  final int seed;
  final double step;
  final double dotSize;
  final Animation<double>? motion;
  final double flow;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: TodayDitherPainter(
      shape: shape,
      color: color,
      strength: strength,
      seed: seed,
      step: step,
      dotSize: dotSize,
      motion: motion,
      flow: flow,
    ),
    child: child,
  );
}

class TodayDitherPainter extends CustomPainter {
  const TodayDitherPainter({
    required this.shape,
    required this.color,
    required this.strength,
    this.seed = 0,
    this.step = 4,
    this.dotSize = 2.2,
    this.motion,
    this.flow = 0,
  }) : super(repaint: motion);

  final TodayDitherShape shape;
  final Color color;
  final double strength;
  final int seed;
  final double step;
  final double dotSize;
  final Animation<double>? motion;
  final double flow;

  double coverageAt(Size size, Offset point) {
    if (size.isEmpty ||
        point.dx < 0 ||
        point.dy < 0 ||
        point.dx > size.width ||
        point.dy > size.height) {
      return 0;
    }
    final amount = strength.clamp(0.0, 1.0);
    switch (shape) {
      case TodayDitherShape.circle:
        final radius = math.min(size.width, size.height) / 2;
        if (radius <= 0) return 0;
        final distance = (point - size.center(Offset.zero)).distance / radius;
        if (distance >= 1) return 0;
        final edge = ((1 - distance) / .22).clamp(0.0, 1.0);
        return amount * (.72 + .28 * edge);
      case TodayDitherShape.strip:
        final radius = math.min(24.0, size.height / 2);
        final rect = RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        );
        return rect.contains(point) ? amount : 0;
      case TodayDitherShape.field:
        final center = size.center(Offset.zero);
        final dx = (point.dx - center.dx) / math.max(1, size.width * .52);
        final dy = (point.dy - center.dy) / math.max(1, size.height * .58);
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance >= 1) return 0;
        final fade = 1 - distance;
        return amount * fade * fade;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0 || step <= 0 || dotSize <= 0) return;
    final phase = motion?.value ?? 0;
    final drift = todayDitherDrift(seed: seed, phase: phase, flow: flow);
    final seedPhase = (seed & 0x3FF) / 1023;
    final breath = 1 + math.sin((phase + seedPhase) * math.pi * 2) * .08;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    final xCount = (size.width / step).ceil();
    final yCount = (size.height / step).ceil();
    final seedX = seed & 3;
    final seedY = (seed >> 2) & 3;
    for (var y = -1; y <= yCount; y++) {
      for (var x = -1; x <= xCount; x++) {
        final center = Offset(
          (x + .5 + drift.dx) * step,
          (y + .5 + drift.dy) * step,
        );
        final coverage = coverageAt(size, center) * breath;
        final threshold = (bayer4(x + seedX, y + seedY) + .5) / 16;
        if (coverage <= threshold) continue;
        canvas.drawRect(
          Rect.fromCenter(center: center, width: dotSize, height: dotSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TodayDitherPainter oldDelegate) =>
      shape != oldDelegate.shape ||
      color != oldDelegate.color ||
      strength != oldDelegate.strength ||
      seed != oldDelegate.seed ||
      step != oldDelegate.step ||
      dotSize != oldDelegate.dotSize ||
      motion != oldDelegate.motion ||
      flow != oldDelegate.flow;
}
