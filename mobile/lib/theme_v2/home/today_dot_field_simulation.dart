import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'today_dot_field_controller.dart';

class TodayDotNode {
  TodayDotNode(this.anchor) : position = anchor;

  final Offset anchor;
  Offset position;
  Offset velocity = Offset.zero;
}

class TodayDotFieldSimulation {
  TodayDotFieldSimulation({this.interval = 8});

  static const dragRadius = 160.0;
  static const breathRadius = 120.0;
  static const maxDisplacement = 18.0;
  static const reducedMotionDisplacement = 4.0;

  final double interval;
  List<TodayDotNode> _nodes = <TodayDotNode>[];
  Size _size = Size.zero;
  int _layoutRevision = 0;

  List<TodayDotNode> get nodes => _nodes;
  int get layoutRevision => _layoutRevision;
  bool get isAtRest => _nodes.every(
    (node) =>
        (node.position - node.anchor).distance < .05 &&
        node.velocity.distance < .05,
  );

  void layout(Size size) {
    if (size == _size || size.isEmpty) return;
    _size = size;
    final half = interval / 2;
    final nodes = <TodayDotNode>[];
    for (var y = half; y < size.height; y += interval) {
      for (var x = half; x < size.width; x += interval) {
        nodes.add(TodayDotNode(Offset(x, y)));
      }
    }
    _nodes = nodes;
    _layoutRevision++;
  }

  void step(
    double dtSeconds, {
    required Offset rekaCenter,
    required TodayRekaMotionState state,
    required double dragEngagement,
    required double breathAmount,
    required bool reduceMotion,
  }) {
    final dt = dtSeconds.clamp(0.0, 1 / 20);
    for (final node in _nodes) {
      final delta = node.anchor - rekaCenter;
      final distance = delta.distance;
      final direction = distance == 0 ? const Offset(1, 0) : delta / distance;
      var target = node.anchor;

      if (state == TodayRekaMotionState.dragging && distance < dragRadius) {
        final falloff = _smooth(1 - distance / dragRadius);
        final cap = reduceMotion ? reducedMotionDisplacement : maxDisplacement;
        target += direction * (falloff * cap * dragEngagement);
      } else if (!reduceMotion &&
          state == TodayRekaMotionState.idle &&
          distance < breathRadius) {
        final falloff = _smooth(1 - distance / breathRadius);
        final angle = math.atan2(delta.dy, delta.dx);
        final asymmetric =
            1 + .08 * math.sin(angle * 3 + .6) + .05 * math.sin(angle * 5 - .8);
        target += direction * (falloff * 5.5 * breathAmount * asymmetric);
      }

      if (reduceMotion) {
        node.position = target;
        node.velocity = Offset.zero;
        continue;
      }

      final spring = state == TodayRekaMotionState.dragging ? 42.0 : 28.0;
      final damping = state == TodayRekaMotionState.dragging ? 14.0 : 11.0;
      final acceleration =
          (target - node.position) * spring - node.velocity * damping;
      node.velocity += acceleration * dt;
      node.position += node.velocity * dt;

      final offset = node.position - node.anchor;
      if (offset.distance > maxDisplacement) {
        node.position =
            node.anchor + offset / offset.distance * maxDisplacement;
        node.velocity *= .5;
      }
      if ((node.position - node.anchor).distance < .025 &&
          node.velocity.distance < .025) {
        node.position = node.anchor;
        node.velocity = Offset.zero;
      }
    }
  }

  static double _smooth(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}
