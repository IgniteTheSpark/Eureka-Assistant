import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../foundation/theme_v2_theme.dart';

class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({super.key, required this.phase, this.size = 32});

  final CaptureActivityPhase phase;
  final double size;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.phase),
  )..repeat();

  @override
  void didUpdateWidget(covariant ThinkingOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _controller
        ..duration = _durationFor(widget.phase)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ThinkingOrbPainter(
              progress: _controller.value,
              phase: widget.phase,
              color: context.themeV2.accent,
            ),
          ),
        ),
      ),
    );
  }
}

Duration _durationFor(CaptureActivityPhase phase) => switch (phase) {
  CaptureActivityPhase.listening => const Duration(milliseconds: 1250),
  CaptureActivityPhase.receiving => const Duration(milliseconds: 1050),
  CaptureActivityPhase.transcribing => const Duration(milliseconds: 900),
  CaptureActivityPhase.understanding => const Duration(milliseconds: 1450),
  CaptureActivityPhase.organizing => const Duration(milliseconds: 1650),
  CaptureActivityPhase.done ||
  CaptureActivityPhase.empty => const Duration(milliseconds: 1900),
  CaptureActivityPhase.failed => const Duration(milliseconds: 2200),
};

class _ThinkingOrbPainter extends CustomPainter {
  const _ThinkingOrbPainter({
    required this.progress,
    required this.phase,
    required this.color,
  });

  final double progress;
  final CaptureActivityPhase phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final minSide = math.min(size.width, size.height);
    final spread = switch (phase) {
      CaptureActivityPhase.listening => minSide * 0.19,
      CaptureActivityPhase.receiving => minSide * 0.23,
      CaptureActivityPhase.transcribing => minSide * 0.27,
      CaptureActivityPhase.understanding => minSide * 0.21,
      CaptureActivityPhase.organizing => minSide * 0.15,
      _ => minSide * 0.08,
    };
    final rotation = progress * math.pi * 2;
    final breath = 0.88 + math.sin(rotation) * 0.08;
    const count = 4;
    for (var index = 0; index < count; index++) {
      final angle = rotation + index * math.pi * 2 / count;
      final wave = math.sin(rotation * 1.5 + index * 0.9);
      final offset = Offset(
        math.cos(angle) * spread * (0.76 + wave * 0.16),
        math.sin(angle) * spread * (0.58 + wave * 0.12),
      );
      final radius = minSide * (0.205 + index * 0.012) * breath;
      canvas.drawCircle(
        center + offset,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.24 + index * 0.08)
          ..blendMode = BlendMode.srcOver,
      );
    }
    canvas.drawCircle(
      center,
      minSide * 0.095 * (1.08 - breath * 0.08),
      Paint()..color = color.withValues(alpha: 0.88),
    );
  }

  @override
  bool shouldRepaint(covariant _ThinkingOrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.phase != phase ||
      oldDelegate.color != color;
}
