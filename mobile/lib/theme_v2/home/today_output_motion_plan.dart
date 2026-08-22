import 'package:flutter/material.dart';

import 'today_output_coordinator.dart';

@immutable
class TodayOutputMotionPlan {
  const TodayOutputMotionPlan({
    required this.distance,
    required this.reduceMotion,
    required this.chargeDuration,
    required this.travelDuration,
    required this.handoffDuration,
    required this.recoveryDuration,
  });

  final double distance;
  final bool reduceMotion;
  final Duration chargeDuration;
  final Duration travelDuration;
  final Duration handoffDuration;
  final Duration recoveryDuration;

  Duration get handoffRecoveryDuration => handoffDuration + recoveryDuration;
  Duration get totalDuration =>
      chargeDuration + travelDuration + handoffDuration + recoveryDuration;

  double get chargeEnd => _ratio(chargeDuration);
  double get travelEnd => _ratio(chargeDuration + travelDuration);
  double get recoveryStart =>
      _ratio(chargeDuration + travelDuration + handoffDuration);

  double _ratio(Duration elapsed) => totalDuration == Duration.zero
      ? 1
      : elapsed.inMicroseconds / totalDuration.inMicroseconds;
}

TodayOutputMotionPlan todayOutputMotionPlan({
  required Offset source,
  required Offset destination,
  required bool reduceMotion,
  TodayOutputKind kind = TodayOutputKind.signal,
}) {
  final distance = (destination - source).distance;
  if (reduceMotion) {
    return TodayOutputMotionPlan(
      distance: distance,
      reduceMotion: true,
      chargeDuration: Duration.zero,
      travelDuration: Duration.zero,
      handoffDuration: const Duration(milliseconds: 50),
      recoveryDuration: const Duration(milliseconds: 90),
    );
  }
  final travelMilliseconds = kind == TodayOutputKind.asset
      ? (distance / 360 * 1000).round().clamp(900, 1800)
      : (distance / 280 * 1000).round().clamp(1200, 2400);
  return TodayOutputMotionPlan(
    distance: distance,
    reduceMotion: false,
    chargeDuration: const Duration(milliseconds: 300),
    travelDuration: Duration(milliseconds: travelMilliseconds),
    handoffDuration: const Duration(milliseconds: 260),
    recoveryDuration: const Duration(milliseconds: 90),
  );
}
