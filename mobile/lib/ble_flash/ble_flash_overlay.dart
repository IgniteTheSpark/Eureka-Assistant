import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BleFlashOverlay extends StatefulWidget {
  const BleFlashOverlay({super.key});

  @override
  State<BleFlashOverlay> createState() => _BleFlashOverlayState();
}

class _BleFlashOverlayState extends State<BleFlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(decoration: TextDecoration.none),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final pulse = 0.5 + 0.5 * math.sin(_ctrl.value * 2 * math.pi);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xF2090B14),
                    const Color(0xF2151630),
                    pulse,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _LightningPainter(
                        progress: _ctrl.value,
                        brand: eu.brand,
                        accent: eu.accentPurple,
                      ),
                    ),
                    Center(
                      child: Transform.scale(
                        scale: 1 + 0.04 * pulse,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 132,
                              height: 132,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: eu.brand.withValues(alpha: 0.45),
                                    blurRadius: 48 + 18 * pulse,
                                    spreadRadius: 6 + 8 * pulse,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.bolt_rounded,
                                color: const Color(0xFFFFF4A8),
                                size: 76,
                                shadows: [
                                  Shadow(
                                    color: eu.brand.withValues(alpha: 0.8),
                                    blurRadius: 22,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              '闪念已开启',
                              style: TextStyle(
                                color: Colors.white,
                                decoration: TextDecoration.none,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '正在接收硬件实时闪念',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                decoration: TextDecoration.none,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LightningPainter extends CustomPainter {
  const _LightningPainter({
    required this.progress,
    required this.brand,
    required this.accent,
  });

  final double progress;
  final Color brand;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final flashAlpha = _flashAlpha(progress);
    _paintSweep(canvas, size, flashAlpha);
    _paintBolt(
      canvas,
      size,
      seed: 1,
      start: Offset(size.width * 0.18, -20),
      end: Offset(size.width * 0.48, size.height * 0.58),
      alpha: flashAlpha,
    );
    _paintBolt(
      canvas,
      size,
      seed: 2,
      start: Offset(size.width * 0.86, -10),
      end: Offset(size.width * 0.58, size.height * 0.64),
      alpha: (flashAlpha * 0.72).clamp(0.0, 1.0),
    );
    _paintBolt(
      canvas,
      size,
      seed: 3,
      start: Offset(size.width * 0.35, size.height + 18),
      end: Offset(size.width * 0.52, size.height * 0.5),
      alpha: (flashAlpha * 0.45).clamp(0.0, 1.0),
    );
  }

  void _paintSweep(Canvas canvas, Size size, double alpha) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(math.sin(progress * 2 * math.pi) * 0.34, -0.12),
        radius: 0.78,
        colors: [
          brand.withValues(alpha: 0.28 + 0.2 * alpha),
          accent.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _paintBolt(
    Canvas canvas,
    Size size, {
    required int seed,
    required Offset start,
    required Offset end,
    required double alpha,
  }) {
    if (alpha <= 0.04) return;
    final points = _boltPoints(start, end, seed);
    final glowPaint = Paint()
      ..color = brand.withValues(alpha: 0.42 * alpha)
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94 * alpha)
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final hotPaint = Paint()
      ..color = const Color(0xFFFFF3A3).withValues(alpha: 0.86 * alpha)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas
      ..drawPath(path, glowPaint)
      ..drawPath(path, corePaint)
      ..drawPath(path, hotPaint);
  }

  List<Offset> _boltPoints(Offset start, Offset end, int seed) {
    const segments = 8;
    final randomPhase = (progress * 12 + seed * 2.17).floorToDouble();
    final points = <Offset>[];
    final direction = end - start;
    final normal = Offset(-direction.dy, direction.dx);
    final normalLength = normal.distance == 0 ? 1.0 : normal.distance;
    final unitNormal = normal / normalLength;

    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final base = Offset.lerp(start, end, t)!;
      final wave =
          math.sin((t * 6.0 + seed + randomPhase) * math.pi) *
          (18 + 10 * math.sin(progress * 2 * math.pi + seed));
      final notch = (i.isEven ? 1.0 : -1.0) * (10 + seed * 2);
      points.add(base + unitNormal * (wave + notch));
    }
    return points;
  }

  double _flashAlpha(double value) {
    final wave = math.sin(value * 2 * math.pi);
    final sharp = math.pow((wave + 1) / 2, 3).toDouble();
    final flicker = (value * 10).floor().isEven ? 1.0 : 0.45;
    return (0.32 + sharp * flicker).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _LightningPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.brand != brand ||
        oldDelegate.accent != accent;
  }
}
