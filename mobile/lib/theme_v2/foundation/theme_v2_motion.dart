import 'package:flutter/material.dart';

enum ThemeV2MotionToken {
  fast(Duration(milliseconds: 160)),
  standard(Duration(milliseconds: 260)),
  fluid(Duration(milliseconds: 420));

  const ThemeV2MotionToken(this.rawDuration);

  final Duration rawDuration;
}

abstract final class ThemeV2Motion {
  static const Curve easeFluid = Cubic(0.22, 1, 0.36, 1);

  /// Resolves a motion token while respecting the operating-system preference.
  static Duration duration(BuildContext context, ThemeV2MotionToken token) {
    return MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : token.rawDuration;
  }
}
