import 'package:eureka/theme_v2/home/today_dithered_reka_config.dart';
import 'package:eureka/theme_v2/home/today_reka_motion_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodayDitheredRekaConfig', () {
    test('exposes the approved local render contract', () {
      const config = TodayDitheredRekaConfig();

      expect(config.renderExtent, 216);
      expect(config.hitExtent, 176);
      expect(config.maxTiltDegrees, 8);
      expect(config.ditherGridSize, 4);
      expect(config.pixelSizeRatio, 1);
      expect(config.maxDevicePixelRatio, 2);
    });

    test('rejects invalid geometry and renderer values', () {
      expect(
        () => TodayDitheredRekaConfig(renderExtent: 120, hitExtent: 176),
        throwsAssertionError,
      );
      expect(
        () => TodayDitheredRekaConfig(hitExtent: 40),
        throwsAssertionError,
      );
      expect(
        () => TodayDitheredRekaConfig(maxTiltDegrees: 0),
        throwsAssertionError,
      );
      expect(
        () => TodayDitheredRekaConfig(ditherGridSize: 0),
        throwsAssertionError,
      );
      expect(
        () => TodayDitheredRekaConfig(pixelSizeRatio: .5),
        throwsAssertionError,
      );
    });
  });

  group('TodayRekaMotionController', () {
    test('starts inside bounds that reserve the full render surface', () {
      final controller = TodayRekaMotionController()
        ..layout(
          const Size(411, 860),
          reservedInsets: const EdgeInsets.fromLTRB(18, 164, 18, 156),
        );

      expect(controller.state, TodayRekaMotionState.idle);
      _expectInsideInclusive(controller.safeBounds, controller.rekaCenter);
      expect(controller.safeBounds.left, 126);
      expect(controller.safeBounds.right, 285);
      expect(controller.pose.eyeOpacity, 1);
      expect(controller.pose.tiltXDegrees, 0);
      expect(controller.pose.tiltYDegrees, 0);
    });

    test('fast drag maps to capped tilt and permanent eyes', () {
      final controller = _laidOutController();
      final start = controller.rekaCenter;

      controller.beginDrag(start);
      controller.updateDrag(
        start + const Offset(180, -90),
        const Duration(milliseconds: 16),
      );

      expect(controller.pose.state, TodayRekaMotionState.dragging);
      expect(controller.pose.eyeOpacity, 1);
      expect(controller.pose.tiltXDegrees.abs(), lessThanOrEqualTo(8));
      expect(controller.pose.tiltYDegrees.abs(), lessThanOrEqualTo(8));
      expect(controller.pose.tiltXDegrees, greaterThan(0));
      expect(controller.pose.tiltYDegrees, greaterThan(0));
      _expectInsideInclusive(controller.safeBounds, controller.rekaCenter);
    });

    test('release settles inside bounds and returns tilt to zero', () {
      final controller = _laidOutController();
      final start = controller.rekaCenter;
      controller.beginDrag(start);
      controller.updateDrag(
        start + const Offset(100, -40),
        const Duration(milliseconds: 16),
      );
      controller.endDrag();

      expect(controller.state, TodayRekaMotionState.settling);
      for (var i = 0; i < 360 && !controller.isSettled; i++) {
        controller.step(1 / 60, reduceMotion: false);
      }

      expect(controller.state, TodayRekaMotionState.idle);
      _expectInsideInclusive(controller.safeBounds, controller.rekaCenter);
      expect(controller.pose.tiltXDegrees, 0);
      expect(controller.pose.tiltYDegrees, 0);
      expect(controller.dragVelocity, Offset.zero);
    });

    test('reduce motion removes settling and tilt', () {
      final controller = _laidOutController();
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(
        controller.rekaCenter + const Offset(80, 0),
        const Duration(milliseconds: 16),
      );
      controller.endDrag();
      controller.step(1 / 60, reduceMotion: true);

      expect(controller.pose.state, TodayRekaMotionState.idle);
      expect(controller.pose.tiltXDegrees, 0);
      expect(controller.pose.tiltYDegrees, 0);
      expect(controller.pose.eyeOpacity, 1);
      expect(controller.dragVelocity, Offset.zero);
    });

    test('resize preserves normalized resting position', () {
      final controller = _laidOutController();
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(
        const Offset(250, 490),
        const Duration(milliseconds: 40),
      );
      controller.cancelDrag();
      final before = controller.normalizedRekaPosition;

      controller.layout(
        const Size(411, 960),
        reservedInsets: const EdgeInsets.fromLTRB(18, 164, 18, 156),
      );

      expect(controller.normalizedRekaPosition.dx, closeTo(before.dx, .02));
      expect(controller.normalizedRekaPosition.dy, closeTo(before.dy, .02));
      _expectInsideInclusive(controller.safeBounds, controller.rekaCenter);
    });

    test('cancel drag immediately returns to a stable idle pose', () {
      final controller = _laidOutController();
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(
        controller.rekaCenter + const Offset(40, 20),
        const Duration(milliseconds: 20),
      );

      controller.cancelDrag();

      expect(controller.state, TodayRekaMotionState.idle);
      expect(controller.dragVelocity, Offset.zero);
      expect(controller.pose.tiltXDegrees, 0);
      expect(controller.pose.tiltYDegrees, 0);
    });
  });
}

TodayRekaMotionController _laidOutController() => TodayRekaMotionController()
  ..layout(
    const Size(411, 860),
    reservedInsets: const EdgeInsets.fromLTRB(18, 164, 18, 156),
  );

void _expectInsideInclusive(Rect bounds, Offset point) {
  expect(point.dx, inInclusiveRange(bounds.left, bounds.right));
  expect(point.dy, inInclusiveRange(bounds.top, bounds.bottom));
}
