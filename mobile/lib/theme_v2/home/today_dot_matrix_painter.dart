import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'today_dot_field_controller.dart';
import 'today_dot_field_simulation.dart';

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
    required this.initialRekaCenter,
    required this.rekaInfluenceRadius,
    this.gridInterval = 8,
  });

  factory TodayDotSceneGeometry.forSize(Size size) => TodayDotSceneGeometry(
    size: size,
    initialRekaCenter: Offset(size.width * .29, size.height * .46),
    rekaInfluenceRadius: 120,
  );

  final Size size;
  final Offset initialRekaCenter;
  final double rekaInfluenceRadius;
  final double gridInterval;

  @Deprecated('Use initialRekaCenter while migrating to the draggable scene.')
  Offset get rekaCenter => initialRekaCenter;
}

class TodayDotMatrixPainter extends CustomPainter {
  TodayDotMatrixPainter({
    this.simulation,
    this.rekaCenter,
    this.rekaState = TodayRekaMotionState.idle,
    this.breathAmount,
    this.eyeOpacity,
    this.rekaPhase,
    required this.refreshEmphasis,
    required this.reduceMotion,
    required this.devicePixelRatio,
    this.palette = TodayDotMatrixPalette.light,
  }) : simulationRevision = simulation?.paintRevision ?? -1;

  final TodayDotFieldSimulation? simulation;
  final int simulationRevision;
  final Offset? rekaCenter;
  final TodayRekaMotionState rekaState;
  final double? breathAmount;
  final double? eyeOpacity;

  @Deprecated('Pass controller-derived breathAmount and eyeOpacity.')
  final double? rekaPhase;

  final double refreshEmphasis;
  final bool reduceMotion;
  final double devicePixelRatio;
  final TodayDotMatrixPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.surface);

    final geometry = TodayDotSceneGeometry.forSize(size);
    final resolvedCenter = rekaCenter ?? geometry.initialRekaCenter;
    final resolvedBreath = breathAmount ?? _legacyBreathAmount;
    final resolvedEyeOpacity = eyeOpacity ?? _legacyEyeOpacity;
    final field = simulation ?? (TodayDotFieldSimulation()..layout(size));
    if (simulation == null) {
      field.step(
        1 / 60,
        rekaCenter: resolvedCenter,
        state: rekaState,
        dragEngagement: 0,
        breathAmount: resolvedBreath,
        fieldPhase: rekaPhase ?? 0,
        reduceMotion: reduceMotion,
      );
    }

    final dotPaint = Paint()..isAntiAlias = true;
    for (final node in field.nodes) {
      final falloff = rekaMaterialFalloff(node.anchor, resolvedCenter);
      final refreshFalloff = (1 - node.anchor.dy / 96).clamp(0.0, 1.0);
      final center = Offset(_snap(node.position.dx), _snap(node.position.dy));
      final radius = .9 + falloff * (1.25 + resolvedBreath * .2);
      final baseColor = Color.lerp(palette.dot, palette.rekaDot, falloff)!;
      final refreshAlpha =
          refreshEmphasis.clamp(0.0, 1.0) * refreshFalloff * .24;
      dotPaint.color = baseColor.withValues(
        alpha: (baseColor.a + refreshAlpha).clamp(0.0, 1.0),
      );
      canvas.drawCircle(center, radius, dotPaint);
    }

    if (resolvedEyeOpacity > .001) {
      _paintEyes(canvas, resolvedCenter, resolvedEyeOpacity, dotPaint);
    }
  }

  double get _legacyBreathAmount {
    if (reduceMotion || rekaPhase == null) return 0;
    final wave = math.sin(rekaPhase! * math.pi * 2 - math.pi / 2);
    return (wave + 1) / 2;
  }

  double get _legacyEyeOpacity {
    if (reduceMotion) return .42;
    return TodayDotFieldController.eyeOpacityForPhase(rekaPhase ?? 0);
  }

  static double rekaMaterialFalloff(Offset point, Offset center) {
    final delta = point - center;
    final angle = math.atan2(delta.dy, delta.dx);
    final organicRadius =
        45 *
        (1 + .08 * math.sin(angle * 3 + .6) + .05 * math.sin(angle * 5 - .8));
    final normalized = (1 - delta.distance / organicRadius).clamp(0.0, 1.0);
    return normalized * normalized * (3 - 2 * normalized);
  }

  void _paintEyes(Canvas canvas, Offset center, double opacity, Paint paint) {
    paint.color = palette.eye.withValues(
      alpha: palette.eye.a * opacity.clamp(0.0, 1.0),
    );
    for (final eyeX in [-15.0, 15.0]) {
      for (var dot = -1; dot <= 1; dot++) {
        canvas.drawCircle(
          Offset(_snap(center.dx + eyeX + dot * 4.5), _snap(center.dy)),
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
    return simulationRevision != oldDelegate.simulationRevision ||
        rekaCenter != oldDelegate.rekaCenter ||
        rekaState != oldDelegate.rekaState ||
        breathAmount != oldDelegate.breathAmount ||
        eyeOpacity != oldDelegate.eyeOpacity ||
        rekaPhase != oldDelegate.rekaPhase ||
        refreshEmphasis != oldDelegate.refreshEmphasis ||
        reduceMotion != oldDelegate.reduceMotion ||
        devicePixelRatio != oldDelegate.devicePixelRatio ||
        palette != oldDelegate.palette;
  }
}
