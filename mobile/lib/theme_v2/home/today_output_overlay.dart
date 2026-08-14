import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'today_output_coordinator.dart';

class TodayOutputOverlay extends StatefulWidget {
  const TodayOutputOverlay({
    super.key,
    required this.item,
    required this.signalBoundaryY,
    required this.assetFloorY,
    required this.onComplete,
    this.side,
    this.onPhaseChanged,
    this.onHandoff,
  });

  final TodayOutputItem item;
  final double signalBoundaryY;
  final double assetFloorY;
  final TodayOutputSide? side;
  final ValueChanged<TodayOutputPhase>? onPhaseChanged;
  final ValueChanged<Offset>? onHandoff;
  final VoidCallback onComplete;

  @override
  State<TodayOutputOverlay> createState() => _TodayOutputOverlayState();
}

class _TodayOutputOverlayState extends State<TodayOutputOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.item.reduceMotion
        ? const Duration(milliseconds: 140)
        : const Duration(milliseconds: 720),
  )..addStatusListener(_statusChanged);
  TodayOutputPhase? _reportedPhase;
  bool _handedOff = false;
  bool _completed = false;
  Offset _destination = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_progressChanged);
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reportPhase(TodayOutputPhase.charge);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_completed && !_controller.isAnimating) _controller.forward();
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  void _progressChanged() {
    final value = _controller.value;
    if (widget.item.reduceMotion) return;
    if (value >= .2 &&
        (_reportedPhase?.index ?? 0) < TodayOutputPhase.emit.index) {
      _reportPhase(TodayOutputPhase.emit);
    }
    if (value >= .72 &&
        (_reportedPhase?.index ?? 0) < TodayOutputPhase.handoff.index) {
      _reportPhase(TodayOutputPhase.handoff);
      _handoff();
    }
    if (value >= .9 &&
        (_reportedPhase?.index ?? 0) < TodayOutputPhase.recover.index) {
      _reportPhase(TodayOutputPhase.recover);
    }
  }

  void _reportPhase(TodayOutputPhase phase) {
    if (_reportedPhase == phase) return;
    _reportedPhase = phase;
    widget.onPhaseChanged?.call(phase);
  }

  void _handoff() {
    if (_handedOff) return;
    _handedOff = true;
    widget.onHandoff?.call(_destination);
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _completed) return;
    _completed = true;
    if (widget.item.reduceMotion) {
      _reportPhase(TodayOutputPhase.handoff);
      _handoff();
      _reportPhase(TodayOutputPhase.recover);
    } else {
      _handoff();
    }
    widget.onComplete();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_progressChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.reduceMotion) {
      _destination = _handoffPoint(widget.item.source);
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final source = Offset(
            widget.item.source.dx.clamp(0, size.width),
            widget.item.source.dy.clamp(0, size.height),
          );
          _destination = _handoffPoint(source);
          final side = widget.side ?? widget.item.side;
          final sideSign = side == TodayOutputSide.right ? 1.0 : -1.0;
          final detached = Offset(
            (source.dx + sideSign * 44).clamp(12, size.width - 12),
            source.dy,
          );
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final raw = _controller.value;
              final charge = Curves.easeOutBack.transform(
                (raw / .2).clamp(0.0, 1.0),
              );
              final travel = Curves.easeInOutCubic.transform(
                ((raw - .2) / .52).clamp(0.0, 1.0),
              );
              final center = Offset(
                detached.dx,
                lerpDouble(detached.dy, _destination.dy, travel)!,
              );
              final unfold = ((raw - .72) / .18).clamp(0.0, 1.0);
              final recover = ((raw - .9) / .1).clamp(0.0, 1.0);
              final signal = widget.item.kind == TodayOutputKind.signal;
              final width = signal ? lerpDouble(14, 172, unfold)! : 14.0;
              final opacity = (.35 + .65 * charge) * (1 - recover);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    key: ValueKey(
                      'today-output-${widget.item.kind.name}-${widget.item.id}',
                    ),
                    left: center.dx - width / 2,
                    top: center.dy - 7,
                    width: width,
                    height: 14,
                    child: Opacity(
                      opacity: opacity,
                      child: _TerminalSeed(
                        key: const ValueKey('today-output-seed'),
                        stretched: signal && unfold > 0,
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

  Offset _handoffPoint(Offset source) => Offset(
    source.dx,
    widget.item.kind == TodayOutputKind.signal
        ? widget.signalBoundaryY
        : widget.assetFloorY,
  );
}

class _TerminalSeed extends StatelessWidget {
  const _TerminalSeed({super.key, required this.stretched});

  final bool stretched;

  static const _green = Color(0xFF78FF74);

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: stretched
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _green.withValues(alpha: 0),
                _green.withValues(alpha: .8),
                _green.withValues(alpha: 0),
              ],
            ),
          )
        : const BoxDecoration(),
    child: Center(
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (var index = 0; index < 5; index++)
            SizedBox.square(
              dimension: index == 2 ? 4 : 3,
              child: ColoredBox(
                color: _green.withValues(alpha: index == 2 ? 1 : .68),
              ),
            ),
        ],
      ),
    ),
  );
}
