import 'dart:ui' as ui;

import 'package:eureka/theme_v2/home/today_dot_matrix_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference geometry keeps an 8 px grid and bounded Reka', () {
    final geometry = TodayDotSceneGeometry.forSize(const Size(411, 860));

    expect(geometry.gridInterval, 8);
    expect(geometry.rekaCenter.dx, closeTo(78, 2));
    expect(geometry.rekaCenter.dy, closeTo(505, 4));
    expect(geometry.rekaInfluenceRadius, inInclusiveRange(86, 95));
  });

  test('unrelated painter inputs do not force repaint', () {
    const first = TodayDotMatrixPainter(
      rekaPhase: 0,
      refreshEmphasis: 0,
      reduceMotion: true,
      devicePixelRatio: 1,
    );
    const same = TodayDotMatrixPainter(
      rekaPhase: 0,
      refreshEmphasis: 0,
      reduceMotion: true,
      devicePixelRatio: 1,
    );

    expect(same.shouldRepaint(first), isFalse);
  });

  test('idle phase changes only the local Reka region', () async {
    final rest = await _paintPhase(0);
    final breath = await _paintPhase(.25);

    expect(
      await _regionBytes(rest, const Rect.fromLTWH(304, 304, 16, 16)),
      await _regionBytes(breath, const Rect.fromLTWH(304, 304, 16, 16)),
    );
    expect(
      await _regionBytes(rest, const Rect.fromLTWH(32, 456, 104, 104)),
      isNot(await _regionBytes(breath, const Rect.fromLTWH(32, 456, 104, 104))),
    );
  });
}

Future<ui.Image> _paintPhase(double phase) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(411, 860);
  TodayDotMatrixPainter(
    rekaPhase: phase,
    refreshEmphasis: 0,
    reduceMotion: false,
    devicePixelRatio: 1,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

Future<List<int>> _regionBytes(ui.Image image, Rect region) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(-region.left, -region.top);
  canvas.drawImage(image, Offset.zero, Paint());
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(
    region.width.toInt(),
    region.height.toInt(),
  );
  final data = await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List().toList(growable: false);
}
