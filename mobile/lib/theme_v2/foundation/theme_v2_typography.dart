import 'package:flutter/material.dart';

abstract final class ThemeV2Typography {
  static const primaryFont = 'Geist';
  static const monoFont = 'Geist Mono';
  static const fallbackFonts = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static TextTheme textTheme({
    required Brightness brightness,
    required Color foreground,
  }) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    return base.apply(
      fontFamily: primaryFont,
      fontFamilyFallback: fallbackFonts,
      bodyColor: foreground,
      displayColor: foreground,
    );
  }

  static TextStyle mono({
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: fallbackFonts,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}
