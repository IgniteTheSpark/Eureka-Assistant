import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../capture/reka_companion_controller.dart';
import '../capture/reka_terminal.dart';
import '../capture/reka_terminal_models.dart';
import '../home/today_dithered_reka_config.dart';
import '../home/today_reka_motion_controller.dart';
import 'reka_mini.dart';
import 'theme_v2_floating_dock.dart';

enum RekaShellCompanionMode { today, mini }

enum RekaShellHandoffDirection { toDock, toToday }

@visibleForTesting
Color rekaCockpitLightColor(RekaTerminalPhase? phase, Brightness brightness) =>
    switch (phase) {
      null =>
        brightness == Brightness.dark
            ? const Color(0x2EFFFFFF)
            : const Color(0x245E7180),
      RekaTerminalPhase.connecting ||
      RekaTerminalPhase.listening => const Color(0xAA53DDF5),
      RekaTerminalPhase.cancelArmed ||
      RekaTerminalPhase.failed ||
      RekaTerminalPhase.empty => const Color(0xAEEF6878),
      RekaTerminalPhase.transcribing ||
      RekaTerminalPhase.receiving ||
      RekaTerminalPhase.sending ||
      RekaTerminalPhase.understanding ||
      RekaTerminalPhase.organizing => const Color(0xAA826CFF),
      RekaTerminalPhase.done => const Color(0xAA78D98B),
    };

class RekaDockCockpit extends StatefulWidget {
  const RekaDockCockpit({
    super.key,
    required this.controller,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  static const lightKey = ValueKey<String>('reka-dock-cockpit-light');

  final RekaCompanionController controller;
  final ValueChanged<Rect> onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<double> onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;

  @override
  State<RekaDockCockpit> createState() => _RekaDockCockpitState();
}

class _RekaDockCockpitState extends State<RekaDockCockpit> {
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant RekaDockCockpit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!duringFrame) {
      setState(() {});
      return;
    }
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.controller.terminal?.phase;
    final light = rekaCockpitLightColor(phase, Theme.of(context).brightness);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: RekaDockCockpit.lightKey,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [light, light.withValues(alpha: 0)],
                  stops: const [.08, .82],
                ),
                boxShadow: [
                  BoxShadow(color: light, blurRadius: 18, spreadRadius: -8),
                ],
              ),
            ),
          ),
        ),
        RekaMini(
          phase: phase,
          onTap: widget.onTap,
          onLongPressStart: widget.onLongPressStart,
          onLongPressMove: widget.onLongPressMove,
          onLongPressEnd: widget.onLongPressEnd,
          onLongPressCancel: widget.onLongPressCancel,
        ),
      ],
    );
  }
}

class RekaShellCompanion extends StatefulWidget {
  const RekaShellCompanion({
    super.key,
    required this.mode,
    required this.controller,
    required this.todayRekaController,
    required this.onRekaTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    required this.onOpenDetail,
    this.handoffDirection,
    this.handoffEpoch = 0,
  });

  static const transitionKey = ValueKey<String>(
    'reka-shell-companion-transition',
  );
  static const handoffProxyKey = ValueKey<String>('reka-shell-handoff-proxy');
  static const handoffVisualKey = ValueKey<String>(
    'reka-shell-handoff-visual',
  );
  static const handoffDuration = Duration(milliseconds: 260);
  static const double terminalGap = 10;
  static const double viewportMargin = 16;
  static const double estimatedTerminalHeight = 224;

  final RekaShellCompanionMode mode;
  final RekaCompanionController controller;
  final TodayRekaMotionController todayRekaController;
  final ValueChanged<Rect> onRekaTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<double> onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
  final VoidCallback onOpenDetail;
  final RekaShellHandoffDirection? handoffDirection;
  final int handoffEpoch;

  @override
  State<RekaShellCompanion> createState() => _RekaShellCompanionState();
}

class _RekaShellCompanionState extends State<RekaShellCompanion> {
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPresentationChanged);
    widget.todayRekaController.addListener(_onPresentationChanged);
  }

  @override
  void didUpdateWidget(covariant RekaShellCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onPresentationChanged);
      widget.controller.addListener(_onPresentationChanged);
    }
    if (!identical(oldWidget.todayRekaController, widget.todayRekaController)) {
      oldWidget.todayRekaController.removeListener(_onPresentationChanged);
      widget.todayRekaController.addListener(_onPresentationChanged);
    }
  }

  void _onPresentationChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!duringFrame) {
      setState(() {});
      return;
    }
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPresentationChanged);
    widget.todayRekaController.removeListener(_onPresentationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final identity = widget.controller.terminal?.identity ?? 'none';
    return AnimatedSwitcher(
      key: RekaShellCompanion.transitionKey,
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey<String>('${widget.mode.name}:$identity'),
        child: _composition(context),
      ),
    );
  }

  Widget _composition(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const SizedBox.shrink();
        final bottomPadding = math.max(
          MediaQuery.paddingOf(context).bottom,
          ThemeV2FloatingDock.viewportBottomPadding,
        );
        final terminal = widget.controller.terminal;
        final children = <Widget>[];

        if (widget.handoffDirection case final direction?) {
          children.add(
            Positioned.fill(
              child: _RekaHandoffProxy(
                key: RekaShellCompanion.handoffProxyKey,
                direction: direction,
                epoch: widget.handoffEpoch,
                todayCenter: widget.todayRekaController.rekaCenter,
                dockCenter: Offset(
                  size.width / 2,
                  size.height -
                      bottomPadding -
                      ThemeV2FloatingDock.compositionHeight +
                      ThemeV2FloatingDock.cockpitTargetExtent / 2,
                ),
                phase: terminal?.phase,
              ),
            ),
          );
        }

        if (terminal != null) {
          final terminalWidth = math.min(
            RekaTerminal.maximumWidth,
            size.width - RekaShellCompanion.viewportMargin * 2,
          );
          final anchor = widget.mode == RekaShellCompanionMode.today
              ? widget.todayRekaController.rekaCenter
              : Offset(
                  size.width / 2,
                  size.height -
                      bottomPadding -
                      ThemeV2FloatingDock.compositionHeight +
                      ThemeV2FloatingDock.cockpitTargetExtent / 2,
                );
          final left = (anchor.dx - terminalWidth / 2).clamp(
            RekaShellCompanion.viewportMargin,
            size.width - terminalWidth - RekaShellCompanion.viewportMargin,
          );

          if (widget.mode == RekaShellCompanionMode.mini) {
            children.add(
              Positioned(
                left: left,
                width: terminalWidth,
                bottom:
                    bottomPadding +
                    ThemeV2FloatingDock.cockpitTopAboveDockBottom +
                    RekaShellCompanion.terminalGap,
                child: _terminal(),
              ),
            );
          } else {
            const config = TodayDitheredRekaConfig();
            final anchorTop = anchor.dy - config.visibleBodyHeight / 2;
            final anchorBottom = anchor.dy + config.visibleBodyHeight / 2;
            final canOpenAbove =
                anchorTop >=
                RekaShellCompanion.estimatedTerminalHeight +
                    RekaShellCompanion.viewportMargin;
            if (canOpenAbove) {
              children.add(
                Positioned(
                  left: left,
                  width: terminalWidth,
                  bottom:
                      size.height - anchorTop + RekaShellCompanion.terminalGap,
                  child: _terminal(),
                ),
              );
            } else {
              final top = (anchorBottom + RekaShellCompanion.terminalGap).clamp(
                RekaShellCompanion.viewportMargin,
                size.height -
                    RekaShellCompanion.estimatedTerminalHeight -
                    RekaShellCompanion.viewportMargin,
              );
              children.add(
                Positioned(
                  left: left,
                  width: terminalWidth,
                  top: top,
                  child: _terminal(),
                ),
              );
            }
          }
        }

        return SizedBox.expand(
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      },
    );
  }

  Widget _terminal() => RekaTerminal(
    model: widget.controller.terminal!,
    onClose: () => unawaited(widget.controller.dismissTerminal()),
    onOpenDetail: widget.controller.terminal!.canOpenDetail
        ? widget.onOpenDetail
        : null,
  );
}

class _RekaHandoffProxy extends StatelessWidget {
  const _RekaHandoffProxy({
    super.key,
    required this.direction,
    required this.epoch,
    required this.todayCenter,
    required this.dockCenter,
    required this.phase,
  });

  final RekaShellHandoffDirection direction;
  final int epoch;
  final Offset todayCenter;
  final Offset dockCenter;
  final RekaTerminalPhase? phase;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final from = direction == RekaShellHandoffDirection.toDock
        ? todayCenter
        : dockCenter;
    final to = direction == RekaShellHandoffDirection.toDock
        ? dockCenter
        : todayCenter;
    const fullScale = 2.75;

    return IgnorePointer(
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          key: ValueKey<int>(epoch),
          tween: Tween(begin: 0, end: 1),
          duration: RekaShellCompanion.handoffDuration,
          curve: Curves.easeInOutCubic,
          builder: (context, progress, child) {
            final center = reduceMotion ? to : Offset.lerp(from, to, progress)!;
            final startScale = direction == RekaShellHandoffDirection.toDock
                ? fullScale
                : 1.0;
            final endScale = direction == RekaShellHandoffDirection.toDock
                ? 1.0
                : fullScale;
            final scale = reduceMotion
                ? endScale
                : startScale + (endScale - startScale) * progress;
            final opacity = reduceMotion
                ? math.sin(progress * math.pi).clamp(0.0, 1.0).toDouble()
                : 1.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: center.dx - RekaMini.visualSize.width / 2,
                  top: center.dy - RekaMini.visualSize.height / 2,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: child),
                  ),
                ),
              ],
            );
          },
          child: RepaintBoundary(
            key: RekaShellCompanion.handoffVisualKey,
            child: RekaMiniVisual(phase: phase),
          ),
        ),
      ),
    );
  }
}
