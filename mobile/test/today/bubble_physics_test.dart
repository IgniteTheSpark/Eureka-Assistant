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
}
