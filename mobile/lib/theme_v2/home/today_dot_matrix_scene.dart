import 'package:flutter/material.dart';

import 'today_dot_matrix_painter.dart';

class TodayDotMatrixScene extends StatefulWidget {
  const TodayDotMatrixScene({
    super.key,
    required this.refreshEmphasis,
    required this.onRekaTap,
    this.menuExpanded = false,
  });

  final double refreshEmphasis;
  final VoidCallback onRekaTap;
  final bool menuExpanded;

  @override
  State<TodayDotMatrixScene> createState() => _TodayDotMatrixSceneState();
}

class _TodayDotMatrixSceneState extends State<TodayDotMatrixScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _breathing
        ..stop()
        ..value = 0;
    } else {
      _breathing.repeat();
    }
  }

  @override
  void dispose() {
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final geometry = TodayDotSceneGeometry.forSize(size);
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final reduceMotion = _reduceMotion ?? true;
        return ColoredBox(
          color: TodayDotMatrixPalette.light.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _breathing,
                  builder: (context, _) => CustomPaint(
                    painter: TodayDotMatrixPainter(
                      rekaPhase: _breathing.value,
                      refreshEmphasis: widget.refreshEmphasis,
                      reduceMotion: reduceMotion,
                      devicePixelRatio: devicePixelRatio,
                    ),
                  ),
                ),
              ),
              const Positioned(left: 18, top: 14, child: _TodayHeading()),
              Positioned(
                left: geometry.rekaCenter.dx + 61,
                top: geometry.rekaCenter.dy - 18,
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
                left: geometry.rekaCenter.dx - 32,
                top: geometry.rekaCenter.dy - 32,
                child: Semantics(
                  label: 'Reka 快捷操作',
                  button: true,
                  expanded: widget.menuExpanded,
                  onTap: widget.onRekaTap,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onRekaTap,
                      child: const SizedBox.square(dimension: 64),
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
  const _TodayHeading();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
