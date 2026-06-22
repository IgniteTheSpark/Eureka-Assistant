import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/today/charts.dart';

void main() {
  test('squarify: area ∝ value, full union, no overlap', () {
    const rect = Rect.fromLTWH(0, 0, 120, 60);
    final cells = squarify([3, 2, 1], rect);
    expect(cells.length, 3);
    final rectArea = rect.width * rect.height; // 7200
    final areas = cells.map((c) => c.width * c.height).toList();
    expect(areas[0], closeTo(3 / 6 * rectArea, 1));
    expect(areas[1], closeTo(2 / 6 * rectArea, 1));
    expect(areas[2], closeTo(1 / 6 * rectArea, 1));
    expect(areas.reduce((a, b) => a + b), closeTo(rectArea, 1)); // full union
    for (var i = 0; i < cells.length; i++) {
      for (var j = i + 1; j < cells.length; j++) {
        final o = cells[i].intersect(cells[j]);
        expect(o.width <= 0 || o.height <= 0, isTrue); // no overlap
      }
    }
  });

  test('squarify: empty + zero-total', () {
    expect(squarify(const [], const Rect.fromLTWH(0, 0, 10, 10)), isEmpty);
    expect(squarify([0, 0], const Rect.fromLTWH(0, 0, 10, 10)).length, 2);
  });
}
