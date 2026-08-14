import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'today_dither_material.dart';
import 'today_output_coordinator.dart';

class TodayOutputOverlay extends StatefulWidget {
  const TodayOutputOverlay({
    super.key,
    required this.item,
    required this.onComplete,
    this.onHandoff,
    this.motion,
  });

  final TodayOutputItem item;
  final VoidCallback onComplete;
  final ValueChanged<Offset>? onHandoff;
  final Animation<double>? motion;

  @override
  State<TodayOutputOverlay> createState() => _TodayOutputOverlayState();
}

class _TodayOutputOverlayState extends State<TodayOutputOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.item.reduceMotion
        ? const Duration(milliseconds: 140)
        : const Duration(milliseconds: 620),
  )..addStatusListener(_statusChanged);
  bool _completed = false;
  Offset _destination = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_completed && !_controller.isAnimating) _controller.forward();
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _completed) return;
    _completed = true;
    widget.onHandoff?.call(_destination);
    widget.onComplete();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? Colors.white : Colors.black;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final source = Offset(
            widget.item.source.dx.clamp(0, size.width),
            widget.item.source.dy.clamp(0, size.height),
          );
          final signal = widget.item.kind == TodayOutputKind.signal;
          final destination = signal
              ? Offset(size.width * .5, size.height * .2)
              : Offset(size.width * .5, size.height * .8);
          _destination = destination;
          final extent = signal ? const Size(172, 54) : const Size.square(62);
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final raw = _controller.value;
              final progress = Curves.easeOutCubic.transform(raw);
              final center = widget.item.reduceMotion
                  ? source
                  : Offset.lerp(source, destination, progress)!;
              final reveal = widget.item.reduceMotion
                  ? (raw / .45).clamp(0.0, 1.0)
                  : (raw / .28).clamp(0.0, 1.0);
              final scale = lerpDouble(.38, 1, reveal)!;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (signal && !widget.item.reduceMotion)
                    for (var index = 1; index <= 3; index++)
                      Positioned(
                        key: index == 1
                            ? const ValueKey('today-output-signal-trail')
                            : null,
                        left: center.dx - extent.width * .38,
                        top: center.dy + extent.height / 2 + index * 7,
                        width: extent.width * .76,
                        height: 4,
                        child: Opacity(
                          opacity: (1 - raw) * (.24 / index),
                          child: TodayDitherMaterial(
                            shape: TodayDitherShape.strip,
                            color: color,
                            strength: .5,
                            seed: index,
                            motion: widget.motion,
                            flow: .34,
                          ),
                        ),
                      ),
                  Positioned(
                    key: ValueKey(
                      'today-output-${widget.item.kind.name}-${widget.item.id}',
                    ),
                    left: center.dx - extent.width / 2,
                    top: center.dy - extent.height / 2,
                    width: extent.width,
                    height: extent.height,
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: reveal,
                        child: TodayDitherMaterial(
                          shape: signal
                              ? TodayDitherShape.strip
                              : TodayDitherShape.circle,
                          color: color.withValues(alpha: .72),
                          strength: .82,
                          seed: widget.item.id.hashCode,
                          motion: widget.motion,
                          flow: .28,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
