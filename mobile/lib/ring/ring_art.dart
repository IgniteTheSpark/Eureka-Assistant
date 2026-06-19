import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Stylized gold ring placeholder (stand-in for a photoreal asset of BCL603S).
class RingArt extends StatelessWidget {
  const RingArt({super.key, this.size = 140});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _RingPainter()),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.width * 0.24;
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Gold body — sweep gradient gives a metallic sheen around the band.
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = const SweepGradient(
        colors: [
          Color(0xFF7A5A22),
          Color(0xFFF6E27A),
          Color(0xFFC9971B),
          Color(0xFFFFF3B0),
          Color(0xFF8A6A2F),
          Color(0xFF7A5A22),
        ],
        stops: [0.0, 0.25, 0.5, 0.7, 0.9, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, body);

    // Soft top highlight.
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.22
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawArc(rect, math.pi * 1.15, math.pi * 0.5, false, highlight);

    // Inner/outer edge shading for depth.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withValues(alpha: 0.25);
    canvas.drawCircle(center, radius + stroke / 2 - 1, edge);
    canvas.drawCircle(center, radius - stroke / 2 + 1, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
