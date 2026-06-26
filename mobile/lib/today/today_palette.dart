import 'package:flutter/material.dart';

import '../theme/app_theme.dart'; // context.eu

/// The today page's token set, switched on the app theme. Dark = the prototype
/// "atmosphere" (verbatim hifi). Light = warm, follows the app's eu light theme
/// (user's call) so the landing matches 日历 / 资产. Read once per build via
/// [TodayPalette.of] so it tracks the global light/dark toggle.
class TodayPalette {
  const TodayPalette({
    required this.dark,
    required this.atmosphereTop,
    required this.atmosphereBottom,
    required this.panelBg,
    required this.panelBorder,
    required this.title,
    required this.body,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentSoft,
    required this.cardTop,
    required this.cardBottom,
    required this.cardBorder,
    required this.shellTop,
    required this.shellBottom,
    required this.chartStroke,
    required this.inset,
    required this.onAccent,
  });

  final bool dark;
  final Color atmosphereTop, atmosphereBottom; // page radial
  final Color panelBg, panelBorder; // frosted panels
  final Color title, body, muted, faint; // text tiers
  final Color accent, accentSoft; // brand accents
  final Color cardTop, cardBottom, cardBorder; // Next Action focal card
  final Color shellTop, shellBottom; // stack shells behind the focal
  final Color chartStroke; // line between rose wedges / treemap cells
  final Color inset; // recessed sub-container (no-time list)
  final Color onAccent; // glyph/check drawn on an accent fill

  static TodayPalette of(BuildContext context) {
    final eu = context.eu;
    if (eu.brightness == Brightness.dark) return dark_;
    // Warm light set — derived from the app's eu light tokens.
    return TodayPalette(
      dark: false,
      atmosphereTop: eu.bg,
      atmosphereBottom: eu.bg,
      panelBg: eu.surfaceRaised.withValues(alpha: 0.82),
      panelBorder: eu.border,
      title: eu.textHi,
      body: eu.text,
      muted: eu.textMid,
      faint: eu.textLo,
      accent: eu.brand,
      accentSoft: eu.brand,
      cardTop: eu.surfaceRaised,
      cardBottom: eu.surface,
      cardBorder: eu.border,
      shellTop: eu.surface,
      shellBottom: eu.surfaceRaised,
      chartStroke: eu.bg,
      inset: eu.bg,
      onAccent: Colors.white,
    );
  }

  static const dark_ = TodayPalette(
    dark: true,
    atmosphereTop: Color(0xFF13203A),
    atmosphereBottom: Color(0xFF0B1220),
    panelBg: Color(0xA80F1728),
    panelBorder: Color(0x17FFFFFF),
    title: Color(0xFFE6EDF3),
    body: Color(0xD0FFFFFF),
    muted: Color(0x80FFFFFF),
    faint: Color(0x66FFFFFF),
    accent: Color(0xFF8AB4FF),
    accentSoft: Color(0xFFCFE0FF),
    cardTop: Color(0xF522304E),
    cardBottom: Color(0xF5162139),
    cardBorder: Color(0x26FFFFFF),
    shellTop: Color(0xF51E2C4A),
    shellBottom: Color(0xF5141E36),
    chartStroke: Color(0xFF0E1626),
    inset: Color(0xB3080E1A),
    onAccent: Color(0xFF0B1220),
  );
}
