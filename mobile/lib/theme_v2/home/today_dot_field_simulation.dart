import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'today_dot_field_controller.dart';
import 'today_dot_field_config.dart';

class TodayDotNode {
  TodayDotNode(this.anchor) : position = anchor;

  final Offset anchor;
  Offset position;
  Offset velocity = Offset.zero;
}

class TodayDotFieldSimulation {
  TodayDotFieldSimulation({this.config = const TodayDotFieldConfig()});

  static const maxDisplacement = 18.0;
  static const reducedMotionDisplacement = 4.0;

  final TodayDotFieldConfig config;
  List<TodayDotNode> _nodes = <TodayDotNode>[];
  Size _size = Size.zero;
  int _layoutRevision = 0;
  int _paintRevision = 0;

  List<TodayDotNode> get nodes => _nodes;
  int get layoutRevision => _layoutRevision;
  int get paintRevision => _paintRevision;
  bool get isAtRest => _nodes.every(
    (node) =>
        (node.position - node.anchor).distance < .05 &&
        node.velocity.distance < .05,
  );

  void layout(Size size) {
    if (size == _size || size.isEmpty) return;
    _size = size;
    final interval = config.dotSpacing;
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
    required double fieldPhase,
    required bool reduceMotion,
  }) {
    final dt = dtSeconds.clamp(0.0, 1 / 20);
    for (final node in _nodes) {
      final delta = node.anchor - rekaCenter;
      final distance = delta.distance;
      final direction = distance == 0 ? const Offset(1, 0) : delta / distance;
      var target = node.anchor;

      if (distance < config.glowRadius &&
          state != TodayRekaMotionState.settling) {
        final falloff = _smooth(1 - distance / config.glowRadius);
        final strength = config.bulgeStrength / 67;
        final motionAmount = state == TodayRekaMotionState.dragging
            ? dragEngagement
            : breathAmount;
        final reducedScale = reduceMotion ? .22 : 1.0;
        final angle = math.atan2(delta.dy, delta.dx);
        final asymmetric =
            1 + .08 * math.sin(angle * 3 + .6) + .05 * math.sin(angle * 5 - .8);
        final displacement =
            12 * strength * motionAmount * falloff * asymmetric * reducedScale;

        if (config.bulgeOnly) {
          target += direction * displacement;
        } else {
          target += direction * displacement * .35;
          if (!reduceMotion) {
            node.velocity +=
                direction *
                (config.cursorForce * 180 * falloff * dragEngagement * dt);
          }
        }
      }

      if (!reduceMotion && config.waveAmplitude > 0) {
        final wave = math.sin(
          node.anchor.dx * .035 +
              node.anchor.dy * .021 +
              fieldPhase * math.pi * 2,
        );
        target += Offset(0, wave * config.waveAmplitude);
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
      final displacementCap = reduceMotion
          ? reducedMotionDisplacement
          : maxDisplacement;
      if (offset.distance > displacementCap) {
        node.position =
            node.anchor + offset / offset.distance * displacementCap;
        node.velocity *= .5;
      }
      if ((node.position - node.anchor).distance < .025 &&
          node.velocity.distance < .025) {
        node.position = node.anchor;
        node.velocity = Offset.zero;
      }
    }
    _paintRevision++;
  }

  bool isSparkle(int index) => config.sparkle && ((index * 37 + 17) % 100) < 3;

  static double _smooth(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}
