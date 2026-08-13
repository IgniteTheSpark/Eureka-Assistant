import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class TodayDotMatrixPalette {
  const TodayDotMatrixPalette({
    required this.surface,
    required this.dot,
    required this.rekaDot,
    required this.eye,
    required this.foreground,
    required this.muted,
  });

  static const light = TodayDotMatrixPalette(
    surface: Color(0xFFE3EAE5),
    dot: Color(0x8974837A),
    rekaDot: Color(0xFF607269),
    eye: Color(0xFFC6532F),
    foreground: Color(0xFF18211C),
    muted: Color(0xFF66746C),
  );

  final Color surface;
  final Color dot;
  final Color rekaDot;
  final Color eye;
  final Color foreground;
  final Color muted;
}

@immutable
class TodayDotSceneGeometry {
  const TodayDotSceneGeometry({
    required this.size,
    required this.rekaCenter,
    required this.rekaInfluenceRadius,
    this.gridInterval = 8,
  });

  factory TodayDotSceneGeometry.forSize(Size size) {
    final heightDelta = math.max(0.0, size.height - 860);
    return TodayDotSceneGeometry(
      size: size,
      rekaCenter: Offset(78, 505 + heightDelta * 0.20),
      rekaInfluenceRadius: 92,
    );
  }

  final Size size;
  final Offset rekaCenter;
  final double rekaInfluenceRadius;
  final double gridInterval;
}

class TodayDotMatrixPainter extends CustomPainter {
  const TodayDotMatrixPainter({
    required this.rekaPhase,
    required this.refreshEmphasis,
    required this.reduceMotion,
    required this.devicePixelRatio,
    this.palette = TodayDotMatrixPalette.light,
  });

  final double rekaPhase;
  final double refreshEmphasis;
  final bool reduceMotion;
  final double devicePixelRatio;
  final TodayDotMatrixPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.surface);

    final geometry = TodayDotSceneGeometry.forSize(size);
    final breath = reduceMotion ? 0.0 : math.sin(rekaPhase * math.pi * 2);
    final rekaCenter = geometry.rekaCenter + Offset(0, breath * 1.5);
    final rekaRadius = geometry.rekaInfluenceRadius + breath * 4;
    final dotPaint = Paint()..isAntiAlias = true;
    final halfInterval = geometry.gridInterval / 2;

    for (var y = halfInterval; y < size.height; y += geometry.gridInterval) {
      final refreshFalloff = (1 - y / 96).clamp(0.0, 1.0);
      for (var x = halfInterval; x < size.width; x += geometry.gridInterval) {
        final point = Offset(x, y);
        final delta = point - rekaCenter;
        final distance = delta.distance;
        final normalized = (1 - distance / rekaRadius).clamp(0.0, 1.0);
        final falloff = normalized * normalized * (3 - 2 * normalized);
        final direction = distance == 0 ? Offset.zero : delta / distance;
        final displaced = point + direction * (falloff * 5.5);
        final center = Offset(_snap(displaced.dx), _snap(displaced.dy));
        final radius = 0.9 + falloff * 1.5;
        final baseColor = Color.lerp(palette.dot, palette.rekaDot, falloff)!;
        final refreshAlpha =
            refreshEmphasis.clamp(0.0, 1.0) * refreshFalloff * 0.24;
        dotPaint.color = baseColor.withValues(
          alpha: (baseColor.a + refreshAlpha).clamp(0.0, 1.0),
        );
        canvas.drawCircle(center, radius, dotPaint);
      }
    }

    _paintEyes(canvas, rekaCenter, dotPaint);
  }

  void _paintEyes(Canvas canvas, Offset rekaCenter, Paint paint) {
    paint.color = palette.eye;
    for (final eyeX in [-15.0, 15.0]) {
      for (var dot = -1; dot <= 1; dot++) {
        canvas.drawCircle(
          Offset(_snap(rekaCenter.dx + eyeX + dot * 4.5), _snap(rekaCenter.dy)),
          2,
          paint,
        );
      }
    }
  }

  double _snap(double value) =>
      (value * devicePixelRatio).roundToDouble() / devicePixelRatio;

  @override
  bool shouldRepaint(covariant TodayDotMatrixPainter oldDelegate) {
    return rekaPhase != oldDelegate.rekaPhase ||
        refreshEmphasis != oldDelegate.refreshEmphasis ||
        reduceMotion != oldDelegate.reduceMotion ||
        devicePixelRatio != oldDelegate.devicePixelRatio ||
        palette != oldDelegate.palette;
  }
}
