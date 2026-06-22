import 'dart:ui' show Rect;

/// Treemap cell layout — slice-along-the-longer-side (a squarified approximation):
/// guarantees area ∝ value, full union of [rect], and no overlap, while keeping
/// aspect ratios reasonable for the small group counts the dashboard charts use.
/// Returns one Rect per input value, in input order. Pure → unit-tested
/// (test/charts_squarify_test.dart). The rose / bar / treemap CustomPainters that
/// consume this land in Slice 5.2's on-device step.
List<Rect> squarify(List<double> values, Rect rect) {
  if (values.isEmpty) return const [];
  final total = values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return List<Rect>.filled(values.length, Rect.zero);

  final out = <Rect>[];
  var free = rect;
  var remaining = total;
  for (var i = 0; i < values.length; i++) {
    if (i == values.length - 1) {
      out.add(free); // last cell takes all remaining free area
      break;
    }
    final frac = values[i] / remaining;
    if (free.width >= free.height) {
      final w = free.width * frac;
      out.add(Rect.fromLTWH(free.left, free.top, w, free.height));
      free = Rect.fromLTWH(free.left + w, free.top, free.width - w, free.height);
    } else {
      final h = free.height * frac;
      out.add(Rect.fromLTWH(free.left, free.top, free.width, h));
      free = Rect.fromLTWH(free.left, free.top + h, free.width, free.height - h);
    }
    remaining -= values[i];
  }
  return out;
}
