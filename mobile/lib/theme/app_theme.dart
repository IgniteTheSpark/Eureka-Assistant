import 'package:flutter/material.dart';

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

  return ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    scaffoldBackgroundColor: c.bg,
    colorScheme: scheme,
    extensions: [EurekaTheme(c)],
    textTheme: Typography.material2021(platform: TargetPlatform.iOS)
        .black
        .apply(
          bodyColor: c.text,
          displayColor: c.textHi,
        ),
  );
}

/// Ergonomic access: `context.eu.brand`, `context.eu.textHi`, …
extension EurekaThemeX on BuildContext {
  EurekaColors get eu => Theme.of(this).extension<EurekaTheme>()!.colors;
}
