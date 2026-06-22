import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/today/bubble_physics.dart';

void main() {
  group('BubbleField solver', () {
    test('gravity pulls a bubble down; floor clamps it', () {
      final b = Bubble(id: 'a', x: 150, y: 50);
      final f = BubbleField(box: const Size(300, 500), bubbles: [b]);
      f.step();
      expect(b.vy, greaterThan(0));
      expect(b.y, greaterThan(50));
      for (var i = 0; i < 300; i++) {
        f.step();
      }
      expect(b.y, lessThanOrEqualTo(500 - b.r + 0.001)); // never below floor
    });

    test('overlapping bubbles separate after a step', () {
      final a = Bubble(id: 'a', x: 100, y: 100);
      final c = Bubble(id: 'c', x: 120, y: 100); // dist 20 < 46 = r+r
      final f = BubbleField(box: const Size(400, 400), bubbles: [a, c]);
      f.step();
      final dist = sqrt(pow(c.x - a.x, 2) + pow(c.y - a.y, 2));
      expect(dist, greaterThanOrEqualTo(a.r + c.r - 0.5));
    });

    test('a body entering the nav AABB is ejected out of it', () {
      const aabb = Rect.fromLTRB(100, 100, 200, 150);
      final b = Bubble(id: 'a', x: 150, y: 125); // dead center of the pill
      final f =
          BubbleField(box: const Size(300, 500), bubbles: [b], navAabb: aabb);
      f.step();
      expect(aabb.contains(Offset(b.x, b.y)), isFalse);
    });

    test('a sleeping body is an immovable anchor in relaxation', () {
      final anchor = Bubble(id: 'anchor', x: 150, y: 300)..sleeping = true;
      final ax0 = anchor.x, ay0 = anchor.y;
      final mover = Bubble(id: 'mover', x: 105, y: 300); // dist 45 < 46 (overlap ~1)
      final f = BubbleField(
          box: const Size(300, 600),
          bubbles: [anchor, mover],
          gravity: Offset.zero);
      f.step();
      // anchor stays put + asleep (gentle overlap < wakeImpact); mover pushed out.
      expect(anchor.x, closeTo(ax0, 0.001));
      expect(anchor.y, closeTo(ay0, 0.001));
      expect(anchor.sleeping, isTrue);
      final dist = sqrt(pow(mover.x - anchor.x, 2) + pow(mover.y - anchor.y, 2));
      expect(dist, greaterThanOrEqualTo(anchor.r + mover.r - 0.5));
    });

    test('a settled bubble sleeps; wake() revives it; anyAwake tracks it', () {
      final b = Bubble(id: 'a', x: 150, y: 50);
      final f = BubbleField(box: const Size(300, 500), bubbles: [b]);
      for (var i = 0; i < 250; i++) {
        f.step();
      }
      expect(b.sleeping, isTrue);
      expect(f.anyAwake, isFalse);
      b.wake();
      expect(b.sleeping, isFalse);
      expect(f.anyAwake, isTrue);
    });
  });
}
