import 'package:flutter/material.dart';

/// Visual and motion parameters for the Today dot field.
///
/// Names mirror the React Bits Dot Field API so design tuning can be
/// transferred without translating between two parameter vocabularies.
@immutable
class TodayDotFieldConfig {
  const TodayDotFieldConfig({
    this.dotRadius = 1.5,
    this.dotSpacing = 14,
    this.cursorRadius = 54,
    this.cursorForce = .1,
    this.bulgeOnly = true,
    this.bulgeStrength = 67,
    this.glowRadius = 150,
    this.sparkle = false,
    this.waveAmplitude = 0,
    this.gradientFrom = const Color(0xA674837A),
    this.gradientTo = const Color(0x8F607269),
    this.glowColor = Colors.black,
  }) : assert(dotRadius > 0),
       assert(dotSpacing > 0),
       assert(cursorRadius > 0),
       assert(glowRadius >= cursorRadius),
       assert(cursorForce >= 0),
       assert(bulgeStrength >= 0),
       assert(waveAmplitude >= 0);

  /// Radius of each individual dot in logical pixels.
  final double dotRadius;

  /// Center-to-center spacing between dots in logical pixels.
  final double dotSpacing;

  /// Radius of the visible white Reka rise in this mobile adaptation.
  final double cursorRadius;

  /// Force applied to nearby dots when [bulgeOnly] is false.
  final double cursorForce;

  /// Whether dots use a bounded radial bulge instead of pushed-dot physics.
  final bool bulgeOnly;

  /// Strength of the local bulge around Reka.
  final double bulgeStrength;

  /// Radius of the radial outer glow around Reka.
  final double glowRadius;

  /// Whether a deterministic three percent subset of dots enlarges.
  final bool sparkle;

  /// Amplitude of the field-wide wave displacement in logical pixels.
  final double waveAmplitude;

  /// Starting color of the diagonal dot gradient.
  final Color gradientFrom;

  /// Ending color of the diagonal dot gradient.
  final Color gradientTo;

  /// Color of the radial outer glow around Reka.
  final Color glowColor;

  TodayDotFieldConfig copyWith({
    double? dotRadius,
    double? dotSpacing,
    double? cursorRadius,
    double? cursorForce,
    bool? bulgeOnly,
    double? bulgeStrength,
    double? glowRadius,
    bool? sparkle,
    double? waveAmplitude,
    Color? gradientFrom,
    Color? gradientTo,
    Color? glowColor,
  }) => TodayDotFieldConfig(
    dotRadius: dotRadius ?? this.dotRadius,
    dotSpacing: dotSpacing ?? this.dotSpacing,
    cursorRadius: cursorRadius ?? this.cursorRadius,
    cursorForce: cursorForce ?? this.cursorForce,
    bulgeOnly: bulgeOnly ?? this.bulgeOnly,
    bulgeStrength: bulgeStrength ?? this.bulgeStrength,
    glowRadius: glowRadius ?? this.glowRadius,
    sparkle: sparkle ?? this.sparkle,
    waveAmplitude: waveAmplitude ?? this.waveAmplitude,
    gradientFrom: gradientFrom ?? this.gradientFrom,
    gradientTo: gradientTo ?? this.gradientTo,
    glowColor: glowColor ?? this.glowColor,
  );
}
