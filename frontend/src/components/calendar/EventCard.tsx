import { SkillCard } from "@/components/skill/SkillCard";
import { buildCard } from "@/lib/render-spec";
import type { CardLayout } from "@/lib/render-spec";

/**
 * EventCard — the ONE event card visual used everywhere events show up.
 *
 * Per the M4-bugfix-2 review: events previously rendered 4 different ways
 * across the app (Schedule colored tile row / DayDetail glass card with
 * mono caps / Library RecentCard bespoke / Chat AssetCardInChat). The user
 * picked "只统一里面的卡,外面的容器保留" — so Schedule's day tile container
 * and DayDetail's gradient page container stay, but every event-shaped card
 * inside (and Library / Chat too) renders via this one component.
 *
 * Visual = SkillCard horizontal with the same render_spec template the
 * chat tool_result extractor synthesizes (`synthesizeSpec('event')` in
 * MessageBubble), so chat / library / day-detail look identical.
 *
 * Subtitle is computed smart:
 *   all_day        → "5月29日 · 全天"
 *   with end_at    → "5月29日 10:00 — 11:00"
 *   start only     → "5月29日 10:00"
 *
 * Location goes into a meta pill when present.
 */

export interface EventCardData {
  event_id?: string;
  id?:       string;
  title:     string;
  start_at:  string;
  end_at?:   string | null;
  all_day?:  boolean | number;
  location?: string | null;
}

interface EventCardProps {
  event:     EventCardData;
  onClick?:  () => void;
  /** Override (rare). Defaults to "horizontal" matching SkillCard. */
  layout?:   CardLayout;
  /** OP8: optional "created at" relative-time chip appended to meta. Used
   *  by Library 最近 to surface the sort dimension (created_at desc). */
  createdMeta?: string;
}

export function EventCard({ event, onClick, layout, createdMeta }: EventCardProps) {
  const payload: Record<string, unknown> = {
    title:    event.title,
    when:     formatWhen(event),
    location: event.location ?? "",
  };
  const metaFields: Array<{ field: string }> = [];
  if (event.location)  metaFields.push({ field: "location" });
  if (createdMeta) {
    payload.created_meta = createdMeta;
    metaFields.push({ field: "created_meta" });
  }
  const card = buildCard({
    payload,
    spec: {
      card_layout:    "horizontal",
      icon:           "📅",
      accent_color:   "purple",
      primary_field:  "title",
      secondary_field: "when",
      meta_fields:    metaFields,
    },
    assetId:    event.event_id ?? event.id ?? null,
    cardType:   "event",
    displayName: event.title,
  });
  return <SkillCard data={card} layoutOverride={layout} onClick={onClick} />;
}

/** Smart subtitle formatting — see component docstring. */
function formatWhen(e: EventCardData): string {
  const start = new Date(e.start_at);
  const dateStr = `${start.getMonth() + 1}月${start.getDate()}日`;
  if (e.all_day) return `${dateStr} · 全天`;
  const pad = (n: number) => String(n).padStart(2, "0");
  const startStr = `${pad(start.getHours())}:${pad(start.getMinutes())}`;
  if (!e.end_at) return `${dateStr} ${startStr}`;
  const end = new Date(e.end_at);
  const endStr = `${pad(end.getHours())}:${pad(end.getMinutes())}`;
  return `${dateStr} ${startStr} — ${endStr}`;
}
