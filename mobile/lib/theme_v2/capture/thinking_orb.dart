import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';

enum ThinkingOrbVisualState {
  listening,
  receiving,
  transcribing,
  understanding,
  executing,
  composing,
  organizing,
  success,
  empty,
  failed,
}

const thinkingOrbMorphDuration = Duration(milliseconds: 220);

ThinkingOrbVisualState thinkingOrbStateForCapture(CaptureActivityPhase phase) =>
    switch (phase) {
      CaptureActivityPhase.listening => ThinkingOrbVisualState.listening,
      CaptureActivityPhase.receiving => ThinkingOrbVisualState.receiving,
      CaptureActivityPhase.transcribing => ThinkingOrbVisualState.transcribing,
      CaptureActivityPhase.understanding =>
        ThinkingOrbVisualState.understanding,
      CaptureActivityPhase.organizing => ThinkingOrbVisualState.organizing,
      CaptureActivityPhase.done => ThinkingOrbVisualState.success,
      CaptureActivityPhase.empty => ThinkingOrbVisualState.empty,
      CaptureActivityPhase.failed => ThinkingOrbVisualState.failed,
    };

@immutable
class ThinkingOrbProfile {
  const ThinkingOrbProfile({
    required this.nodeCount,
    required this.spreadX,
    required this.spreadY,
    required this.nodeRadius,
    required this.coreRadius,
    required this.rotationTurns,
    required this.pulse,
    this.verticalBias = 0,
    this.ring = 0,
    this.split = 0,
  });

  final double nodeCount;
  final double spreadX;
  final double spreadY;
  final double nodeRadius;
  final double coreRadius;
  final double rotationTurns;
  final double pulse;
  final double verticalBias;
  final double ring;
  final double split;

  static ThinkingOrbProfile lerp(
    ThinkingOrbProfile a,
    ThinkingOrbProfile b,
    double t,
  ) => ThinkingOrbProfile(
    nodeCount: _lerp(a.nodeCount, b.nodeCount, t),
    spreadX: _lerp(a.spreadX, b.spreadX, t),
    spreadY: _lerp(a.spreadY, b.spreadY, t),
    nodeRadius: _lerp(a.nodeRadius, b.nodeRadius, t),
    coreRadius: _lerp(a.coreRadius, b.coreRadius, t),
    rotationTurns: _lerp(a.rotationTurns, b.rotationTurns, t),
    pulse: _lerp(a.pulse, b.pulse, t),
    verticalBias: _lerp(a.verticalBias, b.verticalBias, t),
    ring: _lerp(a.ring, b.ring, t),
    split: _lerp(a.split, b.split, t),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThinkingOrbProfile &&
          nodeCount == other.nodeCount &&
          spreadX == other.spreadX &&
          spreadY == other.spreadY &&
          nodeRadius == other.nodeRadius &&
          coreRadius == other.coreRadius &&
          rotationTurns == other.rotationTurns &&
          pulse == other.pulse &&
          verticalBias == other.verticalBias &&
          ring == other.ring &&
          split == other.split;

  @override
  int get hashCode => Object.hash(
    nodeCount,
    spreadX,
    spreadY,
    nodeRadius,
    coreRadius,
    rotationTurns,
    pulse,
    verticalBias,
    ring,
    split,
  );
}

ThinkingOrbProfile thinkingOrbProfile(ThinkingOrbVisualState state) =>
    switch (state) {
      ThinkingOrbVisualState.listening => const ThinkingOrbProfile(
        nodeCount: 3,
        spreadX: 0.11,
        spreadY: 0.29,
        nodeRadius: 0.17,
        coreRadius: 0.085,
        rotationTurns: 0.42,
        pulse: 0.15,
      ),
      ThinkingOrbVisualState.receiving => const ThinkingOrbProfile(
        nodeCount: 5,
        spreadX: 0.31,
        spreadY: 0.12,
        nodeRadius: 0.13,
        coreRadius: 0.08,
        rotationTurns: 1.2,
        pulse: 0.09,
      ),
      ThinkingOrbVisualState.transcribing => const ThinkingOrbProfile(
        nodeCount: 6,
        spreadX: 0.29,
        spreadY: 0.22,
        nodeRadius: 0.105,
        coreRadius: 0.075,
        rotationTurns: 1.55,
        pulse: 0.07,
        verticalBias: 0.06,
      ),
      ThinkingOrbVisualState.understanding => const ThinkingOrbProfile(
        nodeCount: 4,
        spreadX: 0.22,
        spreadY: 0.24,
        nodeRadius: 0.16,
        coreRadius: 0.095,
        rotationTurns: 0.72,
        pulse: 0.13,
      ),
      ThinkingOrbVisualState.executing => const ThinkingOrbProfile(
        nodeCount: 5,
        spreadX: 0.34,
        spreadY: 0.15,
        nodeRadius: 0.12,
        coreRadius: 0.08,
        rotationTurns: 1.7,
        pulse: 0.05,
        split: 0.2,
      ),
      ThinkingOrbVisualState.composing => const ThinkingOrbProfile(
        nodeCount: 3,
        spreadX: 0.17,
        spreadY: 0.3,
        nodeRadius: 0.185,
        coreRadius: 0.1,
        rotationTurns: 0.58,
        pulse: 0.12,
        ring: 0.16,
      ),
      ThinkingOrbVisualState.organizing => const ThinkingOrbProfile(
        nodeCount: 4,
        spreadX: 0.135,
        spreadY: 0.135,
        nodeRadius: 0.18,
        coreRadius: 0.11,
        rotationTurns: 0.36,
        pulse: 0.08,
        ring: 0.34,
      ),
      ThinkingOrbVisualState.success => const ThinkingOrbProfile(
        nodeCount: 3,
        spreadX: 0.075,
        spreadY: 0.075,
        nodeRadius: 0.16,
        coreRadius: 0.13,
        rotationTurns: 0.18,
        pulse: 0.04,
        ring: 0.92,
      ),
      ThinkingOrbVisualState.empty => const ThinkingOrbProfile(
        nodeCount: 2,
        spreadX: 0.09,
        spreadY: 0.09,
        nodeRadius: 0.12,
        coreRadius: 0.075,
        rotationTurns: 0.22,
        pulse: 0.035,
        ring: 0.12,
      ),
      ThinkingOrbVisualState.failed => const ThinkingOrbProfile(
        nodeCount: 4,
        spreadX: 0.3,
        spreadY: 0.065,
        nodeRadius: 0.135,
        coreRadius: 0.065,
        rotationTurns: 0.08,
        pulse: 0.035,
        split: 0.92,
      ),
    };

class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({super.key, required this.state, this.size = 32});

  final ThinkingOrbVisualState state;
  final double size;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with TickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _durationFor(widget.state),
  )..repeat();
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: thinkingOrbMorphDuration,
    value: 1,
  );
  late ThinkingOrbProfile _fromProfile = thinkingOrbProfile(widget.state);
  late ThinkingOrbProfile _toProfile = thinkingOrbProfile(widget.state);
  late ThinkingOrbVisualState _fromState = widget.state;

  @override
  void didUpdateWidget(covariant ThinkingOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    _fromProfile = ThinkingOrbProfile.lerp(
      _fromProfile,
      _toProfile,
      _morph.value,
    );
    _toProfile = thinkingOrbProfile(widget.state);
    _fromState = oldWidget.state;
    _motion
      ..duration = _durationFor(widget.state)
      ..repeat();
    _morph.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_motion, _morph]),
          builder: (context, _) => CustomPaint(
            painter: _ThinkingOrbPainter(
              progress: _motion.value,
              morph: Curves.easeInOutCubic.transform(_morph.value),
              fromProfile: _fromProfile,
              toProfile: _toProfile,
              fromColors: _colorsFor(_fromState, Theme.of(context).brightness),
              toColors: _colorsFor(widget.state, Theme.of(context).brightness),
            ),
          ),
        ),
      ),
    );
  }
}

Duration _durationFor(ThinkingOrbVisualState state) => switch (state) {
  ThinkingOrbVisualState.listening => const Duration(milliseconds: 1280),
  ThinkingOrbVisualState.receiving => const Duration(milliseconds: 960),
  ThinkingOrbVisualState.transcribing => const Duration(milliseconds: 820),
  ThinkingOrbVisualState.understanding => const Duration(milliseconds: 1420),
  ThinkingOrbVisualState.executing => const Duration(milliseconds: 760),
  ThinkingOrbVisualState.composing => const Duration(milliseconds: 1560),
  ThinkingOrbVisualState.organizing => const Duration(milliseconds: 1780),
  ThinkingOrbVisualState.success => const Duration(milliseconds: 2100),
  ThinkingOrbVisualState.empty => const Duration(milliseconds: 2400),
  ThinkingOrbVisualState.failed => const Duration(milliseconds: 2600),
};

List<Color> _colorsFor(ThinkingOrbVisualState state, Brightness brightness) {
  final cyan = brightness == Brightness.dark
      ? const Color(0xFF5DE7FF)
      : const Color(0xFF12A9D2);
  final violet = brightness == Brightness.dark
      ? const Color(0xFFA79BFF)
      : const Color(0xFF735DE8);
  final coral = brightness == Brightness.dark
      ? const Color(0xFFFF8596)
      : const Color(0xFFE85D73);
  final muted = brightness == Brightness.dark
      ? const Color(0xFF798496)
      : const Color(0xFF99A5B5);
  return switch (state) {
    ThinkingOrbVisualState.listening => [cyan, violet, coral],
    ThinkingOrbVisualState.receiving => [violet, cyan, coral],
    ThinkingOrbVisualState.transcribing => [coral, cyan, violet],
    ThinkingOrbVisualState.understanding => [violet, coral, cyan],
    ThinkingOrbVisualState.executing => [coral, violet, cyan],
    ThinkingOrbVisualState.composing => [violet, cyan, coral],
    ThinkingOrbVisualState.organizing => [cyan, coral, violet],
    ThinkingOrbVisualState.success => [cyan, violet, const Color(0xFFFFC568)],
    ThinkingOrbVisualState.empty => [muted, cyan, violet],
    ThinkingOrbVisualState.failed => [coral, violet, const Color(0xFFFFB06B)],
  };
}

class _ThinkingOrbPainter extends CustomPainter {
  const _ThinkingOrbPainter({
    required this.progress,
    required this.morph,
    required this.fromProfile,
    required this.toProfile,
    required this.fromColors,
    required this.toColors,
  });

  final double progress;
  final double morph;
  final ThinkingOrbProfile fromProfile;
  final ThinkingOrbProfile toProfile;
  final List<Color> fromColors;
  final List<Color> toColors;

  @override
  void paint(Canvas canvas, Size size) {
    final profile = ThinkingOrbProfile.lerp(fromProfile, toProfile, morph);
    final colors = List<Color>.generate(
      3,
      (index) => Color.lerp(fromColors[index], toColors[index], morph)!,
    );
    final center = size.center(Offset.zero);
    final minSide = math.min(size.width, size.height);
    final rotation = progress * math.pi * 2 * profile.rotationTurns;
    final breath = 1 + math.sin(progress * math.pi * 2) * profile.pulse;

    if (profile.ring > 0.01) {
      canvas.drawCircle(
        center,
        minSide * (0.27 + profile.ring * 0.055) * breath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, minSide * 0.035 * profile.ring)
          ..color = colors[1].withValues(alpha: 0.16 + profile.ring * 0.42),
      );
    }

    final nodeCount = math.max(1, profile.nodeCount.round());
    for (var index = 0; index < nodeCount; index++) {
      final angle = rotation + index * math.pi * 2 / nodeCount;
      final wave = math.sin(rotation * 1.7 + index * 1.13);
      final splitDirection = index.isEven ? -1.0 : 1.0;
      final offset = Offset(
        math.cos(angle) * minSide * profile.spreadX * (0.82 + wave * 0.12) +
            splitDirection * minSide * profile.split * 0.09,
        math.sin(angle) * minSide * profile.spreadY * (0.78 + wave * 0.1) +
            minSide * profile.verticalBias * wave,
      );
      final radius = minSide * profile.nodeRadius * breath;
      final nodeColor = colors[index % colors.length];
      canvas.drawCircle(
        center + offset,
        radius,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  nodeColor.withValues(alpha: 0.72),
                  nodeColor.withValues(alpha: 0.18),
                ],
              ).createShader(
                Rect.fromCircle(center: center + offset, radius: radius),
              ),
      );
    }

    final coreRadius = minSide * profile.coreRadius * (2.05 - breath);
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors[0].withValues(alpha: 0.98),
            colors[1].withValues(alpha: 0.72),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: coreRadius)),
    );
  }

  @override
  bool shouldRepaint(covariant _ThinkingOrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.morph != morph ||
      oldDelegate.fromProfile != fromProfile ||
      oldDelegate.toProfile != toProfile ||
      oldDelegate.fromColors != fromColors ||
      oldDelegate.toColors != toColors;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
