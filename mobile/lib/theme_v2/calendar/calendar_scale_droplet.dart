import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

class CalendarScaleDragIndicator extends StatelessWidget {
  const CalendarScaleDragIndicator({
    super.key,
    required this.targetLabel,
    required this.onRightEdge,
    required this.shapeProgress,
    required this.labelProgress,
    required this.centerY,
  });

  final String targetLabel;
  final bool onRightEdge;
  final double shapeProgress;
  final double labelProgress;
  final double? centerY;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final brightness = Theme.of(context).brightness;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = reduceMotion ? 64.0 : ui.lerpDouble(48, 103, shapeProgress)!;
    final height = reduceMotion ? 40.0 : ui.lerpDouble(72, 105, shapeProgress)!;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desiredCenterY = centerY ?? constraints.maxHeight / 2;
          final minCenterY = height / 2 + ThemeV2Spacing.md;
          final unclampedMaxCenterY =
              constraints.maxHeight - height / 2 - ThemeV2Spacing.md;
          final maxCenterY = math.max(minCenterY, unclampedMaxCenterY);
          final clampedCenterY = desiredCenterY
              .clamp(minCenterY, maxCenterY)
              .toDouble();

          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 70),
                curve: Curves.easeOutCubic,
                top: clampedCenterY - height / 2,
                left: onRightEdge ? null : 0,
                right: onRightEdge ? 0 : null,
                width: width,
                height: height,
                child: RepaintBoundary(
                  key: const ValueKey('calendar-scale-drag-repaint-boundary'),
                  child: SizedBox(
                    key: const ValueKey('calendar-scale-drag-indicator'),
                    width: width,
                    height: height,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!reduceMotion)
                          Positioned.fill(
                            child: _CalendarScaleDropletGlass(
                              onRightEdge: onRightEdge,
                              tokens: tokens,
                              brightness: brightness,
                            ),
                          )
                        else if (labelProgress > 0)
                          Positioned.fill(
                            child: _CalendarScaleReducedGlass(
                              onRightEdge: onRightEdge,
                              tokens: tokens,
                              brightness: brightness,
                            ),
                          ),
                        if (labelProgress > 0)
                          Opacity(
                            opacity: labelProgress,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: onRightEdge ? 14 : 4,
                                right: onRightEdge ? 4 : 14,
                              ),
                              child: Text(
                                targetLabel,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: tokens.foreground,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                          color: tokens.background.withValues(
                                            alpha:
                                                brightness == Brightness.light
                                                ? 0.18
                                                : 0.42,
                                          ),
                                          blurRadius: 7,
                                        ),
                                      ],
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CalendarScaleDropletGlass extends StatelessWidget {
  const _CalendarScaleDropletGlass({
    required this.onRightEdge,
    required this.tokens,
    required this.brightness,
  });

  final bool onRightEdge;
  final ThemeV2Tokens tokens;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final isLight = brightness == Brightness.light;
    final rim = Color.lerp(
      tokens.surface,
      tokens.foreground,
      isLight ? 0 : 0.68,
    )!;

    return Stack(
      key: const ValueKey('calendar-scale-drag-droplet'),
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _CalendarScaleDropletShadowPainter(
            onRightEdge: onRightEdge,
            shadow: tokens.foreground.withValues(alpha: isLight ? 0.10 : 0.24),
          ),
        ),
        ClipPath(
          clipper: _CalendarScaleDropletClipper(onRightEdge),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              key: const ValueKey('calendar-scale-drag-glass'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: onRightEdge ? Alignment.topLeft : Alignment.topRight,
                  end: onRightEdge
                      ? Alignment.bottomRight
                      : Alignment.bottomLeft,
                  colors: [
                    tokens.surface.withValues(alpha: isLight ? 0.36 : 0.24),
                    tokens.surface.withValues(alpha: isLight ? 0.28 : 0.18),
                  ],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        CustomPaint(
          painter: _CalendarScaleDropletFinishPainter(
            onRightEdge: onRightEdge,
            rim: rim.withValues(alpha: isLight ? 0.62 : 0.38),
            accent: tokens.accent.withValues(alpha: isLight ? 0.16 : 0.22),
            specular: tokens.surface.withValues(alpha: isLight ? 0.48 : 0.22),
          ),
        ),
      ],
    );
  }
}

class _CalendarScaleReducedGlass extends StatelessWidget {
  const _CalendarScaleReducedGlass({
    required this.onRightEdge,
    required this.tokens,
    required this.brightness,
  });

  final bool onRightEdge;
  final ThemeV2Tokens tokens;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final isLight = brightness == Brightness.light;
    final radius = BorderRadius.horizontal(
      left: onRightEdge ? const Radius.circular(ThemeV2Radii.md) : Radius.zero,
      right: onRightEdge ? Radius.zero : const Radius.circular(ThemeV2Radii.md),
    );

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: isLight ? 0.72 : 0.56),
            border: Border.all(
              color: tokens.border.withValues(alpha: isLight ? 0.82 : 0.72),
            ),
            borderRadius: radius,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

Path _calendarScaleDropletPath(Size size, {required bool onRightEdge}) {
  final width = size.width;
  final height = size.height;
  double x(double rightEdgeFactor) =>
      onRightEdge ? width * rightEdgeFactor : width * (1 - rightEdgeFactor);

  return Path()
    ..moveTo(x(1), 0)
    ..cubicTo(x(0.78), 0, x(0.84), height * 0.18, x(0.62), height * 0.23)
    ..cubicTo(
      x(0.31),
      height * 0.29,
      x(0.18),
      height * 0.38,
      x(0.15),
      height * 0.5,
    )
    ..cubicTo(
      x(0.18),
      height * 0.62,
      x(0.31),
      height * 0.71,
      x(0.62),
      height * 0.77,
    )
    ..cubicTo(x(0.84), height * 0.82, x(0.78), height, x(1), height)
    ..close();
}

class _CalendarScaleDropletClipper extends CustomClipper<Path> {
  const _CalendarScaleDropletClipper(this.onRightEdge);

  final bool onRightEdge;

  @override
  Path getClip(Size size) =>
      _calendarScaleDropletPath(size, onRightEdge: onRightEdge);

  @override
  bool shouldReclip(_CalendarScaleDropletClipper oldClipper) =>
      oldClipper.onRightEdge != onRightEdge;
}

class _CalendarScaleDropletShadowPainter extends CustomPainter {
  const _CalendarScaleDropletShadowPainter({
    required this.onRightEdge,
    required this.shadow,
  });

  final bool onRightEdge;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _calendarScaleDropletPath(size, onRightEdge: onRightEdge);
    canvas.drawShadow(path, shadow, 7, true);
  }

  @override
  bool shouldRepaint(_CalendarScaleDropletShadowPainter oldDelegate) {
    return oldDelegate.onRightEdge != onRightEdge ||
        oldDelegate.shadow != shadow;
  }
}

class _CalendarScaleDropletFinishPainter extends CustomPainter {
  const _CalendarScaleDropletFinishPainter({
    required this.onRightEdge,
    required this.rim,
    required this.accent,
    required this.specular,
  });

  final bool onRightEdge;
  final Color rim;
  final Color accent;
  final Color specular;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _calendarScaleDropletPath(size, onRightEdge: onRightEdge);
    final bounds = Offset.zero & size;

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: onRightEdge
              ? const Alignment(-0.42, -0.52)
              : const Alignment(0.42, -0.52),
          radius: 0.88,
          colors: [specular, specular.withValues(alpha: 0)],
          stops: const [0, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: onRightEdge ? Alignment.centerLeft : Alignment.centerRight,
          end: onRightEdge ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.18),
            accent,
          ],
          stops: const [0.35, 0.76, 1],
        ).createShader(bounds),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: onRightEdge ? Alignment.topLeft : Alignment.topRight,
          end: onRightEdge ? Alignment.bottomRight : Alignment.bottomLeft,
          colors: [
            rim,
            rim.withValues(alpha: rim.a * 0.44),
            accent.withValues(alpha: accent.a * 0.62),
          ],
          stops: const [0, 0.58, 1],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15,
    );

    final tensionLine = Path()
      ..moveTo(onRightEdge ? size.width - 9 : 9, size.height * 0.23)
      ..cubicTo(
        onRightEdge ? size.width - 2 : 2,
        size.height * 0.36,
        onRightEdge ? size.width - 2 : 2,
        size.height * 0.64,
        onRightEdge ? size.width - 9 : 9,
        size.height * 0.77,
      );
    canvas.drawPath(
      tensionLine,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CalendarScaleDropletFinishPainter oldDelegate) {
    return oldDelegate.onRightEdge != onRightEdge ||
        oldDelegate.rim != rim ||
        oldDelegate.accent != accent ||
        oldDelegate.specular != specular;
  }
}
