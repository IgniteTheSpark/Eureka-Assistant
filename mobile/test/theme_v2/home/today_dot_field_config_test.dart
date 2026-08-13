import 'package:eureka/theme_v2/home/today_dot_field_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults expose every React Bits Dot Field parameter', () {
    const config = TodayDotFieldConfig();

    expect(config.dotRadius, 1.5);
    expect(config.dotSpacing, 14);
    expect(config.cursorRadius, 54);
    expect(config.cursorForce, .1);
    expect(config.bulgeOnly, isTrue);
    expect(config.bulgeStrength, 67);
    expect(config.glowRadius, 150);
    expect(config.sparkle, isFalse);
    expect(config.waveAmplitude, 0);
    expect(config.gradientFrom, const Color(0xA674837A));
    expect(config.gradientTo, const Color(0x8F607269));
    expect(config.glowColor, Colors.black);
  });

  test('copyWith changes every field without changing the source', () {
    const source = TodayDotFieldConfig();
    final changed = source.copyWith(
      dotRadius: 2,
      dotSpacing: 12,
      cursorRadius: 60,
      cursorForce: .25,
      bulgeOnly: false,
      bulgeStrength: 80,
      glowRadius: 170,
      sparkle: true,
      waveAmplitude: 2,
      gradientFrom: Colors.white,
      gradientTo: Colors.grey,
      glowColor: Colors.blue,
    );

    expect(changed.dotRadius, 2);
    expect(changed.dotSpacing, 12);
    expect(changed.cursorRadius, 60);
    expect(changed.cursorForce, .25);
    expect(changed.bulgeOnly, isFalse);
    expect(changed.bulgeStrength, 80);
    expect(changed.glowRadius, 170);
    expect(changed.sparkle, isTrue);
    expect(changed.waveAmplitude, 2);
    expect(changed.gradientFrom, Colors.white);
    expect(changed.gradientTo, Colors.grey);
    expect(changed.glowColor, Colors.blue);
    expect(source, const TodayDotFieldConfig());
  });

  test('invalid geometric values assert in debug builds', () {
    expect(() => TodayDotFieldConfig(dotRadius: 0), throwsAssertionError);
    expect(() => TodayDotFieldConfig(dotSpacing: 0), throwsAssertionError);
    expect(() => TodayDotFieldConfig(cursorRadius: 0), throwsAssertionError);
    expect(() => TodayDotFieldConfig(glowRadius: 40), throwsAssertionError);
    expect(() => TodayDotFieldConfig(cursorForce: -1), throwsAssertionError);
    expect(() => TodayDotFieldConfig(bulgeStrength: -1), throwsAssertionError);
    expect(() => TodayDotFieldConfig(waveAmplitude: -1), throwsAssertionError);
  });
}
