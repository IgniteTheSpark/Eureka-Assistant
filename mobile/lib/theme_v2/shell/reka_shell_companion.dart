import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../capture/reka_companion_controller.dart';
import '../capture/reka_terminal.dart';
import '../home/today_dithered_reka_config.dart';
import '../home/today_reka_motion_controller.dart';
import 'reka_mini.dart';
import 'theme_v2_floating_dock.dart';

enum RekaShellCompanionMode { today, mini }

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
  });

  static const transitionKey = ValueKey<String>(
    'reka-shell-companion-transition',
  );
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
        final miniTargetBottom =
            bottomPadding +
            ThemeV2FloatingDock.dockHeight +
            ThemeV2FloatingDock.miniRekaGap -
            (RekaMini.targetExtent - RekaMini.visualSize.height) / 2;
        final terminal = widget.controller.terminal;
        final children = <Widget>[];

        if (widget.mode == RekaShellCompanionMode.mini) {
          children.add(
            Positioned(
              left: (size.width - RekaMini.targetExtent) / 2,
              bottom: miniTargetBottom,
              child: RekaMini(
                onTap: widget.onRekaTap,
                onLongPressStart: widget.onLongPressStart,
                onLongPressMove: widget.onLongPressMove,
                onLongPressEnd: widget.onLongPressEnd,
                onLongPressCancel: widget.onLongPressCancel,
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
              : Offset(size.width / 2, size.height - miniTargetBottom);
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
                    miniTargetBottom +
                    RekaMini.targetExtent +
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
