import 'package:flutter/material.dart';

/// Eureka color palette, ported from `frontend/src/styles/tokens.css`.
///
/// Two themes mirror the web app: `dark` == `.theme-atmosphere` (the default),
/// `light` == `.theme-light` (warm day mode). Translucent-over-bg web surfaces
/// are flattened to solid approximations here.
@immutable
class EurekaColors {
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color rule;
  final Color textHi;
  final Color text;
  final Color textMid;
  final Color textLo;
  final Color brand;
  final Color brandHi;
  final Color accentBlue;
  final Color accentAmber;
  final Color accentGreen;
  final Color accentRed;
  final Color accentPurple;
  // §5.1 accent palette is 8 slots — gray/neutral/cyan complete the set the web
  // tailwind config dropped (spec §5.5.4 says to backfill cyan on Flutter).
  final Color accentGray;
  final Color accentNeutral;
  final Color accentCyan;

  const EurekaColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.rule,
    required this.textHi,
    required this.text,
    required this.textMid,
    required this.textLo,
    required this.brand,
    required this.brandHi,
    required this.accentBlue,
    required this.accentAmber,
    required this.accentGreen,
    required this.accentRed,
    required this.accentPurple,
    required this.accentGray,
    required this.accentNeutral,
    required this.accentCyan,
  });

  /// `.theme-atmosphere` — the default dark theme.
  static const dark = EurekaColors(
    brightness: Brightness.dark,
    bg: Color(0xFF0B1220),
    surface: Color(0xFF0E1422),
    surfaceRaised: Color(0xFF121A2B),
    border: Color(0x12FFFFFF), // rgba(255,255,255,0.07)
    rule: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    textHi: Color(0xFFF4F7FB),
    text: Color(0xFFD4DBE6),
    textMid: Color(0xFF9AA6B8),
    textLo: Color(0xFF6C7689),
    brand: Color(0xFF6F9EFF),
    brandHi: Color(0xFFA4C2FF),
    accentBlue: Color(0xFF8AB4FF),
    accentAmber: Color(0xFFF5C977),
    accentGreen: Color(0xFF86E0A5),
    accentRed: Color(0xFFF7768E),
    accentPurple: Color(0xFFC4A8FF),
    accentGray: Color(0xFFA3AEC0),
    accentNeutral: Color(0xFFC8CED8),
    accentCyan: Color(0xFF67D9E8),
  );

  /// `.theme-light` — warm off-white day mode.
  static const light = EurekaColors(
    brightness: Brightness.light,
    // P2 表层深度:bg 比 surfaceRaised 暗一档(原 F4F2EC 几乎与 raised 同明度 → 卡片浮不起来)。
    bg: Color(0xFFEFEBE1),
    surface: Color(0xFFEAE7DE),
    surfaceRaised: Color(0xFFFCFBF8),
    border: Color(0x1F141812), // rgba(20,18,12,0.12)
    rule: Color(0x14141812), // rgba(20,18,12,0.08)
    textHi: Color(0xFF1B1D22),
    text: Color(0xFF34373F),
    textMid: Color(0xFF5F636E),
    textLo: Color(0xFF8B8F9A),
    brand: Color(0xFF3F6FE0),
    brandHi: Color(0xFF2B59C8),
    accentBlue: Color(0xFF2F63D6),
    accentAmber: Color(0xFFB07414),
    accentGreen: Color(0xFF2F9356),
    accentRed: Color(0xFFD23A57),
    accentPurple: Color(0xFF7A54D4),
    accentGray: Color(0xFF6B7280),
    accentNeutral: Color(0xFF52555E),
    accentCyan: Color(0xFF0E8AA0),
  );
}
