import 'dart:math' as math;

import 'package:flutter/material.dart';

class TodayRekaFallbackPainter extends CustomPainter {
  const TodayRekaFallbackPainter();

  static const _shell = Color(0xFFF4F1EA);
  static const _shellShadow = Color(0xFF9A9995);
  static const _visor = Color(0xFF17181C);
  static const _deepShadow = Color(0xFF424348);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 216;
    canvas.save();
    canvas.scale(scale, scale);

    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(31, 54, 154, 111),
      const Radius.circular(54),
    );
    final visor = RRect.fromRectAndRadius(
      const Rect.fromLTWH(43, 68, 130, 78),
      const Radius.circular(36),
    );
    final leftModule = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 84, 29, 54),
      const Radius.circular(10),
    );
    final rightModule = RRect.fromRectAndRadius(
      const Rect.fromLTWH(169, 84, 29, 54),
      const Radius.circular(10),
    );

    canvas.drawRRect(leftModule, Paint()..color = _shell);
    canvas.drawRRect(rightModule, Paint()..color = _shell);
    canvas.drawRRect(body, Paint()..color = _shell);
    canvas.drawRRect(visor, Paint()..color = _visor);

    _ditherRegion(canvas, leftModule.outerRect, _shellShadow, 4, .34);
    _ditherRegion(canvas, rightModule.outerRect, _shellShadow, 4, .34);
    _ditherRegion(
      canvas,
      const Rect.fromLTWH(39, 120, 138, 40),
      _shellShadow,
      4,
      .42,
      clip: body,
    );
    _ditherRegion(
      canvas,
      const Rect.fromLTWH(48, 112, 120, 30),
      _deepShadow,
      4,
      .24,
      clip: visor,
    );

    canvas.restore();
  }

  void _ditherRegion(
    Canvas canvas,
    Rect region,
    Color color,
    double cell,
    double density, {
    RRect? clip,
  }) {
    canvas.save();
    if (clip != null) canvas.clipRRect(clip);
    final paint = Paint()..color = color;
    final columns = (region.width / cell).ceil();
    final rows = (region.height / cell).ceil();
    const bayer = <int>[0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

    for (var row = 0; row < rows; row++) {
      final vertical = rows <= 1 ? 1.0 : row / (rows - 1);
      for (var column = 0; column < columns; column++) {
        final threshold = (bayer[(row % 4) * 4 + column % 4] + .5) / 16;
        final wave = .82 + .18 * math.sin((column + row) * .72);
        if (threshold > density * vertical * wave) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            region.left + column * cell,
            region.top + row * cell,
            cell * .62,
            cell * .62,
          ),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TodayRekaFallbackPainter oldDelegate) => false;
}
