import 'package:flutter/material.dart';

/// Shared height for both Tinder decks. Kept identical so the home
/// AnimatedSwitcher never resizes when switching 今日安排 ⇄ Reka Offer — unequal
/// deck heights made the Align reposition mid-transition (the card 抖动). Each deck
/// always reserves kCardHeight + 20 (the peek slot) so the height is constant even
/// with a single card. 392 fits the tallest card (offer: header + body + CTA + ✕/✓).
const double kCardHeight = 392.0;

/// Per-type visual identity for the B「潮汐」Tinder cards (今日安排 + Reka Offer).
/// kind → (platform emoji, base color). The base color is the source for the
/// header tint + the tag pill; the emoji is the big centered glyph rendered via
/// [Text] (NOT an image asset). Falls back to 💡 / 紫 when the server omits or
/// sends an unknown kind. Shared by both [reka_offer] and [next_action] so the
/// two screens read as one card presentation.
const Map<String, (String, Color)> kCardKindMeta = {
  'event': ('📅', Color(0xFF5B8DEF)),
  'todo': ('📋', Color(0xFF34B79A)),
  'habit_reminder': ('🔥', Color(0xFFF2994A)),
  'idea_synthesis': ('💡', Color(0xFFF2C94C)),
  'offer': ('🗂️', Color(0xFF7B61FF)),
  'overdue': ('⏰', Color(0xFFEB6B56)),
  'reminder': ('🔔', Color(0xFF56A8EB)),
  'consumption_summary': ('💰', Color(0xFF27AE60)),
  'briefing': ('🔍', Color(0xFF2D9CDB)),
  'quiz': ('📝', Color(0xFF9B51E0)),
  'rhythm_gap': ('✍️', Color(0xFFB08968)),
};

/// Default identity for an unknown / missing kind.
const (String, Color) kCardKindDefault = ('💡', Color(0xFF7B61FF));

/// (emoji, base) for [kind] — the per-type glyph + tint/pill source color.
(String, Color) cardKindMeta(String kind) =>
    kCardKindMeta[kind] ?? kCardKindDefault;

/// The shared 3-zone card frame for both home Tinder screens. One clipped,
/// bordered, shadowed rounded rectangle stacking:
///   [A] HEADER (height [headerHeight] ≈ 118): a soft per-type [base] tint
///       painted over the card surface, with the big [emoji] (Text, 74px)
///       centered + a small [tagLabel] pill (base color) at top-left (14,12).
///   [B] BODY: the per-screen content ([body]), padded, on the card surface.
///   [C] ACTION ROW: the in-card [actionRow] (circular buttons + hint), on the
///       card surface.
/// [dark] selects the header-tint alpha + surface gradient; the whole frame
/// reuses the offer card's decoration (gradient surface + border + lift).
class CardFrame extends StatelessWidget {
  const CardFrame({
    super.key,
    required this.emoji,
    required this.base,
    required this.tagLabel,
    required this.height,
    required this.body,
    required this.actionRow,
    required this.dark,
    required this.surfaceTop,
    required this.surfaceBottom,
    required this.border,
    this.headerHeight = 118,
    this.bodyPadding = const EdgeInsets.fromLTRB(16, 12, 16, 8),
  });

  /// The big centered glyph (platform emoji, rendered as Text).
  final String emoji;

  /// Per-type base color — the header-tint + tag-pill source.
  final Color base;

  /// Tag-pill label (white text on the base color), e.g. "日程" / "逾期".
  final String tagLabel;

  /// Total card height (the deck recomputes this for the 3-zone layout).
  final double height;

  /// Middle zone — the per-screen content.
  final Widget body;

  /// Bottom zone — circular end buttons + centered hint, on the surface bg.
  final Widget actionRow;

  /// Dark theme → a stronger header tint; also used for the shadow weight.
  final bool dark;

  /// Card surface gradient (reuse the palette's cardTop/cardBottom).
  final Color surfaceTop, surfaceBottom;

  /// Card resting border (may be faintly domain-tinted by the caller).
  final Color border;

  /// Header-zone height (≈118 in the mockup).
  final double headerHeight;

  /// Padding around [body].
  final EdgeInsets bodyPadding;

  @override
  Widget build(BuildContext context) {
    // Header tint = base painted over the surface at a soft alpha (themed).
    final tint = base.withValues(alpha: dark ? 0.30 : 0.42);
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surfaceTop, surfaceBottom],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [A] HEADER — soft tint bg, big emoji centered + tag pill top-left.
            SizedBox(
              height: headerHeight,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: tint)),
                  Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 74)),
                  ),
                  Positioned(
                    left: 14,
                    top: 12,
                    child: _TagPill(label: tagLabel, color: base),
                  ),
                ],
              ),
            ),
            // [B] BODY — per-screen content on the surface bg.
            Expanded(child: Padding(padding: bodyPadding, child: body)),
            // [C] ACTION ROW — circular end buttons + hint, on the surface bg.
            actionRow,
          ],
        ),
      ),
    );
  }
}

/// The header tag pill — a rounded chip in the per-type color (≈0.9 alpha) with
/// the kind label in white.
class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

/// A circular icon button for the in-card action row (the ✕/✓ on Reka Offer,
/// the ‹/› browse arrows on 今日安排). [tint] colors the fill (soft alpha),
/// border, and glyph; [neutral] buttons use the muted token instead. Tap fires
/// [onTap]; a drag still falls through to the card's pan gesture (this is a
/// child of that GestureDetector).
class CardActionButton extends StatelessWidget {
  const CardActionButton({
    super.key,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.size = 50,
  });

  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.16),
        border: Border.all(color: tint.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Icon(icon, size: 24, color: tint),
    ),
  );
}
