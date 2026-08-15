import 'package:eureka/theme_v2/home/today_output_motion_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('motion plan clamps travel while preserving 280px per second', () {
    final short = todayOutputMotionPlan(
      source: Offset.zero,
      destination: const Offset(0, 100),
      reduceMotion: false,
    );
    final middle = todayOutputMotionPlan(
      source: Offset.zero,
      destination: const Offset(0, 448),
      reduceMotion: false,
    );
    final long = todayOutputMotionPlan(
      source: Offset.zero,
      destination: const Offset(0, 1000),
      reduceMotion: false,
    );

    expect(short.chargeDuration, const Duration(milliseconds: 300));
    expect(short.travelDuration, const Duration(milliseconds: 1200));
    expect(middle.travelDuration, const Duration(milliseconds: 1600));
    expect(long.travelDuration, const Duration(milliseconds: 2400));
    expect(middle.handoffRecoveryDuration, const Duration(milliseconds: 350));
    expect(middle.totalDuration, const Duration(milliseconds: 2250));
    expect(middle.chargeEnd, closeTo(300 / 2250, .0001));
    expect(middle.travelEnd, closeTo(1900 / 2250, .0001));
    expect(middle.recoveryStart, closeTo(2160 / 2250, .0001));
  });

  test('reduce motion keeps the existing short no-travel handoff', () {
    final plan = todayOutputMotionPlan(
      source: Offset.zero,
      destination: const Offset(0, 700),
      reduceMotion: true,
    );

    expect(plan.reduceMotion, isTrue);
    expect(plan.travelDuration, Duration.zero);
    expect(plan.totalDuration, const Duration(milliseconds: 140));
  });
}
