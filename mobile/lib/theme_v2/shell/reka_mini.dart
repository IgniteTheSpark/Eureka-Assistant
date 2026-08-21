import 'package:flutter/material.dart';

class RekaMini extends StatefulWidget {
  const RekaMini({
    super.key,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  static const targetKey = ValueKey<String>('reka-mini-target');
  static const visualKey = ValueKey<String>('reka-mini-visual');
  static const Size visualSize = Size(64, 44);
  static const double targetExtent = 72;

  final ValueChanged<Rect> onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<double> onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;

  @override
  State<RekaMini> createState() => _RekaMiniState();
}

class _RekaMiniState extends State<RekaMini> {
  double? _longPressOriginY;

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
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reka 快捷操作，长按说话，上滑取消，松开发送',
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
            child: Center(
              child: SizedBox.fromSize(
                key: RekaMini.visualKey,
                size: RekaMini.visualSize,
                child: const CustomPaint(painter: _RekaMiniPainter()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RekaMiniPainter extends CustomPainter {
  const _RekaMiniPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shell = Paint()..color = const Color(0xFFF1EEE8);
    final shellShade = Paint()..color = const Color(0xFFAAA8A4);
    final visor = Paint()..color = const Color(0xFF15171C);
    final eye = Paint()..color = const Color(0xFF57DCF4);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, 4, size.width - 10, size.height - 8),
      const Radius.circular(18),
    );
    final face = RRect.fromRectAndRadius(
      Rect.fromLTWH(11, 10, size.width - 22, size.height - 19),
      const Radius.circular(12),
    );
    canvas.drawRRect(body, shell);
    canvas.drawRRect(face, visor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(20, 20, 8, 3),
        const Radius.circular(2),
      ),
      eye,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 28, 20, 8, 3),
        const Radius.circular(2),
      ),
      eye,
    );
    for (var row = 0; row < 3; row++) {
      for (var column = row.isEven ? 0 : 1; column < 8; column += 2) {
        canvas.drawRect(
          Rect.fromLTWH(15 + column * 4, 32 + row * 2, 1.7, 1.7),
          shellShade,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RekaMiniPainter oldDelegate) => false;
}
