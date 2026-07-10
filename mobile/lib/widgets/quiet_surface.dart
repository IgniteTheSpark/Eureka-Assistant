import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../theme/ureka_tokens.dart';

class UQuietSurface extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? signalColor;
  final bool pressed;
  final int stackDepth;
  final VoidCallback? onTap;

  const UQuietSurface({
    super.key,
    required this.child,
    this.padding = USpacing.cardPadding,
    this.radius = URadii.card,
    this.signalColor,
    this.pressed = false,
    this.stackDepth = 0,
    this.onTap,
  });

  @override
  State<UQuietSurface> createState() => _UQuietSurfaceState();
}

class _UQuietSurfaceState extends State<UQuietSurface> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final outerRadius = BorderRadius.circular(widget.radius + 2);
    final innerRadius = BorderRadius.circular(widget.radius);
    final depth = widget.stackDepth.clamp(0, 3);
    final content = AnimatedScale(
      duration: UDurations.fast,
      curve: Curves.easeOutCubic,
      scale: _down ? 0.985 : 1,
      child: AnimatedSlide(
        duration: UDurations.fast,
        curve: Curves.easeOutCubic,
        offset: _down ? const Offset(0, 0.012) : Offset.zero,
        child: Container(
          decoration: BoxDecoration(
            color: _folderBack(eu),
            borderRadius: outerRadius,
            border: Border.all(color: _folderEdge(eu)),
          ),
          child: ClipRRect(
            borderRadius: outerRadius,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: UDurations.normal,
                  curve: Curves.easeOutCubic,
                  left: 12,
                  top: 0,
                  width: 44.0 + depth * 4,
                  height: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _folderTab(eu),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < depth; i++)
                  AnimatedPositioned(
                    duration: UDurations.normal,
                    curve: Curves.easeOutCubic,
                    left: 5.0 + i * 3,
                    right: 5.0 - i * 1.5,
                    top: (_down ? 9.5 : 8.0) + i * 4,
                    bottom: (_down ? 5.5 : 7.0) - i,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _stackPaper(eu, i),
                        borderRadius: BorderRadius.circular(widget.radius - 1),
                        border: Border.all(color: _paperEdge(eu)),
                      ),
                    ),
                  ),
                AnimatedPadding(
                  duration: UDurations.fast,
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.fromLTRB(2, _down ? 12 : 11, 2, 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.pressed
                          ? _pressedColor(eu)
                          : _frontPaper(eu),
                      borderRadius: innerRadius,
                      border: Border.all(
                        color: widget.pressed
                            ? _pressedBorder(eu)
                            : _paperEdge(eu),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: innerRadius,
                      child: Stack(
                        children: [
                          if (widget.signalColor != null)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: widget.signalColor,
                                ),
                                child: const SizedBox(width: 2),
                              ),
                            ),
                          Padding(padding: widget.padding, child: widget.child),
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
    );

    if (widget.onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: content,
    );
  }

  static Color _folderBack(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0xFFECE7DD)
        : const Color(0xFF0E1116);
  }

  static Color _folderTab(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0xFFE3DDD1)
        : const Color(0xFF202631);
  }

  static Color _folderEdge(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0x18211F19)
        : const Color(0x12FFFFFF);
  }

  static Color _stackPaper(EurekaColors eu, int index) {
    if (eu.brightness == Brightness.dark) {
      return [
        const Color(0xFF15191F),
        const Color(0xFF181D24),
        const Color(0xFF1C222B),
      ][index.clamp(0, 2)];
    }
    return [
      const Color(0xFFF7F3EA),
      const Color(0xFFFAF7F0),
      const Color(0xFFFCFAF5),
    ][index.clamp(0, 2)];
  }

  static Color _frontPaper(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0xFFFFFEFB)
        : const Color(0xFF14181E);
  }

  static Color _paperEdge(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0x10211F19)
        : const Color(0x1AFFFFFF);
  }

  static Color _pressedColor(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0xFFFAF8F2)
        : const Color(0xFF171B20);
  }

  static Color _pressedBorder(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0x20211F19)
        : const Color(0x1FFFFFFF);
  }
}
