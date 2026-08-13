import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodayDotFieldController', () {
    test('starts in the middle-left safe region', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );

      expect(controller.state, TodayRekaMotionState.idle);
      expect(controller.safeBounds.contains(controller.rekaCenter), isTrue);
      expect(controller.rekaCenter.dx, inInclusiveRange(80, 150));
      expect(controller.rekaCenter.dy, inInclusiveRange(300, 470));
    });

    test('drag speed controls engagement and remains capped', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      final start = controller.rekaCenter;

      controller.beginDrag(start);
      controller.updateDrag(
        start + const Offset(20, 0),
        const Duration(milliseconds: 40),
      );
      final slow = controller.dragEngagement;
      controller.updateDrag(
        start + const Offset(180, 0),
        const Duration(milliseconds: 16),
      );

      expect(slow, greaterThan(0));
      expect(controller.dragEngagement, greaterThan(slow));
      expect(controller.dragEngagement, lessThanOrEqualTo(1));
      expect(controller.safeBounds.contains(controller.rekaCenter), isTrue);
    });

    test('exhale reveals eyes while inhale and drag hide them', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );

      controller.debugSetBreathPhase(.25);
      expect(controller.eyeOpacity, 0);
      controller.debugSetBreathPhase(.76);
      expect(controller.eyeOpacity, greaterThan(.75));
      controller.beginDrag(controller.rekaCenter);
      expect(controller.eyeOpacity, 0);
    });

    test('release settles inside bounds and resumes idle', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(
        const Offset(360, 410),
        const Duration(milliseconds: 16),
      );
      controller.endDrag();

      for (var i = 0; i < 360 && !controller.isSettled; i++) {
        controller.step(1 / 60, reduceMotion: false);
      }

      expect(controller.state, TodayRekaMotionState.idle);
      expect(
        controller.rekaCenter.dx,
        inInclusiveRange(
          controller.safeBounds.left,
          controller.safeBounds.right,
        ),
      );
      expect(
        controller.rekaCenter.dy,
        inInclusiveRange(
          controller.safeBounds.top,
          controller.safeBounds.bottom,
        ),
      );
      expect(controller.dragVelocity.distance, lessThan(.5));
    });

    test('reduce motion removes inertia and keeps quiet eyes visible', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(
        controller.rekaCenter + const Offset(90, 0),
        const Duration(milliseconds: 16),
      );
      controller.endDrag();
      controller.step(1 / 60, reduceMotion: true);

      expect(controller.state, TodayRekaMotionState.idle);
      expect(controller.dragVelocity, Offset.zero);
      expect(controller.eyeOpacity, closeTo(.42, .01));
    });

    test('resize preserves normalized resting position', () {
      final controller = TodayDotFieldController();
      controller.layout(
        const Size(411, 860),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );
      controller.beginDrag(controller.rekaCenter);
      controller.updateDrag(
        const Offset(300, 500),
        const Duration(milliseconds: 40),
      );
      controller.cancelDrag();
      final before = controller.normalizedRekaPosition;

      controller.layout(
        const Size(411, 960),
        reservedInsets: const EdgeInsets.fromLTRB(18, 88, 18, 118),
      );

      expect(controller.normalizedRekaPosition.dx, closeTo(before.dx, .02));
      expect(controller.normalizedRekaPosition.dy, closeTo(before.dy, .02));
      expect(controller.safeBounds.contains(controller.rekaCenter), isTrue);
    });
  });
}
