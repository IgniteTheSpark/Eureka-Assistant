import 'package:flutter/material.dart';

/// Semantic Theme V2 colors shared by both brightness modes.
///
/// Widgets use this single extension type and let [ThemeData] provide either
/// [light] or [dark]. Color values must not be duplicated in component code.
@immutable
class ThemeV2Tokens extends ThemeExtension<ThemeV2Tokens> {
  const ThemeV2Tokens({
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.border,
    required this.accent,
    required this.accentSoft,
    required this.critical,
    required this.watermark,
  });

  final Color background;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color border;
  final Color accent;
  final Color accentSoft;
  final Color critical;
  final Color watermark;

  static const light = ThemeV2Tokens(
    background: Color(0xFFF7F9FC),
    surface: Color(0xFFFFFFFF),
    foreground: Color(0xFF101319),
    muted: Color(0xFF6D7480),
    border: Color(0xFFD9E0E8),
    accent: Color(0xFF25B6D6),
    accentSoft: Color(0xFFE9F8FC),
    critical: Color(0xFFD23A57),
    watermark: Color(0x09101319),
  );

  static const dark = ThemeV2Tokens(
    background: Color(0xFF0B0D12),
    surface: Color(0xFF121620),
    foreground: Color(0xFFF3F5FA),
    muted: Color(0xFF8991A0),
    border: Color(0xFF29303D),
    accent: Color(0xFF8A82FF),
    accentSoft: Color(0xFF1A1D35),
    critical: Color(0xFFFF5F7B),
    watermark: Color(0x09FFFFFF),
  );

  static ThemeV2Tokens forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static ThemeV2Tokens of(BuildContext context) =>
      Theme.of(context).extension<ThemeV2Tokens>()!;

  @override
  ThemeV2Tokens copyWith({
    Color? background,
    Color? surface,
    Color? foreground,
    Color? muted,
    Color? border,
    Color? accent,
    Color? accentSoft,
    Color? critical,
    Color? watermark,
  }) {
    return ThemeV2Tokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      foreground: foreground ?? this.foreground,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      critical: critical ?? this.critical,
      watermark: watermark ?? this.watermark,
    );
  }

  @override
  ThemeV2Tokens lerp(ThemeExtension<ThemeV2Tokens>? other, double t) {
    if (other is! ThemeV2Tokens) return this;
    return ThemeV2Tokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
      watermark: Color.lerp(watermark, other.watermark, t)!,
    );
  }
}

abstract final class ThemeV2Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class ThemeV2Radii {
  static const double sm = 7;
  static const double md = 10;
  static const double lg = 14;
  static const double pill = 999;
}

abstract final class ThemeV2Sizes {
  static const double minTouchTarget = 44;
}
