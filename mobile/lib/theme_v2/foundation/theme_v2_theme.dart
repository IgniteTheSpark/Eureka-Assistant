import 'package:flutter/material.dart';

import 'theme_v2_tokens.dart';
import 'theme_v2_typography.dart';

ThemeData buildThemeV2Theme(Brightness brightness) {
  final tokens = ThemeV2Tokens.forBrightness(brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: brightness,
      ).copyWith(
        primary: tokens.accent,
        onPrimary: brightness == Brightness.dark
            ? const Color(0xFF101319)
            : const Color(0xFFFFFFFF),
        secondary: tokens.accent,
        surface: tokens.surface,
        onSurface: tokens.foreground,
        error: tokens.critical,
        outline: tokens.border,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: tokens.background,
    colorScheme: scheme,
    fontFamily: ThemeV2Typography.primaryFont,
    textTheme: ThemeV2Typography.textTheme(
      brightness: brightness,
      foreground: tokens.foreground,
    ),
    extensions: [tokens],
  );
}

extension ThemeV2BuildContext on BuildContext {
  ThemeV2Tokens get themeV2 => ThemeV2Tokens.of(this);
}
