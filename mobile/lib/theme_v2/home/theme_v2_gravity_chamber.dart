import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

const double themeV2HomePanelRadius = 19;

class ThemeV2GravityChamber extends StatelessWidget {
  const ThemeV2GravityChamber({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(themeV2HomePanelRadius),
        bottomRight: Radius.circular(themeV2HomePanelRadius),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tokens.surface.withValues(alpha: 0),
                  tokens.surface.withValues(alpha: 0.72),
                  tokens.background.withValues(alpha: 0.9),
                ],
                stops: const [0, 0.18, 1],
              ),
            ),
          ),
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _GravityChamberBorderPainter(
                color: tokens.border.withValues(alpha: 0.78),
                radius: themeV2HomePanelRadius,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GravityChamberBorderPainter extends CustomPainter {
  const _GravityChamberBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(0.5, 48)
      ..lineTo(0.5, size.height - radius)
      ..quadraticBezierTo(0.5, size.height - 0.5, radius, size.height - 0.5)
      ..lineTo(size.width - radius, size.height - 0.5)
      ..quadraticBezierTo(
        size.width - 0.5,
        size.height - 0.5,
        size.width - 0.5,
        size.height - radius,
      )
      ..lineTo(size.width - 0.5, 48);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GravityChamberBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
