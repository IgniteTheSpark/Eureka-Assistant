import 'dart:ui' show Offset, Size, Rect;

import 'package:forge2d/forge2d.dart';

/// Pixels per Box2D meter. Box2D is tuned for objects ~0.1–10 m, so a 23 px
/// bubble ≈ 0.57 m at this scale.
const double _scale = 40.0;

/// One pool bubble = a forge2d dynamic circle. x / y / r stay in **pixels** (the
/// field maps to / from Box2D meters), so the renderer + pool are unchanged.
class Bubble {
  Bubble(this.id, this.body, this.r);

  final String id;
  final Body body;
  final double r; // px

  double get x => body.position.x * _scale;
  double get y => body.position.y * _scale;
  bool get sleeping => !body.isAwake;
  void wake() => body.setAwake(true);
}

/// forge2d-backed bubble pool (≈ the Matter.js reference): bouncy, rolly circles
/// in a closed box whose floor is a ∧ "tent" peaking at the dock's top-center —
/// so bodies slide to the two sides and can never overlap or sink under the dock.
/// Drag = velocity-chase toward the finger; gravity follows device tilt; sleeping
/// + battery handled by Box2D's native body sleep. y is screen-down (gravity +y).
class BubbleField {
  BubbleField({
    required this.box,
    required Rect dock,
    Offset gravity = const Offset(0, _gMag),
  }) : _world = World(Vector2(gravity.dx, gravity.dy)) {
    _buildBounds(dock);
  }

  static const double _gMag = 20.0; // gravity magnitude (m/s² in world units)
  static const double restitution = 0.45; // bounce on landing

  final World _world;
  Size box;
  final List<Bubble> bubbles = [];
  Body? _held;

  bool get anyAwake => bubbles.any((b) => b.body.isAwake);

  void wakeAll() {
    for (final b in bubbles) {
      b.body.setAwake(true);
    }
  }

  set gravity(Offset g) => _world.gravity = Vector2(g.dx, g.dy);

  void step([double dt = 1 / 60]) => _world.stepDt(dt);

  // ── static bounds: ∧ tent floor (apex at dock-top-center) + walls + ceiling ──
  void _buildBounds(Rect dock) {
    final w = box.width / _scale, h = box.height / _scale;
    final apex = Vector2(w / 2, dock.top / _scale);
    final body = _world.createBody(BodyDef()..type = BodyType.static);
    void edge(Vector2 a, Vector2 b) => body.createFixture(
      FixtureDef(EdgeShape()..set(a, b), friction: 0.4, restitution: 0.1),
    );
    // tent: bottom-left corner → apex → bottom-right corner (two diverging lines)
    edge(Vector2(0, h), apex);
    edge(apex, Vector2(w, h));
    // side walls + ceiling close the box (flip-to-rise rests against the top)
    edge(Vector2(0, 0), Vector2(0, h));
    edge(Vector2(w, 0), Vector2(w, h));
    edge(Vector2(0, 0), Vector2(w, 0));
  }

  /// Add a dynamic bubble at [posPx] (pixels). Drop-in spawns it above the top.
  void addBubble(String id, Offset posPx, double rPx) {
    final b = _world.createBody(
      BodyDef()
        ..type = BodyType.dynamic
        ..position = Vector2(posPx.dx / _scale, posPx.dy / _scale)
        ..linearDamping = 0.15
        ..angularDamping = 0.3
        // continuous collision — small fast circles must not tunnel the thin
        // tent edges on the way down.
        ..bullet = true,
    );
    b.createFixture(
      FixtureDef(
        CircleShape()..radius = rPx / _scale,
        density: 1.0,
        friction: 0.08,
        restitution: restitution,
      ),
    );
    bubbles.add(Bubble(id, b, rPx));
  }

  void removeBubble(Bubble bubble) {
    _world.destroyBody(bubble.body);
    bubbles.remove(bubble);
  }

  bool has(String id) => bubbles.any((b) => b.id == id);

  // ── drag: chase the finger by velocity (soft follow + throw on release) ──
  Bubble? hit(Offset p) {
    Bubble? best;
    var bestD = double.infinity;
    for (final b in bubbles) {
      final d = (Offset(b.x, b.y) - p).distance;
      if (d <= b.r + 8 && d < bestD) {
        best = b;
        bestD = d;
      }
    }
    return best;
  }

  void grab(Bubble b) {
    _held = b.body;
    b.body.setAwake(true);
  }

  void dragTo(Offset p) {
    final h = _held;
    if (h == null) return;
    final target = Vector2(p.dx / _scale, p.dy / _scale);
    // velocity that walks the body toward the finger → soft follow + collisions;
    // on release the body keeps this velocity (a natural throw).
    h.linearVelocity = (target - h.position) * 22.0;
    h.setAwake(true);
  }

  void release() => _held = null;
}
