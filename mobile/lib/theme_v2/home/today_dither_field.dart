import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'today_dither_material.dart';

enum TodayDitherSourceShape { circle, capsule }

@immutable
class TodayDitherSource {
  const TodayDitherSource.circle({
    required this.center,
    required double radius,
    this.energy = 0,
  }) : shape = TodayDitherSourceShape.circle,
       _radius = radius,
       _capsuleSize = null;

  const TodayDitherSource.capsule({
    required this.center,
    required Size size,
    this.energy = 0,
  }) : shape = TodayDitherSourceShape.capsule,
       _radius = 0,
       _capsuleSize = size;

  final TodayDitherSourceShape shape;
  final Offset center;
  final double _radius;
  final Size? _capsuleSize;
  final double energy;

  Size get size => _capsuleSize ?? Size.square(_radius * 2);
}

double todayDitherPressureAt(Offset point, TodayDitherSource source) {
  final delta = point - source.center;
  final halfWidth = source.size.width / 2;
  final halfHeight = source.size.height / 2;
  final signedDistance = switch (source.shape) {
    TodayDitherSourceShape.circle => delta.distance - halfWidth,
    TodayDitherSourceShape.capsule => () {
      final segment = math.max(0.0, halfWidth - halfHeight);
      final x = math.max(0.0, delta.dx.abs() - segment);
      return math.sqrt(x * x + delta.dy * delta.dy) - halfHeight;
    }(),
  };
  final feather = (math.min(source.size.width, source.size.height) * .22).clamp(
    4.0,
    14.0,
  );
  final linear = 1 - ((signedDistance + feather) / (feather * 2)).clamp(0, 1);
  final smooth = linear * linear * (3 - 2 * linear);
  return (smooth * (1 + source.energy.clamp(0, 1) * .18)).clamp(0, 1);
}

@immutable
class TodayDitherFieldConfig {
  const TodayDitherFieldConfig.signal({
    this.waveColor = const Color(0xFF6D7480),
    this.colorNum = 4,
    this.pixelSize = 4,
    this.waveAmplitude = .3,
    this.waveFrequency = 3,
    this.waveSpeed = .055,
    this.flowDirection = const Offset(1, .08),
    this.opacity = .18,
    this.displacementStrength = .92,
  });

  const TodayDitherFieldConfig.asset({
    this.waveColor = const Color(0xFF69717B),
    this.colorNum = 4,
    this.pixelSize = 4,
    this.waveAmplitude = .32,
    this.waveFrequency = 2.7,
    this.waveSpeed = .036,
    this.flowDirection = const Offset(.1, 1),
    this.opacity = .16,
    this.displacementStrength = .88,
  });

  final Color waveColor;
  final double colorNum;
  final double pixelSize;
  final double waveAmplitude;
  final double waveFrequency;
  final double waveSpeed;
  final Offset flowDirection;
  final double opacity;
  final double displacementStrength;

  TodayDitherFieldConfig copyWith({
    Color? waveColor,
    double? opacity,
    double? waveSpeed,
  }) => TodayDitherFieldConfig.signal(
    waveColor: waveColor ?? this.waveColor,
    colorNum: colorNum,
    pixelSize: pixelSize,
    waveAmplitude: waveAmplitude,
    waveFrequency: waveFrequency,
    waveSpeed: waveSpeed ?? this.waveSpeed,
    flowDirection: flowDirection,
    opacity: opacity ?? this.opacity,
    displacementStrength: displacementStrength,
  );
}

class TodayDitherField extends StatefulWidget {
  const TodayDitherField({
    super.key,
    required this.config,
    this.sources = const [],
    this.motion,
    this.reduceMotion = false,
  });

  static const shaderAsset = 'shaders/today_dither_field.frag';
  static const maxSources = 24;
  static const shaderSurfaceKey = ValueKey('today-dither-shader-surface');

  final TodayDitherFieldConfig config;
  final List<TodayDitherSource> sources;
  final Animation<double>? motion;
  final bool reduceMotion;

  @override
  State<TodayDitherField> createState() => _TodayDitherFieldState();
}

class _TodayDitherFieldState extends State<TodayDitherField> {
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
        TodayDitherField.shaderAsset,
      ));
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // The deterministic painter below preserves the surface if runtime
      // shaders are unavailable on a platform or test renderer.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = widget.motion ?? const AlwaysStoppedAnimation<double>(0);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, _) => CustomPaint(
          key: TodayDitherField.shaderSurfaceKey,
          painter: TodayDitherFieldPainter(
            shader: _shader,
            config: widget.config,
            sources: widget.sources
                .take(TodayDitherField.maxSources)
                .toList(growable: false),
            phase: widget.reduceMotion ? 0 : motion.value,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class TodayDitherFieldPainter extends CustomPainter {
  const TodayDitherFieldPainter({
    required this.shader,
    required this.config,
    required this.sources,
    required this.phase,
  });

  final ui.FragmentShader? shader;
  final TodayDitherFieldConfig config;
  final List<TodayDitherSource> sources;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final fragment = shader;
    if (fragment == null) {
      _paintFallback(canvas, size);
      return;
    }
    var index = 0;
    void set(double value) => fragment.setFloat(index++, value);

    set(size.width);
    set(size.height);
    set(phase * 120);
    set(config.flowDirection.dx);
    set(config.flowDirection.dy);
    set(config.waveSpeed);
    set(config.waveFrequency);
    set(config.waveAmplitude);
    set(config.waveColor.r);
    set(config.waveColor.g);
    set(config.waveColor.b);
    set(config.opacity);
    set(config.colorNum);
    set(config.pixelSize);
    set(config.displacementStrength);
    set(sources.length.toDouble());
    for (
      var sourceIndex = 0;
      sourceIndex < TodayDitherField.maxSources;
      sourceIndex++
    ) {
      final source = sourceIndex < sources.length ? sources[sourceIndex] : null;
      set(source?.center.dx ?? 0);
      set(source?.center.dy ?? 0);
      set((source?.size.width ?? 0) / 2);
      set((source?.size.height ?? 0) / 2);
    }
    for (
      var sourceIndex = 0;
      sourceIndex < TodayDitherField.maxSources;
      sourceIndex++
    ) {
      final source = sourceIndex < sources.length ? sources[sourceIndex] : null;
      set(source?.shape == TodayDitherSourceShape.capsule ? 1 : 0);
      set(source?.energy.clamp(0, 1).toDouble() ?? 0);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = fragment);
  }

  void _paintFallback(Canvas canvas, Size size) {
    final step = math.max(3.0, config.pixelSize);
    final dotSize = step * .54;
    final drift = config.flowDirection * (phase * config.waveSpeed * 36);
    final paint = Paint()
      ..color = config.waveColor.withValues(alpha: config.opacity)
      ..isAntiAlias = false;
    final xCount = (size.width / step).ceil();
    final yCount = (size.height / step).ceil();
    for (var y = -1; y <= yCount; y++) {
      for (var x = -1; x <= xCount; x++) {
        final center = Offset(
          (x + .5) * step + drift.dx % step,
          (y + .5) * step + drift.dy % step,
        );
        final pressure = sources.fold<double>(
          0,
          (value, source) =>
              math.max(value, todayDitherPressureAt(center, source)),
        );
        final wave =
            .52 +
            math.sin(
                  center.dx * .026 + center.dy * .021 - phase * math.pi * 2,
                ) *
                config.waveAmplitude;
        final coverage = (wave - pressure * config.displacementStrength).clamp(
          0,
          1,
        );
        final threshold = (bayer4(x, y) + .5) / 16;
        if (coverage <= threshold) continue;
        canvas.drawRect(
          Rect.fromCenter(center: center, width: dotSize, height: dotSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TodayDitherFieldPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      config != oldDelegate.config ||
      !identical(sources, oldDelegate.sources) ||
      phase != oldDelegate.phase;
}
