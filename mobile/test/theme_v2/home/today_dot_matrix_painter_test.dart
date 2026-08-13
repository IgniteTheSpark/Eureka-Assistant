import 'dart:ui' as ui;

import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:eureka/theme_v2/home/today_dot_field_config.dart';
import 'package:eureka/theme_v2/home/today_dot_field_simulation.dart';
import 'package:eureka/theme_v2/home/today_dot_matrix_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference geometry starts Reka in the middle-left region', () {
    final geometry = TodayDotSceneGeometry.forSize(const Size(411, 860));

    expect(geometry.gridInterval, 14);
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

  test('Reka rise spreads beyond a circular core without a dark rim', () async {
    const config = TodayDotFieldConfig(
      cursorRadius: 36,
      glowRadius: 76,
      dotSpacing: 14,
      glowColor: Colors.black,
    );
    final image = await _renderPainter(
      config: config,
      rekaCenter: const Offset(100, 100),
      breathAmount: 1,
      eyeOpacity: 0,
    );

    final center = await _pixel(image, 94, 94);
    final horizontalFalloff = await _pixel(image, 140, 100);
    final verticalFalloff = await _pixel(image, 100, 140);
    final outside = await _pixel(image, 190, 100);

    expect(_brightness(center), greaterThan(_brightness(outside)));
    expect(_brightness(horizontalFalloff), greaterThan(_brightness(outside)));
    expect(horizontalFalloff, isNot(verticalFalloff));
  });

  test('eyes render as two warm 3 by 3 LED matrices', () async {
    final visible = await _renderPainter(
      config: const TodayDotFieldConfig(),
      rekaCenter: const Offset(100, 100),
      breathAmount: 1,
      eyeOpacity: 1,
    );
    final hidden = await _renderPainter(
      config: const TodayDotFieldConfig(),
      rekaCenter: const Offset(100, 100),
      breathAmount: 1,
      eyeOpacity: 0,
    );

    for (final eyeCenterX in [85, 115]) {
      for (final row in [-1, 0, 1]) {
        for (final column in [-1, 0, 1]) {
          expect(
            await _pixel(visible, eyeCenterX + column * 5, 100 + row * 5),
            isNot(await _pixel(hidden, eyeCenterX + column * 5, 100 + row * 5)),
          );
        }
      }
    }
    expect(
      _warmth(await _pixel(visible, 85, 100)),
      greaterThan(_warmth(await _pixel(visible, 80, 95))),
    );
  });

  test('robot eyes remain hidden while dragging', () async {
    final hidden = await _renderPainter(
      config: const TodayDotFieldConfig(),
      rekaCenter: const Offset(100, 100),
      breathAmount: 1,
      eyeOpacity: 0,
    );
    final dragging = await _renderPainter(
      config: const TodayDotFieldConfig(),
      rekaCenter: const Offset(100, 100),
      rekaState: TodayRekaMotionState.dragging,
      breathAmount: 1,
      eyeOpacity: 1,
    );

    expect(
      await _regionBytes(hidden, const Rect.fromLTWH(72, 88, 56, 24)),
      await _regionBytes(dragging, const Rect.fromLTWH(72, 88, 56, 24)),
    );
  });

  test('gradient and sparkle parameters affect dot rendering', () async {
    final image = await _renderPainter(
      config: const TodayDotFieldConfig(
        gradientFrom: Colors.red,
        gradientTo: Colors.blue,
        sparkle: true,
      ),
      rekaCenter: const Offset(100, 100),
      breathAmount: 0,
      eyeOpacity: 0,
    );

    expect(await _pixel(image, 7, 7), isNot(await _pixel(image, 189, 189)));
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
    fieldPhase: 0,
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

Future<ui.Image> _renderPainter({
  required TodayDotFieldConfig config,
  required Offset rekaCenter,
  required double breathAmount,
  required double eyeOpacity,
  TodayRekaMotionState rekaState = TodayRekaMotionState.idle,
}) async {
  const size = Size.square(200);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final simulation = TodayDotFieldSimulation(config: config)..layout(size);
  simulation.step(
    1 / 60,
    rekaCenter: rekaCenter,
    state: rekaState,
    dragEngagement: rekaState == TodayRekaMotionState.dragging ? 1 : 0,
    breathAmount: breathAmount,
    fieldPhase: 0,
    reduceMotion: false,
  );
  TodayDotMatrixPainter(
    config: config,
    simulation: simulation,
    rekaCenter: rekaCenter,
    rekaState: rekaState,
    breathAmount: breathAmount,
    eyeOpacity: eyeOpacity,
    refreshEmphasis: 0,
    reduceMotion: false,
    devicePixelRatio: 1,
  ).paint(canvas, size);
  return recorder.endRecording().toImage(200, 200);
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

int _brightness(Color color) => ((color.r + color.g + color.b) * 255).round();

int _warmth(Color color) => ((color.r - color.b) * 255).round();

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
