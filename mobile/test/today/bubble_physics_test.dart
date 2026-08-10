import 'dart:ui';

import 'package:eureka/today/bubble_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('field without a dock applies gravity and keeps bubbles in bounds', () {
    BubbleField? field;
    Object? constructorError;
    try {
      field =
          Function.apply(BubbleField.new, const [], {
                #box: const Size(200, 300),
                #gravity: const Offset(0, 20),
              })
              as BubbleField;
    } catch (error) {
      constructorError = error;
    }
    expect(
      constructorError,
      isNull,
      reason: 'BubbleField must support a panel with no Dock collider',
    );
    final fieldWithoutDock = field!;
    fieldWithoutDock.addBubble('asset-1', const Offset(100, 30), 20);
    final bubble = fieldWithoutDock.bubbles.single;
    final initialY = bubble.y;

    for (var step = 0; step < 60; step++) {
      fieldWithoutDock.step();
    }
    expect(bubble.y, greaterThan(initialY));

    for (var step = 0; step < 600; step++) {
      fieldWithoutDock.step();
    }
    expect(bubble.x, inInclusiveRange(20, 180));
    expect(bubble.y, inInclusiveRange(20, 280.5));
  });

  test('overlapping dynamic circles separate without tunneling', () {
    final field = BubbleField(
      box: const Size(240, 180),
      dock: const Rect.fromLTWH(0, 180, 0, 0),
      gravity: Offset.zero,
    );
    field
      ..addBubble('left', const Offset(100, 90), 20)
      ..addBubble('right', const Offset(130, 90), 20);

    for (var step = 0; step < 120; step++) {
      field.step();
    }

    final left = field.bubbles[0];
    final right = field.bubbles[1];
    final distance = Offset(left.x - right.x, left.y - right.y).distance;
    expect(distance, greaterThanOrEqualTo(39.5));
  });

  test('step recovers a sleeping bubble found outside the ceiling', () {
    final field = BubbleField(
      box: const Size(395, 340),
      gravity: const Offset(0, 20),
    )..addBubble('expense', const Offset(174, 31), 29);
    final expense = field.bubbles.single;
    final escapedPosition = expense.body.position.clone()..y = -1;
    expense.body.setTransform(escapedPosition, expense.angle);
    expense.body.setAwake(false);
    field.step();

    expect(expense.y, greaterThanOrEqualTo(expense.r));
    expect(expense.y, lessThanOrEqualTo(340 - expense.r));
    expect(expense.sleeping, isFalse);
  });

  test('bubble exposes the integrated Forge2D body angle', () {
    final field = BubbleField(box: const Size(240, 180), gravity: Offset.zero);
    field.addBubble('spinning', const Offset(120, 90), 20);
    final bubble = field.bubbles.single;
    bubble.body.angularVelocity = 2.5;

    for (var step = 0; step < 12; step++) {
      field.step();
    }

    double? exposedAngle;
    Object? angleReadError;
    try {
      exposedAngle = (bubble as dynamic).angle as double;
    } catch (error) {
      angleReadError = error;
    }

    expect(
      angleReadError,
      isNull,
      reason: 'Bubble must expose the Forge2D angle used by its renderer',
    );
    expect(bubble.body.angle, isNot(0));
    expect(exposedAngle, closeTo(bubble.body.angle, 0.000001));
  });

  test('a tilted collision produces physical circle spin', () {
    final field = BubbleField(
      box: const Size(240, 180),
      gravity: const Offset(12, 20),
    );
    field.addBubble('rolling', const Offset(50, 30), 20);
    final bubble = field.bubbles.single;
    var peakAngularVelocity = 0.0;

    for (var step = 0; step < 360; step++) {
      field.step();
      final angularVelocity = bubble.body.angularVelocity.abs();
      if (angularVelocity > peakAngularVelocity) {
        peakAngularVelocity = angularVelocity;
      }
    }

    expect(peakAngularVelocity, greaterThan(0.01));
    expect(bubble.body.angle.abs(), greaterThan(0.01));
  });
}
