import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../capture/reka_companion_controller.dart';
import '../capture/reka_terminal.dart';
import '../home/today_dithered_reka_config.dart';
import '../home/today_reka_motion_controller.dart';
import 'reka_mini.dart';
import 'theme_v2_floating_dock.dart';

enum RekaShellCompanionMode { today, mini }

class RekaShellCompanion extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, todayRekaController]),
      builder: (context, _) {
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180);
        final identity = controller.terminal?.identity ?? 'none';
        return AnimatedSwitcher(
          key: transitionKey,
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
            key: ValueKey<String>('${mode.name}:$identity'),
            child: _composition(context),
          ),
        );
      },
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
        final terminal = controller.terminal;
        final children = <Widget>[];

        if (mode == RekaShellCompanionMode.mini) {
          children.add(
            Positioned(
              left: (size.width - RekaMini.targetExtent) / 2,
              bottom: miniTargetBottom,
              child: RekaMini(
                onTap: onRekaTap,
                onLongPressStart: onLongPressStart,
                onLongPressMove: onLongPressMove,
                onLongPressEnd: onLongPressEnd,
                onLongPressCancel: onLongPressCancel,
              ),
            ),
          );
        }

        if (terminal != null) {
          final terminalWidth = math.min(
            RekaTerminal.maximumWidth,
            size.width - viewportMargin * 2,
          );
          final anchor = mode == RekaShellCompanionMode.today
              ? todayRekaController.rekaCenter
              : Offset(size.width / 2, size.height - miniTargetBottom);
          final left = (anchor.dx - terminalWidth / 2).clamp(
            viewportMargin,
            size.width - terminalWidth - viewportMargin,
          );

          if (mode == RekaShellCompanionMode.mini) {
            children.add(
              Positioned(
                left: left,
                width: terminalWidth,
                bottom: miniTargetBottom + RekaMini.targetExtent + terminalGap,
                child: _terminal(),
              ),
            );
          } else {
            const config = TodayDitheredRekaConfig();
            final anchorTop = anchor.dy - config.visibleBodyHeight / 2;
            final anchorBottom = anchor.dy + config.visibleBodyHeight / 2;
            final canOpenAbove =
                anchorTop >= estimatedTerminalHeight + viewportMargin;
            if (canOpenAbove) {
              children.add(
                Positioned(
                  left: left,
                  width: terminalWidth,
                  bottom: size.height - anchorTop + terminalGap,
                  child: _terminal(),
                ),
              );
            } else {
              final top = (anchorBottom + terminalGap).clamp(
                viewportMargin,
                size.height - estimatedTerminalHeight - viewportMargin,
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
    model: controller.terminal!,
    onClose: () => unawaited(controller.dismissTerminal()),
    onOpenDetail: controller.terminal!.canOpenDetail ? onOpenDetail : null,
  );
}
