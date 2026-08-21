import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../capture/reka_terminal_models.dart';

class RekaMini extends StatefulWidget {
  const RekaMini({
    super.key,
    this.phase,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  static const targetKey = ValueKey<String>('reka-mini-target');
  static const visualKey = ValueKey<String>('reka-mini-visual');
  static const shellKey = ValueKey<String>('reka-mini-shell');
  static const visorKey = ValueKey<String>('reka-mini-visor');
  static const Size visualSize = Size(66, 48);
  static const double targetExtent = 72;

  final RekaTerminalPhase? phase;
  final ValueChanged<Rect> onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<double> onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;

  @override
  State<RekaMini> createState() => _RekaMiniState();
}

class _RekaMiniState extends State<RekaMini>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breathing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  double? _longPressOriginY;
  bool? _reduceMotion;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    _syncBreathing();
  }

  void _syncBreathing() {
    if (_reduceMotion == true || !_appActive) {
      _breathing
        ..stop()
        ..value = 0;
      return;
    }
    if (!_breathing.isAnimating) {
      _breathing.repeat(reverse: true);
    }
  }

  void _tap() {
    final box = context.findRenderObject()! as RenderBox;
    widget.onTap(box.localToGlobal(Offset.zero) & box.size);
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
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reka，轻点继续最近对话，长按记录闪念，上滑取消，松开发送',
      button: true,
      onTap: _tap,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: RekaMini.targetKey,
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          onLongPressStart: _longPressStart,
          onLongPressMoveUpdate: _longPressMove,
          onLongPressEnd: _longPressEnd,
          onLongPressCancel: _longPressCancel,
          child: SizedBox.square(
            dimension: RekaMini.targetExtent,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedBuilder(
                animation: _breathing,
                builder: (context, child) {
                  final lift = _breathing.value;
                  return Transform.translate(
                    offset: Offset(0, -lift * 1.2),
                    child: Transform.scale(
                      scale: 1 + lift * .018,
                      child: child,
                    ),
                  );
                },
                child: RepaintBoundary(
                  child: RekaMiniVisual(phase: widget.phase, debugKeys: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The non-interactive native Reka artwork used by visual-only transitions.
class RekaMiniVisual extends StatelessWidget {
  const RekaMiniVisual({super.key, this.phase, this.debugKeys = false});

  final RekaTerminalPhase? phase;
  final bool debugKeys;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    key: debugKeys ? RekaMini.visualKey : null,
    size: RekaMini.visualSize,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          key: debugKeys ? RekaMini.shellKey : null,
          painter: const _RekaMiniShellPainter(),
        ),
        CustomPaint(
          key: debugKeys ? RekaMini.visorKey : null,
          painter: _RekaMiniVisorPainter(phase),
        ),
      ],
    ),
  );
}

class _RekaMiniShellPainter extends CustomPainter {
  const _RekaMiniShellPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final contactRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height - 3),
      width: 43,
      height: 7,
    );
    canvas.drawOval(
      contactRect,
      Paint()
        ..color = const Color(0x3D10151C)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    final leftModule = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 13, 11, 25),
      const Radius.circular(5),
    );
    final rightModule = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 14, 13, 11, 25),
      const Radius.circular(5),
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(7, 4, size.width - 14, size.height - 9),
      const Radius.circular(18),
    );
    final shellRect = body.outerRect;
    final shellPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF2EFE8), Color(0xFFB9B7B2)],
        stops: [0, .58, 1],
      ).createShader(shellRect);
    final modulePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF8F5EE), Color(0xFFA19F9B)],
      ).createShader(Rect.fromLTWH(0, 10, size.width, 31));

    canvas.drawRRect(leftModule, modulePaint);
    canvas.drawRRect(rightModule, modulePaint);
    canvas.drawRRect(body, shellPaint);

    canvas.save();
    canvas.clipRRect(body);
    final shadeRect = Rect.fromLTWH(7, 30, size.width - 14, 13);
    canvas.drawRect(
      shadeRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0x66908F8B)],
        ).createShader(shadeRect),
    );
    const highlightRect = Rect.fromLTWH(15, 6, 27, 8);
    canvas.drawOval(
      highlightRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xCFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(highlightRect),
    );
    canvas.restore();

    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0x5A777873)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );

    final dither = Paint()..color = const Color(0x7094938F);
    for (var row = 0; row < 2; row++) {
      for (var column = row; column < 9; column += 2) {
        canvas.drawRect(
          Rect.fromLTWH(15 + column * 4, 36 + row * 3, 1.6, 1.6),
          dither,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RekaMiniShellPainter oldDelegate) => false;
}

class _RekaMiniVisorPainter extends CustomPainter {
  const _RekaMiniVisorPainter(this.phase);

  final RekaTerminalPhase? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final visor = RRect.fromRectAndRadius(
      Rect.fromLTWH(13, 10, size.width - 26, 24),
      const Radius.circular(11),
    );
    canvas.drawRRect(
      visor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF343940), Color(0xFF111319), Color(0xFF05070A)],
          stops: [0, .45, 1],
        ).createShader(visor.outerRect),
    );
    canvas.save();
    canvas.clipRRect(visor);
    const reflectionRect = Rect.fromLTWH(17, 11, 29, 7);
    canvas.drawOval(
      reflectionRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x5AFFFFFF), Color(0x00FFFFFF)],
        ).createShader(reflectionRect),
    );
    canvas.restore();

    _drawEye(canvas, const Offset(21, 17), left: true);
    _drawEye(canvas, const Offset(39, 17), left: false);
  }

  void _drawEye(Canvas canvas, Offset origin, {required bool left}) {
    final paint = Paint()..color = _eyeColor(phase);
    for (final index in rekaMiniEyePattern(phase, left: left)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            origin.dx + (index % 3) * 3.2,
            origin.dy + (index ~/ 3) * 3.2,
            2.3,
            2.3,
          ),
          const Radius.circular(.7),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RekaMiniVisorPainter oldDelegate) =>
      phase != oldDelegate.phase;
}

Color _eyeColor(RekaTerminalPhase? phase) => switch (phase) {
  RekaTerminalPhase.cancelArmed ||
  RekaTerminalPhase.empty ||
  RekaTerminalPhase.failed => const Color(0xFFFF7A82),
  RekaTerminalPhase.done => const Color(0xFF8BFA91),
  RekaTerminalPhase.transcribing ||
  RekaTerminalPhase.sending ||
  RekaTerminalPhase.receiving ||
  RekaTerminalPhase.understanding ||
  RekaTerminalPhase.organizing => const Color(0xFF9B8CFF),
  _ => const Color(0xFF72EEFF),
};

@visibleForTesting
List<int> rekaMiniEyePattern(RekaTerminalPhase? phase, {required bool left}) =>
    switch (phase) {
      null || RekaTerminalPhase.connecting => const [0, 1, 2, 3, 5, 6, 7, 8],
      RekaTerminalPhase.listening => const [0, 1, 2, 3, 4, 5, 6, 7, 8],
      RekaTerminalPhase.cancelArmed => const [0, 2, 4, 6, 8],
      RekaTerminalPhase.transcribing => const [0, 1, 2, 6, 7, 8],
      RekaTerminalPhase.receiving => left ? const [0, 3, 6] : const [2, 5, 8],
      RekaTerminalPhase.sending ||
      RekaTerminalPhase.understanding => const [1, 3, 4, 5, 7],
      RekaTerminalPhase.organizing => const [0, 4, 8],
      RekaTerminalPhase.done => const [1, 3, 4, 5],
      RekaTerminalPhase.empty => const [3, 4, 5],
      RekaTerminalPhase.failed => left ? const [0, 4, 8] : const [2, 4, 6],
    };

@visibleForTesting
double rekaMiniPerspectiveTilt(double phase) =>
    math.sin(phase * math.pi * 2) * .008;
