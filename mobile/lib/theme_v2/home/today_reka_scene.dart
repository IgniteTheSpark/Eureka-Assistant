import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../foundation/theme_v2_theme.dart';
import 'today_dithered_reka.dart';
import 'today_dithered_reka_config.dart';
import 'today_output_coordinator.dart';
import 'today_reka_capture_cue.dart';
import 'today_reka_motion_controller.dart';

typedef TodayRekaBuilder =
    Widget Function(
      BuildContext context,
      TodayRekaPose pose,
      bool active,
      bool reduceMotion,
      int refreshSignal,
      TodayOutputCue cue,
      TodayRekaCaptureCue captureCue,
    );

class TodayRekaScene extends StatefulWidget {
  const TodayRekaScene({
    super.key,
    required this.refreshSignal,
    required this.onRekaTap,
    this.controller,
    this.config = const TodayDitheredRekaConfig(),
    this.topChromeInset = 0,
    this.bottomChromeInset = 0,
    this.menuExpanded = false,
    this.now,
    this.active = true,
    this.rekaBuilder,
    this.content,
    this.cue = const TodayOutputCue.idle(),
    this.captureCue = const TodayRekaCaptureCue.idle(),
  });

  static const backgroundKey = ValueKey<String>('today-reka-background');
  static const rekaRenderKey = ValueKey<String>('today-reka-render');
  static const rekaTargetKey = ValueKey<String>('today-reka-drag-target');

  final int refreshSignal;
  final ValueChanged<Rect> onRekaTap;
  final TodayRekaMotionController? controller;
  final TodayDitheredRekaConfig config;
  final double topChromeInset;
  final double bottomChromeInset;
  final bool menuExpanded;
  final DateTime? now;
  final bool active;
  final TodayRekaBuilder? rekaBuilder;
  final Widget? content;
  final TodayOutputCue cue;
  final TodayRekaCaptureCue captureCue;

  @override
  State<TodayRekaScene> createState() => _TodayRekaSceneState();
}

class _TodayRekaSceneState extends State<TodayRekaScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _sceneKey = GlobalKey();
  final GlobalKey _rekaGeometryKey = GlobalKey();
  late final TodayRekaMotionController _controller;
  late final Ticker _ticker;
  late AppLifecycleState _lifecycleState;
  Duration? _lastElapsed;
  Duration? _lastDragTimestamp;
  Offset _dragGrabOffset = Offset.zero;
  Size _lastSize = Size.zero;
  EdgeInsets? _lastReservedInsets;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TodayRekaMotionController(config: widget.config);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _controller.step(0, reduceMotion: reduceMotion);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant TodayRekaScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(identical(oldWidget.controller, widget.controller));
    if (oldWidget.active && !widget.active) {
      _controller.cancelDrag();
      _lastDragTimestamp = null;
    }
    if (oldWidget.active != widget.active) _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      _controller.cancelDrag();
      _lastDragTimestamp = null;
    }
    _syncTicker();
  }

  void _syncTicker() {
    final shouldTick =
        widget.active &&
        _lifecycleState == AppLifecycleState.resumed &&
        !(_reduceMotion ?? true) &&
        _controller.state == TodayRekaMotionState.settling;
    if (shouldTick && !_ticker.isActive) {
      _lastElapsed = null;
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
  }

  void _onTick(Duration elapsed) {
    final deltaMicros = _lastElapsed == null
        ? 0
        : elapsed.inMicroseconds - _lastElapsed!.inMicroseconds;
    _lastElapsed = elapsed;
    _controller.step(
      (deltaMicros / Duration.microsecondsPerSecond).clamp(0.0, 1 / 20),
      reduceMotion: false,
    );
    if (mounted) setState(() {});
    _syncTicker();
  }

  RenderBox? get _sceneBox {
    final renderObject = _sceneKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  void _handlePanStart(DragStartDetails details) {
    if (!widget.active) return;
    final box = _sceneBox;
    if (box == null) return;
    final localPointer = box.globalToLocal(details.globalPosition);
    _dragGrabOffset = localPointer - _controller.rekaCenter;
    _lastDragTimestamp = details.sourceTimeStamp;
    _controller.beginDrag(_controller.rekaCenter);
    setState(() {});
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!widget.active) return;
    final box = _sceneBox;
    if (box == null) return;
    final timestamp = details.sourceTimeStamp;
    final elapsed = timestamp != null && _lastDragTimestamp != null
        ? timestamp - _lastDragTimestamp!
        : const Duration(milliseconds: 16);
    _lastDragTimestamp = timestamp;
    final localPointer = box.globalToLocal(details.globalPosition);
    _controller.updateDrag(localPointer - _dragGrabOffset, elapsed);
    setState(() {});
  }

  void _handlePanEnd(DragEndDetails details) {
    _lastDragTimestamp = null;
    _controller.endDrag();
    if (_reduceMotion ?? true) {
      _controller.step(0, reduceMotion: true);
    }
    setState(() {});
    _syncTicker();
  }

  void _handlePanCancel() {
    _lastDragTimestamp = null;
    _controller.cancelDrag();
    setState(() {});
    _syncTicker();
  }

  void _reportTapAnchor() {
    final renderObject = _rekaGeometryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    widget.onRekaTap(
      renderObject.localToGlobal(Offset.zero) & renderObject.size,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final reservedInsets = EdgeInsets.fromLTRB(
          4,
          widget.topChromeInset + 4,
          4,
          widget.bottomChromeInset + 4,
        );
        if (widget.active &&
            (size != _lastSize || reservedInsets != _lastReservedInsets) &&
            !size.isEmpty) {
          _lastSize = size;
          _lastReservedInsets = reservedInsets;
          _controller.layout(size, reservedInsets: reservedInsets);
        }

        final renderExtent = widget.config.renderExtent;
        final renderRadius = renderExtent / 2;
        final targetExtent = widget.config.hitExtent;
        final targetRadius = targetExtent / 2;
        final reduceMotion = _reduceMotion ?? true;
        final rekaBuilder = widget.rekaBuilder ?? _buildDefaultReka;

        return ColoredBox(
          key: TodayRekaScene.backgroundKey,
          color: context.themeV2.background,
          child: Stack(
            key: _sceneKey,
            fit: StackFit.expand,
            children: [
              if (widget.content case final content?)
                Positioned.fill(child: content)
              else
                Positioned(
                  left: 18,
                  top: widget.topChromeInset + 14,
                  child: _TodayHeading(now: widget.now ?? DateTime.now()),
                ),
              Positioned(
                left: _controller.rekaCenter.dx - renderRadius,
                top: _controller.rekaCenter.dy - renderRadius,
                width: renderExtent,
                height: renderExtent,
                child: KeyedSubtree(
                  key: TodayRekaScene.rekaRenderKey,
                  child: rekaBuilder(
                    context,
                    _controller.pose,
                    widget.active,
                    reduceMotion,
                    widget.refreshSignal,
                    widget.cue,
                    widget.captureCue,
                  ),
                ),
              ),
              Positioned(
                left: _controller.rekaCenter.dx - targetRadius,
                top: _controller.rekaCenter.dy - targetRadius,
                child: Semantics(
                  label: 'Reka 快捷操作，可拖动',
                  button: true,
                  expanded: widget.menuExpanded,
                  onTap: _reportTapAnchor,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      key: TodayRekaScene.rekaTargetKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.active ? _reportTapAnchor : null,
                      onPanStart: _handlePanStart,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: _handlePanEnd,
                      onPanCancel: _handlePanCancel,
                      child: SizedBox.square(
                        key: _rekaGeometryKey,
                        dimension: targetExtent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDefaultReka(
    BuildContext context,
    TodayRekaPose pose,
    bool active,
    bool reduceMotion,
    int refreshSignal,
    TodayOutputCue cue,
    TodayRekaCaptureCue captureCue,
  ) => TodayDitheredReka(
    pose: pose,
    active: active,
    reduceMotion: reduceMotion,
    refreshSignal: refreshSignal,
    cue: cue,
    config: widget.config,
  );
}

class _TodayHeading extends StatelessWidget {
  const _TodayHeading({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '今日',
        style: TextStyle(
          color: context.themeV2.foreground,
          fontSize: 24,
          height: 1,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        '${now.month}月${now.day}日 · ${_weekday(now.weekday)}',
        style: TextStyle(
          color: context.themeV2.muted,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w600,
          letterSpacing: .5,
        ),
      ),
    ],
  );
}

String _weekday(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
