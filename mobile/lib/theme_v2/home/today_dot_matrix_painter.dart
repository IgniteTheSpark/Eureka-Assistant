import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'today_dot_field_controller.dart';
import 'today_dot_field_config.dart';
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
    this.gridInterval = 14,
  });

  factory TodayDotSceneGeometry.forSize(Size size) => TodayDotSceneGeometry(
    size: size,
    initialRekaCenter: Offset(size.width * .29, size.height * .46),
    rekaInfluenceRadius: 150,
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
    this.config = const TodayDotFieldConfig(),
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
  final TodayDotFieldConfig config;
  final TodayDotMatrixPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.surface);

    final geometry = TodayDotSceneGeometry.forSize(size);
    final resolvedCenter = rekaCenter ?? geometry.initialRekaCenter;
    final resolvedBreath = breathAmount ?? _legacyBreathAmount;
    final resolvedEyeOpacity = eyeOpacity ?? _legacyEyeOpacity;
    final field =
        simulation ?? (TodayDotFieldSimulation(config: config)..layout(size));
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
    for (var index = 0; index < field.nodes.length; index++) {
      final node = field.nodes[index];
      final refreshFalloff = (1 - node.anchor.dy / 96).clamp(0.0, 1.0);
      final center = Offset(_snap(node.position.dx), _snap(node.position.dy));
      final gradientProgress =
          ((node.anchor.dx / size.width) + (node.anchor.dy / size.height)) / 2;
      final baseColor = Color.lerp(
        config.gradientFrom,
        config.gradientTo,
        gradientProgress.clamp(0.0, 1.0),
      )!;
      final refreshAlpha =
          refreshEmphasis.clamp(0.0, 1.0) * refreshFalloff * .24;
      dotPaint.color = baseColor.withValues(
        alpha: (baseColor.a + refreshAlpha).clamp(0.0, 1.0),
      );
      final sparkleScale = field.isSparkle(index) ? 1.65 : 1.0;
      canvas.drawCircle(center, config.dotRadius * sparkleScale, dotPaint);
    }

    _paintRekaGlow(canvas, resolvedCenter, resolvedBreath);
    _paintRekaRise(canvas, resolvedCenter, resolvedBreath);

    if (rekaState != TodayRekaMotionState.dragging &&
        resolvedEyeOpacity > .001) {
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

  void _paintRekaGlow(Canvas canvas, Offset center, double breath) {
    final strength = reduceMotion ? .38 : .34 + breath * .66;
    final rect = Rect.fromCircle(center: center, radius: config.glowRadius);
    canvas.drawCircle(
      center,
      config.glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            config.glowColor.withValues(alpha: .06 * strength),
            config.glowColor.withValues(alpha: .022 * strength),
            config.glowColor.withValues(alpha: 0),
          ],
          stops: const [0, .58, 1],
        ).createShader(rect),
    );
  }

  void _paintRekaRise(Canvas canvas, Offset center, double breath) {
    final strength = reduceMotion ? .82 : .78 + breath * .22;
    final radius =
        config.cursorRadius *
        (reduceMotion ? 1 : .96 + breath.clamp(0.0, 1.0) * .04);
    _paintSoftLightField(
      canvas,
      center: center + Offset(-radius * .08, -radius * .04),
      horizontalRadius: radius * 1.6,
      verticalRadius: radius * 1.14,
      alignment: const Alignment(-.04, -.08),
      strength: strength,
      peakAlpha: .86,
    );
    _paintSoftLightField(
      canvas,
      center: center + Offset(-radius * .24, -radius * .22),
      horizontalRadius: radius * .78,
      verticalRadius: radius * .66,
      alignment: const Alignment(-.24, -.28),
      strength: strength,
      peakAlpha: .46,
    );
    _paintSoftLightField(
      canvas,
      center: center + Offset(radius * .18, radius * .16),
      horizontalRadius: radius * .92,
      verticalRadius: radius * .72,
      alignment: const Alignment(-.08, -.12),
      strength: strength,
      peakAlpha: .22,
    );
  }

  void _paintSoftLightField(
    Canvas canvas, {
    required Offset center,
    required double horizontalRadius,
    required double verticalRadius,
    required Alignment alignment,
    required double strength,
    required double peakAlpha,
  }) {
    final horizontalScale = horizontalRadius / verticalRadius;
    final shaderRect = Rect.fromCircle(
      center: Offset.zero,
      radius: verticalRadius,
    );
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(horizontalScale, 1)
      ..drawCircle(
        Offset.zero,
        verticalRadius,
        Paint()
          ..shader = RadialGradient(
            center: alignment,
            colors: [
              Colors.white.withValues(alpha: peakAlpha * strength),
              Colors.white.withValues(alpha: peakAlpha * strength * .62),
              Colors.white.withValues(alpha: peakAlpha * strength * .42),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, .34, .7, 1],
          ).createShader(shaderRect),
      )
      ..restore();
  }

  void _paintEyes(Canvas canvas, Offset center, double opacity, Paint paint) {
    final resolvedOpacity = opacity.clamp(0.0, 1.0);
    final eyeOffset = config.cursorRadius * .28;
    final ledRadius = math.max(1.25, config.dotRadius * .72);
    final pitch = math.max(5.0, config.dotRadius * 3.0);
    for (final eyeX in [center.dx - eyeOffset, center.dx + eyeOffset]) {
      for (var row = -1; row <= 1; row++) {
        for (var column = -1; column <= 1; column++) {
          final corner = row.abs() == 1 && column.abs() == 1;
          final edge = row == 0 || column == 0;
          final ledStrength = corner ? .46 : (edge ? .78 : 1.0);
          final ledCenter = Offset(
            _snap(eyeX + column * pitch),
            _snap(center.dy + row * pitch),
          );
          paint.color = palette.eye.withValues(
            alpha: palette.eye.a * resolvedOpacity * ledStrength * .18,
          );
          canvas.drawCircle(ledCenter, ledRadius * 2.2, paint);
          paint.color = palette.eye.withValues(
            alpha: palette.eye.a * resolvedOpacity * ledStrength,
          );
          canvas.drawCircle(ledCenter, ledRadius, paint);
        }
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
        config != oldDelegate.config ||
        palette != oldDelegate.palette;
  }
}
