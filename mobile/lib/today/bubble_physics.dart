import 'dart:math' as math;
import 'dart:ui' show Offset, Size, Rect;

/// One physics body in the today-page bubble pool. Pure data + integrator state;
/// rendering lives in bubble_pool.dart. (Plan: spec/plan-today-page-landing.md Slice 4.)
class Bubble {
  Bubble({required this.id, required this.x, required this.y, this.r = 23});

  final String id;
  double x, y;
  double vx = 0, vy = 0;
  final double r;

  /// Sleeping = barely moved for [BubbleField.sleepAfter] frames → frozen. This is
  /// what removes idle jitter and lets the ticker stop (battery). Woken by a
  /// meaningful collision, drag, gravity change, or a new drop.
  bool sleeping = false;
  int _stillFrames = 0;
  double _px = 0, _py = 0; // position at the start of the current step

  void wake() {
    sleeping = false;
    _stillFrames = 0;
  }
}

/// Wall-less box solver: gravity + 4 walls (low restitution), the centered nav
/// pill as an AABB collider (bodies eject to its nearest edge → never trapped),
/// circle-circle positional relaxation, and position-delta sleeping. Constants
/// from the prototype README §Bubble. Pure (geometry types only) → unit-tested in
/// test/bubble_physics_test.dart.
class BubbleField {
  BubbleField({
    required this.box,
    required this.bubbles,
    this.navAabb,
    this.gravity = const Offset(0, 0.44),
  });

  Size box;
  Rect? navAabb;
  final List<Bubble> bubbles;
  Offset gravity;

  /// The bubble currently held by a finger: it skips gravity/integration + never
  /// sleeps (its position is driven directly by the drag). Null when not dragging.
  Bubble? held;

  static const double restitution = 0.06; // low bounce — settle, don't ring
  static const double damping = 0.93;
  static const double maxSpeed = 18.0;
  static const int relaxIters = 14;
  static const int sleepAfter = 12;
  static const double moveEps = 0.5; // px/frame net below which a body is "still"
  static const double wakeImpact = 1.5; // overlap that wakes a sleeping neighbor

  bool get anyAwake => bubbles.any((b) => !b.sleeping);

  void wakeAll() {
    for (final b in bubbles) {
      b.wake();
    }
  }

  void step() {
    // 1) integrate awake bodies + walls + nav-pill ejection
    for (final b in bubbles) {
      if (b.sleeping || identical(b, held)) continue;
      b._px = b.x;
      b._py = b.y;
      b.vx = (b.vx + gravity.dx) * damping;
      b.vy = (b.vy + gravity.dy) * damping;
      final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sp > maxSpeed) {
        final k = maxSpeed / sp;
        b.vx *= k;
        b.vy *= k;
      }
      b.x += b.vx;
      b.y += b.vy;
      if (b.x < b.r) {
        b.x = b.r;
        b.vx = -b.vx * restitution;
      } else if (b.x > box.width - b.r) {
        b.x = box.width - b.r;
        b.vx = -b.vx * restitution;
      }
      if (b.y < b.r) {
        b.y = b.r;
        b.vy = -b.vy * restitution;
      } else if (b.y > box.height - b.r) {
        b.y = box.height - b.r;
        b.vy = -b.vy * restitution;
      }
      _ejectAabb(b);
    }
    // 2) circle-circle positional relaxation (multi-pass). Push apart always; only
    //    a *meaningful* shove wakes a sleeping neighbor, so a settled stack with
    //    tiny gravity overlap can still sleep (the Δ-based check below sees net ~0).
    for (var iter = 0; iter < relaxIters; iter++) {
      for (var i = 0; i < bubbles.length; i++) {
        for (var j = i + 1; j < bubbles.length; j++) {
          final a = bubbles[i], c = bubbles[j];
          if (a.sleeping && c.sleeping) continue; // both anchored
          final dx = c.x - a.x, dy = c.y - a.y;
          final minD = a.r + c.r;
          var dist = math.sqrt(dx * dx + dy * dy);
          if (dist >= minD) continue;
          if (dist == 0) dist = 0.01;
          final overlap = minD - dist;
          final nx = dx / dist, ny = dy / dist;
          // A sleeping body is an immovable anchor: the awake body takes the full
          // correction; two awake bodies split it. This is what keeps a settled
          // pile stable — gravity can't keep nudging it into endless jitter.
          if (a.sleeping) {
            c.x += nx * overlap;
            c.y += ny * overlap;
          } else if (c.sleeping) {
            a.x -= nx * overlap;
            a.y -= ny * overlap;
          } else {
            final push = overlap / 2;
            a.x -= nx * push;
            a.y -= ny * push;
            c.x += nx * push;
            c.y += ny * push;
          }
          // Only a real impact (a fresh drop) wakes a sleeping neighbor — not the
          // hair-thin overlaps of a resting stack.
          if (overlap > wakeImpact) {
            if (a.sleeping) a.wake();
            if (c.sleeping) c.wake();
          }
        }
      }
    }
    // 3) sleeping: freeze bodies that barely moved (net position delta) this step.
    for (final b in bubbles) {
      if (b.sleeping || identical(b, held)) continue;
      final mdx = b.x - b._px, mdy = b.y - b._py;
      if (math.sqrt(mdx * mdx + mdy * mdy) < moveEps) {
        if (++b._stillFrames >= sleepAfter) {
          b.sleeping = true;
          b.vx = 0;
          b.vy = 0;
        }
      } else {
        b._stillFrames = 0;
      }
    }
  }

  /// Eject a body whose center entered the nav pill's radius-inflated AABB to the
  /// nearest edge (so it slides past, never trapped behind the pill).
  void _ejectAabb(Bubble b) {
    final aabb = navAabb;
    if (aabb == null) return;
    final ex = aabb.inflate(b.r);
    if (!ex.contains(Offset(b.x, b.y))) return;
    final dl = b.x - ex.left, dr = ex.right - b.x;
    final dt = b.y - ex.top, db = ex.bottom - b.y;
    final m = [dl, dr, dt, db].reduce(math.min);
    if (m == dl) {
      b.x = ex.left;
      b.vx = -b.vx.abs() * restitution;
    } else if (m == dr) {
      b.x = ex.right;
      b.vx = b.vx.abs() * restitution;
    } else if (m == dt) {
      b.y = ex.top;
      b.vy = -b.vy.abs() * restitution;
    } else {
      b.y = ex.bottom;
      b.vy = b.vy.abs() * restitution;
    }
  }
}
