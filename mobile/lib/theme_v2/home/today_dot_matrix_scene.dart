import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'today_dot_field_controller.dart';
import 'today_dot_field_simulation.dart';
import 'today_dot_matrix_painter.dart';

class TodayDotMatrixScene extends StatefulWidget {
  const TodayDotMatrixScene({
    super.key,
    required this.refreshEmphasis,
    required this.onRekaTap,
    this.controller,
    this.simulation,
    this.menuExpanded = false,
    this.now,
    this.active = true,
  });

  static const rekaTargetKey = ValueKey<String>('today-reka-drag-target');

  final double refreshEmphasis;
  final ValueChanged<Rect> onRekaTap;
  final TodayDotFieldController? controller;
  final TodayDotFieldSimulation? simulation;
  final bool menuExpanded;
  final DateTime? now;
  final bool active;

  @override
  State<TodayDotMatrixScene> createState() => _TodayDotMatrixSceneState();
}

class _TodayDotMatrixSceneState extends State<TodayDotMatrixScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _reservedInsets = EdgeInsets.fromLTRB(18, 88, 18, 118);

  final GlobalKey _sceneKey = GlobalKey();
  final GlobalKey _rekaGeometryKey = GlobalKey();
  late final TodayDotFieldController _controller;
  late final TodayDotFieldSimulation _simulation;
  late final Ticker _ticker;
  late AppLifecycleState _lifecycleState;
  Duration? _lastElapsed;
  Duration? _lastDragTimestamp;
  Offset _dragGrabOffset = Offset.zero;
  Size _lastSize = Size.zero;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TodayDotFieldController();
    _simulation = widget.simulation ?? TodayDotFieldSimulation();
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
  void didUpdateWidget(covariant TodayDotMatrixScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(identical(oldWidget.controller, widget.controller));
    assert(identical(oldWidget.simulation, widget.simulation));
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
        !(_reduceMotion ?? true);
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
    final dt = (deltaMicros / Duration.microsecondsPerSecond).clamp(
      0.0,
      1 / 20,
    );
    _controller.step(dt, reduceMotion: false);
    _stepSimulation(dt);
    if (mounted) setState(() {});
  }

  void _stepSimulation(double dt) {
    _simulation.step(
      dt,
      rekaCenter: _controller.rekaCenter,
      state: _controller.state,
      dragEngagement: _controller.dragEngagement,
      breathAmount: _controller.breathAmount,
      reduceMotion: _reduceMotion ?? true,
    );
  }

  void _renderGestureFrame() {
    final reduceMotion = _reduceMotion ?? true;
    if (reduceMotion) {
      _controller.step(0, reduceMotion: true);
    }
    _stepSimulation(1 / 60);
    if (mounted) setState(() {});
  }

  RenderBox? get _sceneBox {
    final renderObject = _sceneKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  void _handlePanStart(DragStartDetails details) {
    final box = _sceneBox;
    if (box == null) return;
    final localPointer = box.globalToLocal(details.globalPosition);
    _dragGrabOffset = localPointer - _controller.rekaCenter;
    _lastDragTimestamp = details.sourceTimeStamp;
    _controller.beginDrag(_controller.rekaCenter);
    _renderGestureFrame();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final box = _sceneBox;
    if (box == null) return;
    final timestamp = details.sourceTimeStamp;
    final elapsed = timestamp != null && _lastDragTimestamp != null
        ? timestamp - _lastDragTimestamp!
        : const Duration(milliseconds: 16);
    _lastDragTimestamp = timestamp;
    final localPointer = box.globalToLocal(details.globalPosition);
    _controller.updateDrag(localPointer - _dragGrabOffset, elapsed);
    _renderGestureFrame();
  }

  void _handlePanEnd(DragEndDetails details) {
    _lastDragTimestamp = null;
    _controller.endDrag();
    _renderGestureFrame();
  }

  void _handlePanCancel() {
    _lastDragTimestamp = null;
    _controller.cancelDrag();
    _renderGestureFrame();
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
        if (size != _lastSize && !size.isEmpty) {
          _lastSize = size;
          _controller.layout(size, reservedInsets: _reservedInsets);
          _simulation.layout(size);
          _stepSimulation(0);
        }
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final reduceMotion = _reduceMotion ?? true;
        final copyLeft = (_controller.rekaCenter.dx + 61)
            .clamp(18.0, size.width - 110)
            .toDouble();
        final copyTop = (_controller.rekaCenter.dy - 18)
            .clamp(80.0, size.height - 90)
            .toDouble();

        return ColoredBox(
          color: TodayDotMatrixPalette.light.surface,
          child: Stack(
            key: _sceneKey,
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: TodayDotMatrixPainter(
                    simulation: _simulation,
                    rekaCenter: _controller.rekaCenter,
                    rekaState: _controller.state,
                    breathAmount: _controller.breathAmount,
                    eyeOpacity: _controller.eyeOpacity,
                    refreshEmphasis: widget.refreshEmphasis,
                    reduceMotion: reduceMotion,
                    devicePixelRatio: devicePixelRatio,
                  ),
                ),
              ),
              Positioned(
                left: 18,
                top: 14,
                child: _TodayHeading(now: widget.now ?? DateTime.now()),
              ),
              Positioned(
                left: copyLeft,
                top: copyTop,
                width: 92,
                child: Text(
                  '今天很安静，我在这里。',
                  style: TextStyle(
                    color: TodayDotMatrixPalette.light.muted,
                    fontSize: 11,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Positioned(
                left: _controller.rekaCenter.dx - 32,
                top: _controller.rekaCenter.dy - 32,
                child: Semantics(
                  label: 'Reka 快捷操作，可拖动',
                  button: true,
                  expanded: widget.menuExpanded,
                  onTap: _reportTapAnchor,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      key: TodayDotMatrixScene.rekaTargetKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: _reportTapAnchor,
                      onPanStart: _handlePanStart,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: _handlePanEnd,
                      onPanCancel: _handlePanCancel,
                      child: SizedBox.square(
                        key: _rekaGeometryKey,
                        dimension: 64,
                        child: const SizedBox.expand(),
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
}

class _TodayHeading extends StatelessWidget {
  const _TodayHeading({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '今日',
          style: TextStyle(
            color: TodayDotMatrixPalette.light.foreground,
            fontSize: 24,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${now.month}月${now.day}日 · ${_weekday(now.weekday)}',
          style: TextStyle(
            color: TodayDotMatrixPalette.light.muted,
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

String _weekday(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
