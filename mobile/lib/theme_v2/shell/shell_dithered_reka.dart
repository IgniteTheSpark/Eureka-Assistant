import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../home/today_dithered_reka.dart';
import '../home/today_dithered_reka_config.dart';
import '../home/today_reka_motion_controller.dart';
import 'shell_reka_presentation_controller.dart';
import 'theme_v2_floating_dock.dart';

enum ShellDitheredRekaMode { today, dock }

class ShellDitheredReka extends StatefulWidget {
  const ShellDitheredReka({
    super.key,
    required this.mode,
    required this.motionController,
    required this.presentationController,
    this.interactive = true,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    this.forceFallback = false,
  });

  static const visualKey = ValueKey<String>('shell-dithered-reka-visual');
  static const visibleBoundsKey = ValueKey<String>(
    'shell-dithered-reka-visible-bounds',
  );
  static const breathingTransformKey = ValueKey<String>(
    'shell-dithered-reka-breathing-transform',
  );
  static const targetKey = ValueKey<String>('shell-dithered-reka-target');
  static const Size dockVisibleSize = Size(78, 54);
  static const double targetExtent = 72;
  static const transitionDuration = Duration(milliseconds: 260);

  final ShellDitheredRekaMode mode;
  final TodayRekaMotionController motionController;
  final ShellRekaPresentationController presentationController;
  final bool interactive;
  final ValueChanged<Rect> onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<double> onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
  final bool forceFallback;

  static Offset dockCenter(Size viewport, double safeBottom) => Offset(
    viewport.width / 2,
    viewport.height -
        math.max(safeBottom, ThemeV2FloatingDock.viewportBottomPadding) -
        ThemeV2FloatingDock.shellSize.height +
        -12,
  );

  @override
  State<ShellDitheredReka> createState() => _ShellDitheredRekaState();
}

class _ShellDitheredRekaState extends State<ShellDitheredReka>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _config = TodayDitheredRekaConfig();
  late final AnimationController _breathing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  final GlobalKey _targetGeometryKey = GlobalKey();
  double? _longPressOriginY;
  bool? _reduceMotion;
  bool _appIsResumed = true;
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.motionController.addListener(_onChanged);
    widget.presentationController.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant ShellDitheredReka oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.motionController, widget.motionController)) {
      oldWidget.motionController.removeListener(_onChanged);
      widget.motionController.addListener(_onChanged);
    }
    if (!identical(
      oldWidget.presentationController,
      widget.presentationController,
    )) {
      oldWidget.presentationController.removeListener(_onChanged);
      widget.presentationController.addListener(_onChanged);
    }
    _syncBreathing();
  }

  void _onChanged() {
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

  void _syncBreathing() {
    final shouldBreathe =
        widget.mode == ShellDitheredRekaMode.dock &&
        _reduceMotion == false &&
        _appIsResumed;
    if (shouldBreathe) {
      if (!_breathing.isAnimating) _breathing.repeat(reverse: true);
    } else {
      _breathing
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appIsResumed == resumed) return;
    _appIsResumed = resumed;
    _syncBreathing();
  }

  void _tap() {
    final renderObject = _targetGeometryKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      widget.onTap(renderObject.localToGlobal(Offset.zero) & renderObject.size);
    }
  }

  void _longPressStart(LongPressStartDetails details) {
    _longPressOriginY = details.globalPosition.dy;
    widget.onLongPressStart();
  }

  void _longPressMove(LongPressMoveUpdateDetails details) {
    final origin = _longPressOriginY;
    if (origin == null) return;
    widget.onLongPressMove(details.globalPosition.dy - origin);
  }

  void _longPressEnd(LongPressEndDetails details) {
    _longPressOriginY = null;
    widget.onLongPressEnd();
  }

  void _longPressCancel() {
    _longPressOriginY = null;
    widget.onLongPressCancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.motionController.removeListener(_onChanged);
    widget.presentationController.removeListener(_onChanged);
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion ?? true;
    final presentation = widget.presentationController.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (viewport.isEmpty) return const SizedBox.shrink();
        final center = widget.mode == ShellDitheredRekaMode.today
            ? widget.motionController.rekaCenter
            : ShellDitheredReka.dockCenter(
                viewport,
                MediaQuery.paddingOf(context).bottom,
              );
        final scale = widget.mode == ShellDitheredRekaMode.today
            ? 1.0
            : ShellDitheredReka.dockVisibleSize.width /
                  _config.visibleBodyWidth;
        final duration = reduceMotion
            ? Duration.zero
            : ShellDitheredReka.transitionDuration;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeInOutCubic,
              left: center.dx - _config.renderExtent / 2,
              top: center.dy - _config.renderExtent / 2,
              width: _config.renderExtent,
              height: _config.renderExtent,
              child: AnimatedScale(
                duration: duration,
                curve: Curves.easeInOutCubic,
                scale: scale,
                child: AnimatedBuilder(
                  animation: _breathing,
                  builder: (context, child) => Transform.translate(
                    key: ShellDitheredReka.breathingTransformKey,
                    offset: widget.mode == ShellDitheredRekaMode.dock
                        ? Offset(0, -_breathing.value * 2)
                        : Offset.zero,
                    child: Transform.scale(
                      scale: widget.mode == ShellDitheredRekaMode.dock
                          ? 1 + _breathing.value * .018
                          : 1,
                      child: child,
                    ),
                  ),
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      key: ShellDitheredReka.visualKey,
                      child: TodayDitheredReka(
                        pose: widget.motionController.pose,
                        active: true,
                        reduceMotion: reduceMotion,
                        refreshSignal: presentation.refreshSignal,
                        cue: presentation.cue,
                        captureCue: presentation.captureCue,
                        config: _config,
                        forceFallback: widget.forceFallback,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.mode == ShellDitheredRekaMode.dock)
              Positioned(
                key: ShellDitheredReka.visibleBoundsKey,
                left: center.dx - ShellDitheredReka.dockVisibleSize.width / 2,
                top: center.dy - ShellDitheredReka.dockVisibleSize.height / 2,
                width: ShellDitheredReka.dockVisibleSize.width,
                height: ShellDitheredReka.dockVisibleSize.height,
                child: const IgnorePointer(child: SizedBox.expand()),
              ),
            if (widget.mode == ShellDitheredRekaMode.dock && widget.interactive)
              Positioned(
                left: center.dx - ShellDitheredReka.targetExtent / 2,
                top: center.dy - ShellDitheredReka.targetExtent / 2,
                child: Semantics(
                  label: 'Reka，轻点继续最近对话，长按记录闪念，上滑取消，松开发送',
                  button: true,
                  onTap: _tap,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      key: ShellDitheredReka.targetKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: _tap,
                      onLongPressStart: _longPressStart,
                      onLongPressMoveUpdate: _longPressMove,
                      onLongPressEnd: _longPressEnd,
                      onLongPressCancel: _longPressCancel,
                      child: SizedBox.square(
                        key: _targetGeometryKey,
                        dimension: ShellDitheredReka.targetExtent,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
