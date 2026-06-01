import { useState } from "react";

import { AssetDetailDrawer } from "@/components/asset/AssetDetailDrawer";
import { DayDetailSheet } from "@/components/calendar/DayDetailSheet";
import { MonthPane } from "@/components/calendar/MonthPane";
import { YearPane } from "@/components/calendar/YearPane";
import { ScheduleView } from "@/components/calendar/ScheduleView";
import { useEvents } from "@/hooks/useEvents";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { swrFetcher } from "@/lib/api";
import { buildCard } from "@/lib/render-spec";
import useSWR from "swr";
import type { AssetsResponse, TimelineItem } from "@/lib/types";

/**
 * CalendarPage — Mobile-Redesign: a Segmented (流/月/年) control switches
 * between three views; month is the default. Replaces the old horizontal swipe
 * deck (per the new design spec + user decision — match the segmented model).
 *
 *   ┌─────────────────────────────┐
 *   │        [ 流 | 月 | 年 ]       │ ← segmented control
 *   ├─────────────────────────────┤
 *   │  active view (flow/month/yr) │
 *   └─────────────────────────────┘
 */

type CalMode = "timeline" | "month" | "year";

export function CalendarPage() {
  const [cursor]                        = useState<Date>(() => new Date());
  const [mode, setMode]                 = useState<CalMode>("month"); // 流/月/年 — month default
  const [focusMonthKey, setFocusMonthKey] = useState<string | null>(null);
  const [dayDetailKey, setDayDetailKey] = useState<string | null>(null);
  const [openEventId, setOpenEventId]   = useState<string | null>(null);
  const [openAssetId, setOpenAssetId]   = useState<string | null>(null);

  function handleItemTap(item: TimelineItem) {
    if (item.kind === "event") {
      setOpenEventId(item.event_id ?? item.id);
    } else {
      setOpenAssetId(item.id);
    }
    setDayDetailKey(null);
  }

  // Create-from-day was removed: creation goes through the global dock + entry
  // (FloatingDock owns CreateAssetMenu). No inline "+ 添加事件" anywhere.

  // Year view → tap a month → switch to Month view + scroll it to that month.
  function handlePickMonth(monthKey: string) {
    setFocusMonthKey(monthKey);
    setMode("month");
  }

  return (
    <div className="flex flex-col h-full">
      {/* Segmented 流/月/年 — the sole calendar nav (redesign). Month default. */}
      <div className="shrink-0 flex justify-center px-eu-md pt-1 pb-2">
        <Segmented value={mode} onChange={setMode} />
      </div>

      <div className="flex-1 min-h-0 overflow-hidden">
        {mode === "timeline" && (
          <ScheduleView embedded onItemTap={handleItemTap} onDayTap={(k) => setDayDetailKey(k)} />
        )}
        {mode === "month" && (
          <MonthPane
            embedded
            cursor={cursor}
            focusMonthKey={focusMonthKey}
            onItemTap={handleItemTap}
            onDayOpen={(k) => setDayDetailKey(k)}
          />
        )}
        {mode === "year" && (
          <YearPane initialYear={cursor.getFullYear()} onPickMonth={handlePickMonth} />
        )}
      </div>

      {/* ── overlays ─────────────────────────────────────────────────── */}

      {dayDetailKey && (
        <DayDetailSheet
          dayKey={dayDetailKey}
          onClose={() => setDayDetailKey(null)}
          onItemTap={handleItemTap}
        />
      )}

      {openEventId && (
        <EventDetailModal
          eventId={openEventId}
          onClose={() => setOpenEventId(null)}
        />
      )}

      {openAssetId && (
        <AssetDetailModal
          assetId={openAssetId}
          onClose={() => setOpenAssetId(null)}
        />
      )}
    </div>
  );
}

/**
 * Segmented — 流/月/年 toggle, per the Mobile-Redesign spec (calendar.jsx
 * Segmented): a pill of options, the active one tinted brand-faint with a
 * brand-line border + brand-hi text.
 */
function Segmented({ value, onChange }: { value: CalMode; onChange: (m: CalMode) => void }) {
  const opts: [CalMode, string][] = [["timeline", "流"], ["month", "月"], ["year", "年"]];
  return (
    <div
      style={{
        display: "flex",
        padding: 3,
        borderRadius: 999,
        background: "var(--eu-surface)",
        border: "1px solid var(--eu-border)",
      }}
    >
      {opts.map(([k, l]) => {
        const active = value === k;
        return (
          <button
            key={k}
            type="button"
            onClick={() => onChange(k)}
            className="font-display"
            style={{
              padding: "5px 18px",
              borderRadius: 999,
              background: active ? "var(--eu-brand-faint)" : "transparent",
              border: active ? "1px solid var(--eu-brand-line)" : "1px solid transparent",
              color: active ? "var(--eu-brand-hi)" : "var(--eu-text-mid)",
              fontSize: 12.5,
              fontWeight: 600,
              letterSpacing: "0.04em",
              cursor: "pointer",
              transition: "all var(--eu-dur-fast) var(--eu-ease-in-out)",
            }}
          >
            {l}
          </button>
        );
      })}
    </div>
  );
}

/**
 * AssetDetailModal — convenience wrapper that loads an asset by id and renders
 * AssetDetailDrawer when ready. CalendarPage opens this when the user taps a
 * non-event timeline item (todo / idea / etc.).
 *
 * Uses the same /api/assets list endpoint as ContextChipRail does — for the
 * MVP scale of <500 assets this is cheap and avoids a per-id round-trip.
 */
function AssetDetailModal({ assetId, onClose }: { assetId: string; onClose: () => void }) {
  const { bySkill } = useSkillRegistry();
  const { data } = useSWR<AssetsResponse>("/api/assets?limit=500", swrFetcher);
  const asset = data?.assets.find((a) => a.id === assetId);
  if (!asset) return null;

  const skill = bySkill.get(asset.user_skill_name);
  const card = buildCard({
    payload: asset.payload,
    spec: skill?.render_spec ?? null,
    assetId: asset.id,
    cardType: asset.user_skill_name,
    displayName: skill?.display_name ?? asset.user_skill_name,
  });

  return (
    <AssetDetailDrawer
      card={card}
      payload={asset.payload}
      sourceSessionId={asset.session_id}
      onClose={onClose}
    />
  );
}

/**
 * EventDetailModal — RV5 wrapper that opens AssetDetailDrawer for an
 * event row. Tap event in Schedule / DayDetail / Month-summary now lands
 * here first (view), and the drawer's 编辑 button hands off to EventForm
 * — same flow as assets. No more "tap event = jump to editor" special
 * case.
 */
function EventDetailModal({ eventId, onClose }: { eventId: string; onClose: () => void }) {
  const { events } = useEvents();
  const event = events.find((e) => e.event_id === eventId);
  if (!event) return null;

  // Build a CardData with cardType="event" so AssetDetailDrawer's edit
  // branch knows to route to EventForm (not SkillCreateForm).
  const card = buildCard({
    payload: event as unknown as Record<string, unknown>,
    spec: {
      card_layout:    "horizontal",
      icon:           "📅",
      accent_color:   "purple",
      primary_field:  "title",
      // OP12: use a precomputed clean "when" string (was secondary_field:
      // start_at → rendered the raw ISO "2026-05-27T16:00:00+00:00" in the
      // drawer header).
      secondary_field: "when",
    },
    assetId:     event.event_id,
    cardType:    "event",
    displayName: event.title,
  });

  // Make a payload object so GenericField can render the readable fields
  // (title / start_at / end_at / location / description). SKIP_KEYS hides
  // the noisy internals (status, all_day, ok, event_id, etc.). `when` is a
  // synthetic field only used for the card subtitle, not shown in the body.
  const payload = {
    ...(event as unknown as Record<string, unknown>),
    when: eventWhenLabel(event),
  };

  return (
    <AssetDetailDrawer
      card={card}
      payload={payload}
      sourceSessionId={null}
      onClose={onClose}
    />
  );
}

/** OP12: clean "when" subtitle for the event drawer header. */
function eventWhenLabel(e: { start_at: string; end_at?: string | null; all_day?: boolean }): string {
  const d = new Date(e.start_at);
  const md = `${d.getMonth() + 1}月${d.getDate()}日`;
  if (e.all_day) return `${md} · 全天`;
  const pad = (n: number) => String(n).padStart(2, "0");
  const startT = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  if (!e.end_at) return `${md} ${startT}`;
  const e2 = new Date(e.end_at);
  return `${md} ${startT} — ${pad(e2.getHours())}:${pad(e2.getMinutes())}`;
}
