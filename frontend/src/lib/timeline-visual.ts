/**
 * timeline-visual — the per-item type signal shared by the calendar's 流
 * (ScheduleView) and 月 (MonthPane selected-day footer) surfaces.
 *
 * Both used to render a generic colored dot keyed off a 5-way subKind, so
 * notes / misc / qa / external_ref and every user-created skill collapsed to
 * the same neutral gray. Now each row shows the skill's own render_spec icon
 * (✅ 待办 · 💡 想法 · 💰 记账 · 🏃 跑步 · 🗂 其它 · 🔗 外部引用) plus a soft
 * accent-colored glow — matching the SkillCard / library icon language.
 */
import type { AccentColor } from "@/lib/render-spec";
import type { TimelineItem } from "@/lib/types";

/** Minimal structural shape of the skill-registry lookup (a Map satisfies it). */
interface SkillLike {
  render_spec?: { icon?: string; accent_color?: AccentColor } | null;
}
export interface SkillLookup {
  get(name: string): SkillLike | undefined;
}

// render_spec.accent_color → soft glow color behind the row icon. Mirrors the
// accent palette used by SkillCard / the library tiles.
const ACCENT_GLOW: Record<string, string> = {
  blue:    "rgba(138,180,255,0.50)",
  amber:   "rgba(245,201,119,0.50)",
  green:   "rgba(134,224,165,0.50)",
  red:     "rgba(255,141,161,0.50)",
  purple:  "rgba(196,168,255,0.50)",
  gray:    "rgba(212,219,230,0.32)",
  neutral: "rgba(212,219,230,0.32)",
};

/**
 * Resolve a timeline item to its display glyph + accent glow. Events get a
 * calendar glyph + purple; assets use their skill's icon + accent_color;
 * unknown / unregistered skills fall back to a neutral dot so a row is never
 * blank.
 */
export function timelineItemVisual(
  it: TimelineItem,
  bySkill: SkillLookup,
): { glyph: string; glow: string } {
  if (it.kind === "event") {
    return { glyph: "📅", glow: ACCENT_GLOW.purple };
  }
  const skill = it.skill_name ? bySkill.get(it.skill_name) : undefined;
  const glyph = skill?.render_spec?.icon || "•";
  const glow = ACCENT_GLOW[skill?.render_spec?.accent_color ?? "neutral"] ?? ACCENT_GLOW.neutral;
  return { glyph, glow };
}
