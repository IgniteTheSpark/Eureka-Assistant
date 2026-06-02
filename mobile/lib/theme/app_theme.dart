import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'eureka_colors.dart';

/// ThemeExtension that carries the full Eureka palette so widgets can read any
/// token via `Theme.of(context).extension<EurekaTheme>()!.colors` (or the
/// `context.eu` helper below), beyond what Material's ColorScheme exposes.
@immutable
class EurekaTheme extends ThemeExtension<EurekaTheme> {
  final EurekaColors colors;
  const EurekaTheme(this.colors);

  @override
  EurekaTheme copyWith({EurekaColors? colors}) => EurekaTheme(colors ?? this.colors);

  @override
  EurekaTheme lerp(ThemeExtension<EurekaTheme>? other, double t) {
    // Palette swaps are instant (no cross-theme tweening needed).
    return (other is EurekaTheme) ? other : this;
  }
}

/// Build a Material ThemeData from an Eureka palette.
ThemeData buildEurekaTheme(EurekaColors c) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.brand,
    brightness: c.brightness,
  ).copyWith(
    primary: c.brand,
    secondary: c.accentPurple,
    surface: c.surface,
    onSurface: c.text,
    error: c.accentRed,
  );

  final baseTypo = c.brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  final textTheme = GoogleFonts.manropeTextTheme(baseTypo)
      .apply(bodyColor: c.text, displayColor: c.textHi);

  return ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    scaffoldBackgroundColor: c.bg,
    colorScheme: scheme,
    extensions: [EurekaTheme(c)],
    fontFamily: GoogleFonts.manrope().fontFamily,
    textTheme: textTheme,
  );
}

/// JetBrains Mono style — for times, weekday caps, counts (matches the web's
/// mono usage). Pass only what you need; the rest inherits.
TextStyle euMono({
  double? fontSize,
  Color? color,
  FontWeight? fontWeight,
  double? letterSpacing,
}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );

/// A brand-glow heading style (Manrope 700 + soft brand shadow), mirroring the
/// web's `font-display` brand headings.
TextStyle euHeading(EurekaColors c, {double fontSize = 22}) => GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: c.brand,
      shadows: [Shadow(color: c.brand.withValues(alpha: 0.35), blurRadius: 18)],
    );

/// Ergonomic access: `context.eu.brand`, `context.eu.textHi`, …
extension EurekaThemeX on BuildContext {
  EurekaColors get eu => Theme.of(this).extension<EurekaTheme>()!.colors;
}
