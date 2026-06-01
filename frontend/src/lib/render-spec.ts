/**
 * lib/render-spec — TypeScript type definitions for UserSkill.render_spec.
 *
 * Mirrors Phase B §九.1 RenderSpec DSL. Kept in sync with:
 *   backend/db/seed.py        — seeded UserSkill.render_spec values
 *   backend/agents/flash_pipeline.py — _build_card_from_render_spec / _apply_format
 *
 * M1 will add the actual interpreter (renderCardFromSpec) that takes a
 * payload + spec and returns Card props. For M0 we just establish types so
 * downstream files have something to import.
 */

export type CardLayout = "horizontal" | "stacked" | "inline" | "compact";

export type AccentColor =
  | "blue"
  | "amber"
  | "green"
  | "red"
  | "purple"
  | "gray"
  | "neutral";

export type FieldFormat =
  | "text"
  | "relative_date"
  | "absolute_date"
  | "time"
  | "currency"
  | "duration"
  | "badge"
  | "truncate_30"
  | "truncate_40"
  | "truncate_60";

export type CardAction = "check" | "edit" | "delete" | "open";

export interface MetaFieldSpec {
  field: string;
  format?: FieldFormat;
  label?: string;
}

export interface RenderSpec {
  card_layout: CardLayout;
  icon: string;
  accent_color: AccentColor;
  primary_field: string;
  primary_format?: FieldFormat;
  secondary_field?: string;
  secondary_format?: FieldFormat;
  meta_fields?: MetaFieldSpec[];
  actions?: CardAction[];
  timeline_position?: { time_field?: string; fallback: "created_at" };
  calendar_render?: { date_field: string; time_field?: string };
  /**
   * @deprecated Units were dropped per May audit — users embed them in the
   * value when needed ("150 毫升" / "5 km"). Kept on the type so existing
   * skills with these fields still type-check; renderer ignores them.
   */
  field_units?:    Record<string, string>;
  /** @deprecated */ primary_label?:   string;
  /** @deprecated */ primary_unit?:    string;
  /** @deprecated */ secondary_label?: string;
  /** @deprecated */ secondary_unit?:  string;
}

/**
 * Card data produced from a (payload, render_spec) pair — what SkillCard
 * consumes. The interpreter (`buildCard` below) normalizes the heterogeneous
 * skill data into this single shape; SkillCard then renders it according to
 * `layout`.
 */
export interface CardData {
  cardType: string;        // skill machine name (todo / idea / notes / …)
  layout: CardLayout;
  icon: string;
  accentColor: AccentColor;
  title: string;
  subtitle: string;
  metaFields: Array<{ field: string; value: string; format?: FieldFormat }>;
  actions: CardAction[];
  assetId: string | null;
  /** OP3: when actions includes "check", derived done-state used by the
   *  SkillCard checkbox affordance. Undefined = no checkbox shown.
   *  True when payload.status === "done" or payload.done === true. */
  checkDone?: boolean;
}

/* ── Interpreter ──────────────────────────────────────────────────────────
 *
 * buildCard(payload, spec, fallback) — converts an asset's payload + its
 * UserSkill.render_spec into normalized CardData for the SkillCard renderer.
 *
 * `fallback` lets the caller pass the skill's display_name + machine_name
 * for sensible defaults when primary_field resolves to empty.
 *
 * Mirrors backend's _build_card_from_render_spec in agents/flash_pipeline.py.
 * Stays sync (no DB); takes the resolved spec in.
 */

import { applyFormat } from "./format";

export interface BuildCardInput {
  payload: Record<string, unknown>;
  spec: RenderSpec | null;
  assetId: string | null;
  cardType: string;        // usually = skill machine name
  displayName: string;     // for title fallback when payload[primary_field] is empty
}

const DEFAULT_LAYOUT: CardLayout = "horizontal";
const DEFAULT_ACCENT: AccentColor = "gray";
const DEFAULT_ICON = "•";

// Friendly labels for external_ref/task `external_system` values. The
// in-flight sentinel ("pending") and unknown map to "" so the subtitle is
// blank while the status badge ("待处理"/"同步中") carries the state.
const EXTERNAL_SYSTEM_LABEL: Record<string, string> = {
  pending:           "",
  unknown:           "",
  notion:            "Notion",
  google_calendar:   "Google 日历",
  dingtalk:          "钉钉",
  dingtalk_calendar: "钉钉日历",
  dingtalk_todo:     "钉钉待办",
  dingtalk_notes:    "钉钉文档",
};

// external_system → card icon for external_ref / task cards. "mcp:*" sentinels
// render the real brand logo (see McpBrandMark); others are emoji stand-ins;
// "pending" stays ⏳ (in flight). Unknown keeps the spec's default (🔗).
const EXTERNAL_SYSTEM_ICON: Record<string, string> = {
  pending:           "⏳",
  dingtalk:          "mcp:dingtalk",
  dingtalk_calendar: "mcp:dingtalk",
  dingtalk_todo:     "mcp:dingtalk",
  dingtalk_notes:    "mcp:dingtalk",
  notion:            "📝",
  google_calendar:   "📅",
};

// Decoration (label prefix, unit suffix) was removed in two passes per the
// May audit. Final rule: the card title/subtitle = the field's value as-is.
// Users embed units in the value when they need them ("150 毫升", "5 km"),
// which also makes multi-modal skills (宝宝养育: amount in 毫升 OR 克 OR
// 小时 depending on activity) actually work — one schema, no per-asset
// unit-lookup gymnastics.

export function buildCard(input: BuildCardInput): CardData {
  const { payload, spec, assetId, cardType, displayName } = input;

  // Defensive: render_spec can be null (qa-skill, system skills) or partial.
  if (!spec) {
    return {
      cardType,
      layout: DEFAULT_LAYOUT,
      icon: DEFAULT_ICON,
      accentColor: DEFAULT_ACCENT,
      title: displayName || cardType,
      subtitle: "",
      metaFields: [],
      actions: [],
      assetId,
    };
  }

  const primaryRaw = spec.primary_field ? payload[spec.primary_field] : undefined;
  const secondaryRaw = spec.secondary_field ? payload[spec.secondary_field] : undefined;

  // Title / subtitle: the raw payload value with format applied (date,
  // currency, ...). No unit, no label — values speak for themselves. Falls
  // back to displayName / cardType when the primary field is empty so the
  // card never reads as blank.
  const primaryValue = applyFormat(primaryRaw, spec.primary_format);
  const title = primaryValue || displayName || cardType;
  let subtitle = applyFormat(secondaryRaw, spec.secondary_format);

  // external_ref / task cards use `external_system` as their subtitle. Raw it
  // reads as "pending" (the in-flight sentinel) or a lowercase machine name
  // ("google_calendar"). Localize: blank during pending/unknown so the status
  // badge carries the state, friendly names once the system is known.
  if (spec.secondary_field === "external_system" && typeof secondaryRaw === "string") {
    subtitle = EXTERNAL_SYSTEM_LABEL[secondaryRaw] ?? subtitle;
  }

  const metaFields = (spec.meta_fields ?? [])
    .map((mf) => {
      const raw = payload[mf.field];
      const value = applyFormat(raw, mf.format);
      return value ? { field: mf.field, value, format: mf.format } : null;
    })
    .filter((m): m is NonNullable<typeof m> => m !== null);

  // OP3: derive checkDone from payload when the spec exposes a "check"
  // action. Supports both shapes (todo uses status enum; some other skills
  // might add a simple boolean `done`).
  //
  // Defensive backstop for #6 (May audit): early design-agent runs sometimes
  // tagged measurement skills (跑步记录, etc.) with actions=["check"] even
  // though the payload has no status/done concept. Without this check the
  // card grew a meaningless checkbox stuck in unchecked state forever.
  // Now: only honor "check" when the payload actually carries one of the
  // state fields — keeps the phantom checkbox off for legacy bad specs.
  const actions = spec.actions ?? [];
  let checkDone: boolean | undefined;
  if (actions.includes("check")) {
    const hasStatus = Object.prototype.hasOwnProperty.call(payload, "status");
    const hasDone   = Object.prototype.hasOwnProperty.call(payload, "done");
    if (hasStatus || hasDone) {
      checkDone = payload.status === "done" || payload.done === true;
    }
  }

  // external_ref / task cards: icon reflects the MCP the item hit, once known
  // (pending → ⏳, dingtalk → real brand mark, …). Falls back to the spec icon.
  let icon = spec.icon ?? DEFAULT_ICON;
  if (cardType === "external_ref" || cardType === "task") {
    const sysRaw = payload["external_system"];
    const mapped = typeof sysRaw === "string" ? EXTERNAL_SYSTEM_ICON[sysRaw] : undefined;
    if (mapped) icon = mapped;
  }

  return {
    cardType,
    layout: spec.card_layout ?? DEFAULT_LAYOUT,
    icon,
    accentColor: spec.accent_color ?? DEFAULT_ACCENT,
    title,
    subtitle,
    metaFields,
    actions,
    assetId,
    checkDone,
  };
}
