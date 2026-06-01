import { useEffect, useMemo, useRef, useState } from "react";

import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useTimeline, toLocalDayKey } from "@/hooks/useTimeline";
import { timelineItemVisual, type SkillLookup } from "@/lib/timeline-visual";
import type { TimelineItem } from "@/lib/types";

/**
 * MonthPane — SW: Month as an inline swipe-deck pane (was a slide-in
 * overlay in TP2 FG). The deck in CalendarPage arranges Schedule / Month /
 * Year side by side; horizontal swipe moves between them. So Month no
 * longer needs an overlay shell / scrim — it's a full-size pane.
 *
 * Continuous scroll (G, retained): stacks 13 months (cursor −6 … +6) in a
 * vertical scroll, auto-scrolls to the cursor month on mount, and re-scrolls
 * when `focusMonthKey` changes (e.g. Year pane → tap a month → deck swipes
 * here + scrolls to it).
 *
 * Selected-day footer: tapping a day selects it (blue ring) → footer shows
 * that day's items; tapping an item routes up via onItemTap; tapping a day
 * twice (or via the footer) can open DayDetail through onDayOpen.
 *
 *   ┌───────────────────────────────┐
 *   │ 2026                    今天   │ ← header (year + jump-to-today)
 *   │ ─────────────────────────────  │
 *   │  4月  S M T W T F S            │ ← continuous month scroll
 *   │  · · ● · · ○ ·                 │
 *   │  5月  ...                      │
 *   ├───────────────────────────────┤
 *   │ 周三 · 今天 · 5月27日           │ ← selected-day footer
 *   │ 10:00 ● 产品评审                │
 *   │ (create via global dock + button)│
 *   └───────────────────────────────┘
 */

interface MonthPaneProps {
  /** Anchor month (the deck keeps this = today; Year nav overrides via
   *  focusMonthKey). */
  cursor: Date;
  /** YYYY-MM — when set/changed, scroll that month into view (Year→Month). */
  focusMonthKey?: string | null;
  onItemTap?: (item: TimelineItem) => void;
  /** Open DayDetail for a day (tap the day's date dot a second time, or any
   *  day with content). */
  onDayOpen?: (dayKey: string) => void;
  /** Redesign: hide own header when rendered under CalendarPage's Segmented. */
  embedded?: boolean;
}

const MONTHS_BACK = 6;
const MONTHS_FWD = 6;

export function MonthPane({
  cursor, focusMonthKey, onItemTap, onDayOpen, embedded,
}: MonthPaneProps) {
  const { byDay } = useTimeline();
  // Per-item type signal in the selected-day footer (matches the 流 view).
  const { bySkill } = useSkillRegistry();
  const todayKey = toLocalDayKey(new Date().toISOString());

  const [selected, setSelected] = useState<string>(todayKey);

  // 13 months centered on cursor.
  const months = useMemo(() => {
    const out: Date[] = [];
    for (let i = -MONTHS_BACK; i <= MONTHS_FWD; i++) {
      out.push(new Date(cursor.getFullYear(), cursor.getMonth() + i, 1));
    }
    return out;
  }, [cursor]);

  const scrollRef = useRef<HTMLDivElement | null>(null);
  const cursorMonthKey = `${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`;

  // Auto-scroll to the cursor month on mount.
  useEffect(() => {
    const el = scrollRef.current?.querySelector<HTMLElement>(`[data-month="${cursorMonthKey}"]`);
    el?.scrollIntoView({ block: "start", behavior: "auto" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Re-scroll when Year pane requests a specific month.
  useEffect(() => {
    if (!focusMonthKey) return;
    const el = scrollRef.current?.querySelector<HTMLElement>(`[data-month="${focusMonthKey}"]`);
    el?.scrollIntoView({ block: "start", behavior: "auto" });
  }, [focusMonthKey]);

  function handleSelect(dayKey: string) {
    // Tapping the already-selected day opens DayDetail (matches the
    // Timepage "tap day → day view" affordance).
    if (dayKey === selected) onDayOpen?.(dayKey);
    setSelected(dayKey);
  }

  return (
    <div
      className="relative flex flex-col h-full"
      style={{
        background: "#06070d",
        color: "#d4dbe6",
        fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      }}
    >
      {/* Header: year + jump-to-today — hidden when embedded under the
          CalendarPage Segmented control (redesign). */}
      {!embedded && (
      <header
        className="shrink-0 flex items-center justify-between"
        style={{ padding: "16px 20px 12px", borderBottom: "1px solid rgba(255,255,255,0.06)" }}
      >
        <div
          className="font-display"
          style={{
            fontSize: 26, fontWeight: 700, color: "#a4c2ff",
            letterSpacing: "-0.01em",
            textShadow: "0 0 18px rgba(111,158,255,0.4)",
          }}
        >
          {cursor.getFullYear()}
        </div>
        <button
          type="button"
          onClick={() => {
            setSelected(todayKey);
            const el = scrollRef.current?.querySelector<HTMLElement>(
              `[data-month="${todayKey.slice(0, 7)}"]`,
            );
            el?.scrollIntoView({ block: "start", behavior: "smooth" });
          }}
          className="font-mono"
          style={{
            fontSize: 11, letterSpacing: "0.16em",
            color: "rgba(255,255,255,0.55)",
            padding: "4px 10px", borderRadius: 999,
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(255,255,255,0.08)",
            cursor: "pointer",
          }}
        >
          今天
        </button>
      </header>
      )}

      {/* Continuous month scroll */}
      <div
        ref={scrollRef}
        className="flex-1 overflow-y-auto eu-noscroll"
        style={{ padding: "8px 0 12px" }}
      >
        {months.map((m) => (
          <MonthBlock
            key={`${m.getFullYear()}-${m.getMonth()}`}
            month={m}
            byDay={byDay}
            todayKey={todayKey}
            selected={selected}
            onSelect={handleSelect}
          />
        ))}
      </div>

      {/* Selected-day footer */}
      <SelectedDayFooter
        dayKey={selected}
        items={byDay.get(selected) ?? []}
        bySkill={bySkill}
        onItemTap={(it) => onItemTap?.(it)}
      />
    </div>
  );
}

/* ── MonthBlock — one compact month dot grid ──────────────────────────── */

function MonthBlock({
  month, byDay, todayKey, selected, onSelect,
}: {
  month: Date;
  byDay: Map<string, TimelineItem[]>;
  todayKey: string;
  selected: string;
  onSelect: (k: string) => void;
}) {
  const cells = useMemo(() => buildCells(month), [month]);
  const monthKey = `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, "0")}`;
  const isCurrentMonth = monthKey === todayKey.slice(0, 7);

  return (
    <div data-month={monthKey} style={{ padding: "10px 18px 18px" }}>
      {/* Month label */}
      <div className="flex items-baseline gap-2" style={{ marginBottom: 8 }}>
        <span
          className="font-display"
          style={{
            fontSize: 18, fontWeight: 700,
            color: isCurrentMonth ? "#a4c2ff" : "#f4f7fb",
            letterSpacing: "-0.01em",
            textShadow: isCurrentMonth ? "0 0 14px rgba(111,158,255,0.4)" : "none",
          }}
        >
          {month.getMonth() + 1}月
        </span>
        <span
          className="font-mono"
          style={{ fontSize: 10.5, color: "rgba(255,255,255,0.35)", letterSpacing: "0.14em" }}
        >
          {month.getFullYear()}
        </span>
      </div>

      {/* Weekday header */}
      <div className="grid" style={{ gridTemplateColumns: "repeat(7, 1fr)", marginBottom: 4 }}>
        {["S", "M", "T", "W", "T", "F", "S"].map((d, i) => (
          <div
            key={i}
            className="font-mono text-center"
            style={{ fontSize: 9.5, color: "rgba(255,255,255,0.28)", letterSpacing: "0.14em" }}
          >
            {d}
          </div>
        ))}
      </div>

      {/* Dot grid */}
      <div className="grid" style={{ gridTemplateColumns: "repeat(7, 1fr)", gap: 2 }}>
        {cells.map((c) => {
          const items = byDay.get(c.key) ?? [];
          const kind = dominantKind(items);
          const isToday = c.key === todayKey;
          const isSelected = c.key === selected;
          const isOut = !c.inCursor;

          let bg = "transparent", fg = "rgba(255,255,255,0.82)",
              border = "transparent", glow: string | undefined;
          if (isOut) fg = "rgba(255,255,255,0.16)";
          if (kind === "event") { bg = "rgba(156,128,240,0.26)"; border = "rgba(196,168,255,0.40)"; fg = "#e5d9ff"; }
          if (kind === "todo")  { bg = "rgba(111,158,255,0.20)"; border = "rgba(138,180,255,0.40)"; fg = "#d4e2ff"; }
          if (kind === "mixed") { bg = "rgba(156,128,240,0.30)"; border = "rgba(196,168,255,0.50)"; fg = "#e5d9ff"; }
          if (isToday) { bg = "#ffffff"; fg = "#1a1735"; border = "transparent"; glow = "0 0 14px rgba(255,255,255,0.6)"; }
          if (isSelected && !isToday) { border = "#6f9eff"; bg = "transparent"; fg = "#a4c2ff"; }

          return (
            <button
              key={c.key}
              type="button"
              onClick={() => onSelect(c.key)}
              className="flex items-center justify-center"
              style={{ padding: "3px 0", background: "transparent", border: "none", cursor: "pointer" }}
            >
              <div
                className="flex items-center justify-center font-mono"
                style={{
                  width: 28, height: 28, borderRadius: 999,
                  background: bg, border: `1.5px solid ${border}`, boxShadow: glow,
                  fontSize: isToday ? 12.5 : 12, fontWeight: isToday ? 700 : 500,
                  color: fg, letterSpacing: "0.02em",
                  transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
                }}
              >
                {c.d}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/* ── Selected-day footer ──────────────────────────────────────────────── */

function SelectedDayFooter({
  dayKey, items, bySkill, onItemTap,
}: {
  dayKey: string;
  items: TimelineItem[];
  bySkill: SkillLookup;
  onItemTap: (it: TimelineItem) => void;
}) {
  return (
    <div
      className="shrink-0 eu-noscroll"
      style={{
        borderTop: "1px solid rgba(255,255,255,0.08)",
        background: "rgba(0,0,0,0.20)",
        // Bottom padding clears the floating dock so the last item isn't
        // hidden behind it (this footer is pinned, not scrolled-through).
        // Per-day creation is via the dock's global + (context-aware add
        // entry); no inline "+ 添加事件" — see CalendarPage rev.
        padding: "14px 20px",
        paddingBottom: "calc(env(safe-area-inset-bottom) + 96px)",
        maxHeight: "42%", overflowY: "auto",
      }}
    >
      <div
        className="font-mono"
        style={{
          fontSize: 10.5, letterSpacing: "0.20em",
          color: "rgba(255,255,255,0.50)", fontWeight: 600, marginBottom: 10,
        }}
      >
        {fullDateLabel(dayKey)}
      </div>
      {items.length === 0 ? (
        <div style={{ fontSize: 13, color: "rgba(255,255,255,0.40)", fontStyle: "italic" }}>
          空闲
        </div>
      ) : (
        <div className="flex flex-col gap-2.5">
          {items.map((it) => {
            const { glyph, glow } = timelineItemVisual(it, bySkill);
            return (
              <button
                key={`${it.kind}-${it.id}`}
                type="button"
                onClick={() => onItemTap(it)}
                className="flex items-center gap-3 text-left"
                style={{ background: "transparent", border: "none", cursor: "pointer" }}
              >
                <span
                  className="font-mono"
                  style={{ fontSize: 11, color: "rgba(255,255,255,0.55)", minWidth: 40 }}
                >
                  {formatTime(it)}
                </span>
                {/* Type signal: skill icon + accent halo (was a generic dot). */}
                <span
                  style={{
                    flex: "0 0 17px", width: 17, height: 17,
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 12.5, lineHeight: 1,
                    filter: `drop-shadow(0 0 4px ${glow})`,
                  }}
                >
                  {glyph}
                </span>
                <span style={{ fontSize: 13.5, color: "#f4f7fb", fontWeight: 500 }}>
                  {it.title}
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

/* ── Helpers (mirrors MonthGrid) ──────────────────────────────────────── */

interface Cell { key: string; d: number; inCursor: boolean; }

function buildCells(cursor: Date): Cell[] {
  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const start = new Date(first);
  start.setDate(first.getDate() - first.getDay());
  const out: Cell[] = [];
  for (let i = 0; i < 42; i++) {
    const d = new Date(start);
    d.setDate(start.getDate() + i);
    out.push({
      key: toLocalDayKey(d.toISOString()),
      d: d.getDate(),
      inCursor: d.getMonth() === cursor.getMonth(),
    });
  }
  return out;
}

function dominantKind(items: TimelineItem[]): "event" | "todo" | "mixed" | undefined {
  const hasEvent = items.some((i) => i.kind === "event");
  const hasTodo  = items.some((i) => i.kind === "asset" && (i.skill_name === "todo" || i.skill_name === "expense"));
  if (hasEvent && hasTodo) return "mixed";
  if (hasEvent)            return "event";
  if (hasTodo)             return "todo";
  return undefined;
}

function formatTime(it: TimelineItem): string {
  if (it.kind === "event" && it.all_day) return "全天";
  const d = new Date(it.effective_at);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fullDateLabel(dayKey: string): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  const weekday = ["周日","周一","周二","周三","周四","周五","周六"][new Date(y, m - 1, d).getDay()];
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const days = Math.round((Date.UTC(y, m - 1, d) - Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())) / 86_400_000);
  const dist = days === 0 ? "今天"
    : days === 1 ? "明天" : days === -1 ? "昨天"
    : days > 0 ? `${days} 天后` : `${-days} 天前`;
  return `${weekday} · ${dist} · ${m}月${d}日`;
}
