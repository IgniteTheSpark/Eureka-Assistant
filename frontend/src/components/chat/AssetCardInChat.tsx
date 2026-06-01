import { EventCard } from "@/components/calendar/EventCard";
import { SkillCard } from "@/components/skill/SkillCard";
import { useAssets } from "@/hooks/useAssets";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useToggleTodo } from "@/hooks/useToggleTodo";
import { buildCard } from "@/lib/render-spec";
import type { AccentColor, CardAction, CardData, FieldFormat } from "@/lib/render-spec";

/**
 * AssetCardInChat — render a card that came inline in a chat agent message.
 *
 * Two ways the card can arrive:
 *  1. Live chat tool_result (`tool_create_asset` → response.payload)
 *  2. History replay (Message.cards JSON from the messages table — flash also
 *     writes here)
 *
 * Both surface as a `{user_skill_name?, payload, asset_id?, ...}` dict.
 * We look up the matching UserSkill to get its render_spec, then hand to
 * SkillCard with the inline layout so the card sits cleanly inside the
 * chat bubble flow.
 *
 * Special-case skills (event / task / external_ref) fall back to sensible
 * defaults when no render_spec is registered for them.
 */

interface AssetCardInChatProps {
  /** Either the raw tool_result.response or a Message.cards[i] entry */
  data: Record<string, unknown>;
  /** Opens the detail drawer. `sourceSessionId` lets the drawer show the
   *  real provenance (闪念 / Agent) when the card resolves to a live asset —
   *  chat cards otherwise carry only the prebuilt card dict + no session. */
  onOpen?: (cardData: CardData, payload: Record<string, unknown>, sourceSessionId?: string | null) => void;
}

export function AssetCardInChat({ data, onOpen }: AssetCardInChatProps) {
  // Fall back to "task" when a card dict carries task_id but no card_type —
  // covers history replay where the stored card wasn't tagged (live cards get
  // tagged by tagByIdField). Without this the task card renders as「资产」.
  const skillName = pickString(data, ["user_skill_name", "card_type", "skill_name"]) ?? (data.task_id ? "task" : null);
  const assetId   = pickString(data, ["asset_id", "id"]);

  // Async-task lifecycle cards (third-party MCP sync via task-skill) read their
  // LIVE status from the assets cache instead of the frozen card captured when
  // the agent message streamed. The background task finishes seconds later and
  // fires a `task_done` notification → /api/assets revalidates → this card
  // flips pending → done (⏳ → 🔗 / 已同步) with no reload.
  if ((skillName === "task" || skillName === "external_ref") && assetId) {
    return <LiveTaskCard assetId={assetId} frozen={data} onOpen={onOpen} />;
  }
  return <AssetCardBody data={data} onOpen={onOpen} />;
}

/** Lifecycle-card wrapper: overlays the live asset payload onto the frozen
 *  chat card so async MCP tasks visibly complete in place. */
function LiveTaskCard({
  assetId, frozen, onOpen,
}: {
  assetId: string;
  frozen: Record<string, unknown>;
  onOpen?: AssetCardInChatProps["onOpen"];
}) {
  const { assets } = useAssets();
  const live = assets.find((a) => a.id === assetId);
  const data = live
    ? { ...frozen, user_skill_name: live.user_skill_name, asset_id: assetId, payload: live.payload }
    : frozen;
  return <AssetCardBody data={data} onOpen={onOpen} />;
}

function AssetCardBody({ data, onOpen }: AssetCardInChatProps) {
  const { bySkill } = useSkillRegistry();
  const toggleTodo = useToggleTodo();
  const { assets } = useAssets();

  const skillName = pickString(data, ["user_skill_name", "card_type", "skill_name"]) ?? (data.task_id ? "task" : null);
  const payload   = pickObject(data, "payload") ?? data;
  const assetId   = pickString(data, ["asset_id", "id"]);
  const eventId   = pickString(data, ["event_id"]);
  const taskId    = pickString(data, ["task_id"]);

  // Resolve the live asset (if this card maps to one) so the detail drawer
  // gets the REAL payload + its source session — not the truncated card dict
  // a flash/agent card carries inline. Falls back to the inline payload.
  const live        = assetId ? assets.find((a) => a.id === assetId) : undefined;
  const openPayload = live?.payload ?? payload;
  const openSession = live?.session_id ?? null;

  // M4-bugfix-2: events route through the unified EventCard so chat /
  // library / day-detail show identical surfaces. The tool_create_event
  // response carries title / start_at / end_at / all_day / location at
  // the top level.
  if (skillName === "event" && (eventId || data.title)) {
    return (
      <EventCard
        event={{
          event_id: eventId ?? undefined,
          title:    String(data.title ?? ""),
          start_at: String(data.start_at ?? ""),
          end_at:   typeof data.end_at === "string" ? data.end_at : null,
          all_day:  Boolean(data.all_day),
          location: typeof data.location === "string" ? data.location : null,
        }}
        onClick={onOpen ? () => onOpen(buildEventCardData(data), openPayload, openSession) : undefined}
      />
    );
  }

  // Flash pipeline emits a PRE-BUILT card: title/subtitle/icon/accent are
  // already computed server-side (via the skill's render_spec), shaped
  // {card_type, title, subtitle, icon, accent_color, meta_fields, actions,
  // asset_id} with NO `payload`. Detect that and render it directly —
  // otherwise buildCard re-derives the title from the spec's primary_field
  // ("content"/etc.) which isn't in this shape, and falls back to the
  // display_name ("待办"). The chat tool_result path keeps `payload`, so it
  // still flows through buildCard below.
  const prebuilt =
    pickObject(data, "payload") == null &&
    typeof data.title === "string" &&
    typeof data.card_type === "string";
  if (prebuilt) {
    const actions = Array.isArray(data.actions) ? (data.actions as CardAction[]) : [];
    const cardData: CardData = {
      cardType:    String(data.card_type),
      layout:      "horizontal",
      icon:        typeof data.icon === "string" ? data.icon : "•",
      accentColor: (typeof data.accent_color === "string" ? data.accent_color : "neutral") as AccentColor,
      title:       String(data.title),
      subtitle:    typeof data.subtitle === "string" ? data.subtitle : "",
      metaFields:  Array.isArray(data.meta_fields)
        ? (data.meta_fields as Array<Record<string, unknown>>)
            .map((m) => ({ field: String(m.field ?? ""), value: String(m.value ?? ""), format: m.format as FieldFormat | undefined }))
            .filter((m) => m.value)
        : [],
      actions,
      assetId:     assetId,
      // Fresh flash cards are unchecked; show the box when the skill is checkable.
      checkDone:   actions.includes("check") ? false : undefined,
    };
    return (
      <SkillCard
        data={cardData}
        layoutOverride="horizontal"
        onClick={onOpen ? () => onOpen(cardData, openPayload, openSession) : undefined}
        onToggleCheck={cardData.checkDone !== undefined && assetId
          ? (next) => toggleTodo(assetId, next)
          : undefined}
      />
    );
  }

  const skill = skillName ? bySkill.get(skillName) : undefined;

  // Pick a render spec — prefer the registered one, else synthesize for
  // first-class entity / task cards based on conventions in M1.
  const spec = skill?.render_spec ?? synthesizeSpec(skillName, data);

  const cardData = buildCard({
    payload,
    spec,
    assetId: assetId ?? eventId ?? taskId ?? null,
    cardType: skillName ?? "asset",
    displayName: skill?.display_name ?? skillName ?? "资产",
  });

  return (
    <SkillCard
      data={cardData}
      // Chat-embedded cards always use the compact horizontal style; respect
      // existing layout if explicitly set (rare).
      layoutOverride={cardData.layout === "compact" ? "compact" : "horizontal"}
      onClick={onOpen ? () => onOpen(cardData, openPayload, openSession) : undefined}
      onToggleCheck={cardData.checkDone !== undefined && assetId
        ? (next) => toggleTodo(assetId, next)
        : undefined}
    />
  );
}

/** Build a minimal CardData for the onOpen callback when the event branch
 *  is taken — keeps the existing onOpen signature happy. OP12: subtitle uses
 *  a precomputed clean "when" string so the drawer header doesn't show raw
 *  ISO (2026-05-29T02:00:00+00:00). */
function buildEventCardData(data: Record<string, unknown>): CardData {
  const payload = { ...data, when: eventWhen(data) };
  return buildCard({
    payload,
    spec: {
      card_layout: "horizontal", icon: "📅", accent_color: "purple",
      primary_field: "title", secondary_field: "when",
    },
    assetId:    String(data.event_id ?? data.id ?? ""),
    cardType:   "event",
    displayName: String(data.title ?? "事件"),
  });
}

/* ── Helpers ────────────────────────────────────────────────────────────── */

/** Clean "5月29日 10:00 — 12:00" / "… · 全天" subtitle for an event-shaped
 *  tool_result. Mirrors EventCard.formatWhen + CalendarPage.eventWhenLabel. */
function eventWhen(data: Record<string, unknown>): string {
  const startRaw = data.start_at;
  if (typeof startRaw !== "string") return "";
  const d = new Date(startRaw);
  if (Number.isNaN(d.getTime())) return "";
  const md = `${d.getMonth() + 1}月${d.getDate()}日`;
  if (data.all_day) return `${md} · 全天`;
  const pad = (n: number) => String(n).padStart(2, "0");
  const startT = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const endRaw = data.end_at;
  if (typeof endRaw !== "string" || !endRaw) return `${md} ${startT}`;
  const e = new Date(endRaw);
  if (Number.isNaN(e.getTime())) return `${md} ${startT}`;
  return `${md} ${startT} — ${pad(e.getHours())}:${pad(e.getMinutes())}`;
}

function pickString(obj: Record<string, unknown>, keys: string[]): string | null {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === "string" && v.length > 0) return v;
  }
  return null;
}

function pickObject(obj: Record<string, unknown>, key: string): Record<string, unknown> | null {
  const v = obj[key];
  if (v && typeof v === "object" && !Array.isArray(v)) return v as Record<string, unknown>;
  return null;
}

/**
 * Fallback render_spec for things we don't have a registered UserSkill for.
 * Mirrors the inline synthesis in CategoryDetail so chat-rendered cards look
 * the same as drill-down cards.
 */
function synthesizeSpec(
  skillName: string | null,
  data: Record<string, unknown>,
): Parameters<typeof buildCard>[0]["spec"] {
  if (skillName === "event") {
    return {
      card_layout: "horizontal",
      icon: "📅",
      accent_color: "purple",
      primary_field: "title",
      secondary_field: "start_at",
      secondary_format: "relative_date",
      meta_fields: [{ field: "location" }],
    };
  }
  if (skillName === "task") {
    return {
      card_layout: "horizontal",
      icon: "⏳",
      accent_color: "amber",
      primary_field: "title",
      secondary_field: "external_system",
      // Surface the async lifecycle state (pending/running/done/failed) as a
      // colored badge — see SkillCard.LIFECYCLE_STATUS. Without this the
      // in-flight card showed no state at all in chat.
      meta_fields: [{ field: "status", format: "badge" }],
    };
  }
  if (skillName === "external_ref") {
    return {
      card_layout: "horizontal",
      icon: "🔗",
      accent_color: "purple",
      primary_field: "title",
      secondary_field: "external_system",
      meta_fields: [{ field: "status", format: "badge" }],
    };
  }
  // Best-effort: render whatever field looks like a title
  void data;
  return null;
}
