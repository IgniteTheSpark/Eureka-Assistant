import 'package:eureka/theme_v2/home/today_dot_field_controller.dart';
import 'package:eureka/theme_v2/home/today_dot_field_simulation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout builds an 8 px anchored field and reuses stable geometry', () {
    final simulation = TodayDotFieldSimulation();
    simulation.layout(const Size(411, 860));
    final firstNodes = simulation.nodes;
    final firstRevision = simulation.layoutRevision;

    simulation.layout(const Size(411, 860));

    expect(simulation.interval, 8);
    expect(simulation.nodes, same(firstNodes));
    expect(simulation.layoutRevision, firstRevision);
    expect(simulation.nodes, isNotEmpty);
  });

  test('drag deformation is local, speed-sensitive, and capped', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    const center = Offset(120, 420);
    final near = simulation.nodes.reduce(
      (a, b) =>
          (a.anchor - center).distance < (b.anchor - center).distance ? a : b,
    );
    final far = simulation.nodes.reduce(
      (a, b) =>
          (a.anchor - center).distance > (b.anchor - center).distance ? a : b,
    );

    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: .25,
      breathAmount: 0,
      reduceMotion: false,
    );
    final slow = (near.position - near.anchor).distance;
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: 1,
      breathAmount: 0,
      reduceMotion: false,
    );

    expect((near.position - near.anchor).distance, greaterThan(slow));
    expect(
      (near.position - near.anchor).distance,
      lessThanOrEqualTo(TodayDotFieldSimulation.maxDisplacement),
    );
    expect((far.position - far.anchor).distance, lessThan(.01));
  });

  test('idle breathing affects only the local field', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    const center = Offset(120, 420);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.idle,
      dragEngagement: 0,
      breathAmount: 1,
      reduceMotion: false,
    );

    expect(
      simulation.nodes.any(
        (node) =>
            (node.anchor - center).distance < 120 &&
            (node.position - node.anchor).distance > .005,
      ),
      isTrue,
    );
    expect(
      simulation.nodes
          .where((node) => (node.anchor - center).distance > 170)
          .every((node) => (node.position - node.anchor).distance < .01),
      isTrue,
    );
  });

  test('settling returns all dots to anchors without rebuilding nodes', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    final nodes = simulation.nodes;
    const center = Offset(120, 420);
    for (var i = 0; i < 12; i++) {
      simulation.step(
        1 / 60,
        rekaCenter: center,
        state: TodayRekaMotionState.dragging,
        dragEngagement: 1,
        breathAmount: 0,
        reduceMotion: false,
      );
    }

    for (var i = 0; i < 360 && !simulation.isAtRest; i++) {
      simulation.step(
        1 / 60,
        rekaCenter: center,
        state: TodayRekaMotionState.settling,
        dragEngagement: 0,
        breathAmount: 0,
        reduceMotion: false,
      );
    }

    expect(simulation.nodes, same(nodes));
    expect(simulation.isAtRest, isTrue);
    expect(
      simulation.nodes.every(
        (node) => (node.position - node.anchor).distance < .05,
      ),
      isTrue,
    );
  });

  test('reduce motion uses a small displacement and no spring tail', () {
    final simulation = TodayDotFieldSimulation()..layout(const Size(411, 860));
    const center = Offset(120, 420);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.dragging,
      dragEngagement: 1,
      breathAmount: 0,
      reduceMotion: true,
    );
    final maxOffset = simulation.nodes
        .map((node) => (node.position - node.anchor).distance)
        .reduce((a, b) => a > b ? a : b);
    simulation.step(
      1 / 60,
      rekaCenter: center,
      state: TodayRekaMotionState.idle,
      dragEngagement: 0,
      breathAmount: 0,
      reduceMotion: true,
    );

    expect(
      maxOffset,
      lessThanOrEqualTo(TodayDotFieldSimulation.reducedMotionDisplacement),
    );
    expect(simulation.isAtRest, isTrue);
  });
}
