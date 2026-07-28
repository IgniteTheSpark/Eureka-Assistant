import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/ureka_tokens.dart';

class USkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry margin;
  final Color? baseColor;
  final Color? glowColor;

  const USkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.margin = EdgeInsets.zero,
    this.baseColor,
    this.glowColor,
  });

  @override
  State<USkeleton> createState() => _USkeletonState();
}

class _USkeletonState extends State<USkeleton> with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _disposeController();
    } else {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1300),
      )..repeat();
    }
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final needsLegacyPalette =
        widget.baseColor == null || widget.glowColor == null;
    final eu = needsLegacyPalette ? context.eu : null;
    final base =
        widget.baseColor ??
        eu!.textLo.withValues(
          alpha: eu.brightness == Brightness.dark ? 0.16 : 0.12,
        );
    final glow =
        widget.glowColor ??
        eu!.textLo.withValues(
          alpha: eu.brightness == Brightness.dark ? 0.26 : 0.22,
        );
    final shape = Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );

    if (reduceMotion) return ExcludeSemantics(child: shape);

    final controller = _controller!;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final slide = controller.value * 2.4 - 1.2;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, glow, base],
                stops: const [0.22, 0.50, 0.78],
                transform: _SlidingGradientTransform(slide),
              ).createShader(rect);
            },
            child: child,
          );
        },
        child: shape,
      ),
    );
  }
}

class USkeletonLine extends StatelessWidget {
  final double widthFactor;
  final double height;
  final EdgeInsetsGeometry margin;
  final Color? baseColor;
  final Color? glowColor;

  const USkeletonLine({
    super.key,
    this.widthFactor = 1,
    this.height = 12,
    this.margin = EdgeInsets.zero,
    this.baseColor,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: USkeleton(
        height: height,
        radius: height / 2,
        margin: margin,
        baseColor: baseColor,
        glowColor: glowColor,
      ),
    );
  }
}

class USkeletonCard extends StatelessWidget {
  final double height;
  final bool leading;
  final int lines;

  const USkeletonCard({
    super.key,
    this.height = 84,
    this.leading = true,
    this.lines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final verticalPadding = height < 84 ? 10.0 : 14.0;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: eu.surfaceRaised.withValues(
          alpha: eu.brightness == Brightness.dark ? 0.46 : 0.72,
        ),
        borderRadius: BorderRadius.circular(URadii.card),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          if (leading) ...[
            const USkeleton(width: 38, height: 38, radius: 12),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const USkeletonLine(widthFactor: 0.58, height: 13),
                if (lines > 1)
                  const USkeletonLine(
                    widthFactor: 0.92,
                    height: 11,
                    margin: EdgeInsets.only(top: 10),
                  ),
                if (lines > 2)
                  const USkeletonLine(
                    widthFactor: 0.36,
                    height: 10,
                    margin: EdgeInsets.only(top: 9),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class USkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final double cardHeight;
  final bool leading;

  const USkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
    this.cardHeight = 84,
    this.leading = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => USkeletonCard(
        height: cardHeight,
        leading: leading,
        lines: i % 3 == 0 ? 2 : 3,
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double percent;

  const _SlidingGradientTransform(this.percent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}
