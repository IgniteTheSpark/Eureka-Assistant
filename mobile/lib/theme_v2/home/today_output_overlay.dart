import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'today_output_coordinator.dart';
import 'today_output_motion_plan.dart';

@immutable
class TodayAssetHandoff {
  const TodayAssetHandoff({required this.center, required this.velocity});

  final Offset center;
  final Offset velocity;
}

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
    this.onAssetHandoff,
    this.assetVisual,
    this.assetDiameter = 70,
  });

  final TodayOutputItem item;
  final double signalBoundaryY;
  final double assetFloorY;
  final TodayOutputSide? side;
  final ValueChanged<TodayOutputPhase>? onPhaseChanged;
  final ValueChanged<Offset>? onHandoff;
  final ValueChanged<TodayAssetHandoff>? onAssetHandoff;
  final Widget? assetVisual;
  final double assetDiameter;
  final VoidCallback onComplete;

  @override
  State<TodayOutputOverlay> createState() => _TodayOutputOverlayState();
}

class _TodayOutputOverlayState extends State<TodayOutputOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  TodayOutputMotionPlan? _plan;
  bool _startScheduled = false;
  TodayOutputPhase? _reportedPhase;
  bool _handedOff = false;
  bool _completed = false;
  Offset _destination = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_statusChanged);
    _controller.addListener(_progressChanged);
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
    final plan = _plan;
    if (plan == null) return;
    if (value >= plan.chargeEnd &&
        (_reportedPhase?.index ?? 0) < TodayOutputPhase.emit.index) {
      _reportPhase(TodayOutputPhase.emit);
    }
    if (value >= plan.travelEnd &&
        (_reportedPhase?.index ?? 0) < TodayOutputPhase.handoff.index) {
      _reportPhase(TodayOutputPhase.handoff);
      _handoff();
    }
    if (value >= plan.recoveryStart &&
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
    if (widget.item.kind == TodayOutputKind.asset) {
      widget.onAssetHandoff?.call(
        TodayAssetHandoff(center: _destination, velocity: _assetVelocity()),
      );
    }
  }

  Offset _assetVelocity() {
    final plan = _plan;
    if (plan == null || plan.travelDuration == Duration.zero) {
      return const Offset(0, 80);
    }
    final seconds = plan.travelDuration.inMicroseconds / 1000000;
    final displacement = _destination.dy - widget.item.source.dy;
    return Offset(0, 2 * displacement / seconds);
  }

  void _installMotionPlan(Offset source, Offset destination) {
    if (_plan != null) return;
    final plan = todayOutputMotionPlan(
      source: source,
      destination: destination,
      reduceMotion: widget.item.reduceMotion,
      kind: widget.item.kind,
    );
    _plan = plan;
    _controller.duration = plan.totalDuration;
    if (_startScheduled) return;
    _startScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScheduled = false;
      if (!mounted || _completed || _controller.isAnimating) return;
      _reportPhase(TodayOutputPhase.charge);
      _controller.forward();
    });
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
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final source = Offset(
            widget.item.source.dx.clamp(0, size.width),
            widget.item.source.dy.clamp(0, size.height),
          );
          final side = widget.side ?? widget.item.side;
          final sideSign = side == TodayOutputSide.right ? 1.0 : -1.0;
          final detached = Offset(
            (source.dx + sideSign * 44).clamp(12, size.width - 12),
            source.dy,
          );
          _destination = _handoffPoint(detached);
          _installMotionPlan(detached, _destination);
          if (widget.item.reduceMotion) {
            final visual = widget.assetVisual;
            if (widget.item.kind != TodayOutputKind.asset || visual == null) {
              return const SizedBox.expand();
            }
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    key: ValueKey('today-output-asset-ball-${widget.item.id}'),
                    left: _destination.dx - widget.assetDiameter / 2,
                    top: _destination.dy - widget.assetDiameter / 2,
                    width: widget.assetDiameter,
                    height: widget.assetDiameter,
                    child: Opacity(
                      opacity: 1 - _controller.value,
                      child: visual,
                    ),
                  ),
                ],
              ),
            );
          }
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final plan = _plan!;
              final raw = _controller.value;
              final charge = Curves.easeOutBack.transform(
                (raw / plan.chargeEnd).clamp(0.0, 1.0),
              );
              final travelSpan = plan.travelEnd - plan.chargeEnd;
              final travel = Curves.easeInOutCubic.transform(
                ((raw - plan.chargeEnd) / travelSpan).clamp(0.0, 1.0),
              );
              final center = Offset(
                detached.dx,
                lerpDouble(detached.dy, _destination.dy, travel)!,
              );
              final unfold =
                  ((raw - plan.travelEnd) /
                          (plan.recoveryStart - plan.travelEnd))
                      .clamp(0.0, 1.0);
              final recover =
                  ((raw - plan.recoveryStart) / (1 - plan.recoveryStart)).clamp(
                    0.0,
                    1.0,
                  );
              final signal = widget.item.kind == TodayOutputKind.signal;
              if (!signal) {
                final visual = widget.assetVisual;
                if (visual == null) return const SizedBox.expand();
                final gravity = ((raw - plan.chargeEnd) / travelSpan).clamp(
                  0.0,
                  1.0,
                );
                final assetCenter = Offset(
                  detached.dx,
                  lerpDouble(detached.dy, _destination.dy, gravity * gravity)!,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      key: ValueKey(
                        'today-output-asset-ball-${widget.item.id}',
                      ),
                      left: assetCenter.dx - widget.assetDiameter / 2,
                      top: assetCenter.dy - widget.assetDiameter / 2,
                      width: widget.assetDiameter,
                      height: widget.assetDiameter,
                      child: Opacity(
                        opacity: (1 - recover).clamp(0.0, 1.0),
                        child: visual,
                      ),
                    ),
                  ],
                );
              }
              final width = signal ? lerpDouble(20, 172, unfold)! : 20.0;
              final opacity = ((.35 + .65 * charge) * (1 - recover)).clamp(
                0.0,
                1.0,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  for (var index = 0; index < 3; index++)
                    _buildTrail(
                      index: index,
                      raw: raw,
                      detached: detached,
                      recover: recover,
                      plan: plan,
                    ),
                  Positioned(
                    key: ValueKey(
                      'today-output-${widget.item.kind.name}-${widget.item.id}',
                    ),
                    left: center.dx - width / 2,
                    top: center.dy - 10,
                    width: width,
                    height: 20,
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
        : widget.assetFloorY - (widget.item.reduceMotion ? 0 : 16),
  );

  Widget _buildTrail({
    required int index,
    required double raw,
    required Offset detached,
    required double recover,
    required TodayOutputMotionPlan plan,
  }) {
    final lag = .035 * (index + 1);
    final travelSpan = plan.travelEnd - plan.chargeEnd;
    final progress = Curves.easeInOutCubic.transform(
      (((raw - plan.chargeEnd) / travelSpan) - lag).clamp(0.0, 1.0),
    );
    final center = Offset(
      detached.dx,
      lerpDouble(detached.dy, _destination.dy, progress)!,
    );
    final size = 12.0 - index * 2;
    final travelVisibility = ((raw - plan.chargeEnd) / (travelSpan * .2)).clamp(
      0.0,
      1.0,
    );
    return Positioned(
      key: ValueKey('today-output-trail-$index'),
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: travelVisibility * (1 - recover) * (.28 - index * .07),
        child: const _TerminalSeed(stretched: false),
      ),
    );
  }
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
        : BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .58),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface,
              width: 1.25,
            ),
          ),
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
