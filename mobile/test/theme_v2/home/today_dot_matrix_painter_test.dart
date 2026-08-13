import 'dart:ui' as ui;

import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:eureka/theme_v2/home/today_dot_field_simulation.dart';
import 'package:eureka/theme_v2/home/today_dot_matrix_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference geometry starts Reka in the middle-left region', () {
    final geometry = TodayDotSceneGeometry.forSize(const Size(411, 860));

    expect(geometry.gridInterval, 8);
    expect(geometry.initialRekaCenter.dx, inInclusiveRange(80, 150));
    expect(geometry.initialRekaCenter.dy, inInclusiveRange(300, 470));
  });

  test('eyes change only the local eye region during exhale', () async {
    final inhale = await _paintState(eyeOpacity: 0, breathAmount: .7);
    final exhale = await _paintState(eyeOpacity: 1, breathAmount: .2);

    expect(
      await _regionBytes(inhale, const Rect.fromLTWH(300, 200, 20, 20)),
      await _regionBytes(exhale, const Rect.fromLTWH(300, 200, 20, 20)),
    );
    expect(
      await _regionBytes(inhale, const Rect.fromLTWH(88, 380, 64, 40)),
      isNot(await _regionBytes(exhale, const Rect.fromLTWH(88, 380, 64, 40))),
    );
  });

  test('same simulation revision and visual inputs do not repaint', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    final first = TodayDotMatrixPainter(
      simulation: simulation,
      rekaCenter: const Offset(120, 400),
      rekaState: TodayRekaMotionState.idle,
      breathAmount: 0,
      eyeOpacity: 0,
      refreshEmphasis: 0,
      reduceMotion: false,
      devicePixelRatio: 1,
    );
    final same = TodayDotMatrixPainter(
      simulation: simulation,
      rekaCenter: const Offset(120, 400),
      rekaState: TodayRekaMotionState.idle,
      breathAmount: 0,
      eyeOpacity: 0,
      refreshEmphasis: 0,
      reduceMotion: false,
      devicePixelRatio: 1,
    );

    expect(same.shouldRepaint(first), isFalse);
  });

  test('organic material has no hard circular boundary', () {
    const center = Offset(120, 400);
    final horizontal = TodayDotMatrixPainter.rekaMaterialFalloff(
      center + const Offset(39, 0),
      center,
    );
    final diagonal = TodayDotMatrixPainter.rekaMaterialFalloff(
      center + const Offset(27.5, 27.5),
      center,
    );

    expect(horizontal, isNot(closeTo(diagonal, .001)));
    expect(horizontal, inInclusiveRange(0, 1));
    expect(diagonal, inInclusiveRange(0, 1));
  });
}

Future<ui.Image> _paintState({
  required double eyeOpacity,
  required double breathAmount,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(411, 860);
  const rekaCenter = Offset(120, 400);
  final simulation = TodayDotFieldSimulation()..layout(size);
  simulation.step(
    1 / 60,
    rekaCenter: rekaCenter,
    state: TodayRekaMotionState.idle,
    dragEngagement: 0,
    breathAmount: breathAmount,
    reduceMotion: false,
  );
  TodayDotMatrixPainter(
    simulation: simulation,
    rekaCenter: rekaCenter,
    rekaState: TodayRekaMotionState.idle,
    breathAmount: breathAmount,
    eyeOpacity: eyeOpacity,
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
