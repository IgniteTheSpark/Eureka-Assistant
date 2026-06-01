import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";

import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useTimeline, toLocalDayKey } from "@/hooks/useTimeline";
import { timelineItemVisual } from "@/lib/timeline-visual";
import type { TimelineItem } from "@/lib/types";

/**
 * ScheduleView — Timepage-style scroll timeline (M4-timepage refactor).
 *
 * Five behavior shifts from the M3-redo canvas-literal version, learned
 * directly from a Timepage screen recording the user shared:
 *
 * A. Floating「N 天/周/月/年 前/后」overlay during scroll
 *    - Big black text centered on the current viewport-center day
 *    - fade-in while scrolling, fade-out 250ms after scroll stops
 *    - tells the user "where am I" without reading rail numbers
 *
 * B. Rail year+month vertical label, current-month highlighted
 *    - Each month's first row gets a "2026 年 X 月" vertical-rl label
 *    - Brand blue + glow when matching today's month, dim white otherwise
 *    - gives the rail an anchor instead of just floating dates
 *
 * C. All day tiles same tint (Timepage uses one blue across everything)
 *    - Old code computed dominant accent (purple/blue/mixed/amber/dark)
 *      which made scrolling visually noisy
 *    - Now: one brand blue tint everywhere; per-item accent shows via the
 *      dot + text color inside the tile (events purple dot, todos blue, …)
 *
 * D. Empty days = same tint, no "空闲" italic
 *    - Empty tile is just blue space (continuity, "time flowing")
 *    - The 「仅有事 / 全部」 toggle still controls whether empty rows
 *      collapse into gap-summary chips; this only changes how each
 *      individual empty tile renders when it IS shown
 *
 * E. 「跳回今天」 floating button
 *    - 56×56 dock-style button bottom-center, only when today is offscreen
 *    - tap → smooth-scroll today's tile to the viewport center
 *
 * Numbers (time / weekday caps / counts) run JetBrains Mono with
 * 0.16-0.22em letter-spacing per design-system §3.3.
 *
 * Bucketing window: from earliest item back ~14 days before today, then
 * forward ~21 days. Adjustable by `showEmpty` toggle.
 */

interface ScheduleViewProps {
  /** Item taps route up to the parent — events open editor, assets open drawer. */
  onItemTap: (item: TimelineItem) => void;
  /** Day-tile tap (whole tile, not item row) → DayDetailSheet. */
  onDayTap?: (dayKey: string) => void;
  /** Redesign: when rendered under CalendarPage's Segmented control, hide this
   *  view's own header (month label + 仅有事/⌕/⋮) — the month context lives in
   *  the left vertical rail, and the redesign drops the filter toggle. */
  embedded?: boolean;
}

/**
 * Show-empty toggle persisted in localStorage so the user's preference
 * survives reloads (the alternative — re-flooding the rail with grey
 * tiles on every visit — feels broken when data is sparse).
 */
const EMPTY_PREF_KEY = "eureka:schedule_show_empty";

// RV2: removed type-filter chips. The horizontal chip row (全部 / 事件 /
// 待办 / 想法 / 记账 / 名片) was redundant — most users always stayed on
// "全部" and the chips ate ~50px of header space every render. The per-
// type display preference will move to a Settings page in M5; in the
// meantime Schedule shows everything.

export function ScheduleView({ onItemTap, onDayTap, embedded }: ScheduleViewProps) {
  const { items, isLoading } = useTimeline();
  // Per-item type signal: each row shows its skill's icon (✅ todo, 💡 idea,
  // 💰 记账, 🏃 跑步…) instead of a generic dot, so the timeline reads as typed.
  const { bySkill } = useSkillRegistry();
  // Infinite-ish forward scroll: the window grows toward the future as the user
  // scrolls near the bottom (appending rows → no scroll jump). Past is a
  // generous fixed window. Reset isn't needed — it only grows within a session.
  const [fwdDays, setFwdDays] = useState(120);
  const [showEmpty, setShowEmpty] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return window.localStorage.getItem(EMPTY_PREF_KEY) === "1";
  });
  useEffect(() => {
    if (typeof window === "undefined") return;
    window.localStorage.setItem(EMPTY_PREF_KEY, showEmpty ? "1" : "0");
  }, [showEmpty]);

  // ── Build day buckets across the visible window ──────────────────────────
  // Window: -14d ... earliest item ... +21d from today.
  const fullDayWindow = useMemo(() => buildDayWindow(items, fwdDays), [items, fwdDays]);
  const byDay = useMemo(() => {
    const m = new Map<string, TimelineItem[]>();
    for (const it of items) {
      const k = toLocalDayKey(it.effective_at);
      const arr = m.get(k) ?? [];
      arr.push(it);
      m.set(k, arr);
    }
    for (const arr of m.values()) {
      arr.sort((a, b) => a.effective_at.localeCompare(b.effective_at));
    }
    return m;
  }, [items]);

  const todayKey    = toLocalDayKey(new Date().toISOString());
  const tomorrowKey = toLocalDayKey(addDays(new Date(), 1).toISOString());

  // Compact mode (default): show only days with content + today + tomorrow.
  // When a stretch of empty days exists between two visible days, we render
  // ONE collapsible separator "N 天空闲" instead of N grey tiles.
  // Full mode: render every day in the window (the original canvas behavior).
  const visibleRows = useMemo<RailRow[]>(
    () => buildRows(fullDayWindow, byDay, todayKey, tomorrowKey, showEmpty),
    [fullDayWindow, byDay, todayKey, tomorrowKey, showEmpty],
  );

  // Auto-scroll to today on mount so user lands on "now" instead of the
  // window's start. data-day-key marker is on each row.
  const tilesRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    scrollToToday(tilesRef.current, todayKey, "auto");
    // Run only on first mount + when visibleRows length changes (not item taps)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visibleRows.length]);

  // A — floating "N 天/周/月/年 前/后" overlay during scroll.
  // E — "跳回今天" button visibility (today off-screen → show).
  // Both driven by the same rAF-throttled scroll handler.
  const [overlay,      setOverlay]      = useState<{ text: string; visible: boolean } | null>(null);
  const [todayInView,  setTodayInView]  = useState(true);
  const scrollEndTimer  = useRef<number | null>(null);
  const rafQueued       = useRef(false);
  useEffect(() => {
    const container = tilesRef.current;
    if (!container) return;

    const compute = () => {
      rafQueued.current = false;
      // Infinite forward scroll: near the bottom, push the window further into
      // the future (cap ~10y). Appending rows keeps scroll position stable.
      if (container.scrollHeight - container.scrollTop - container.clientHeight < 800) {
        setFwdDays((d) => (d < 3650 ? d + 120 : d));
      }
      const dayKey = dayKeyAtViewportCenter(container);
      if (!dayKey) return;
      const dist = distanceLabel(dayKey, todayKey);
      setOverlay({ text: dist, visible: true });
      setTodayInView(isTodayInViewport(container, todayKey));
      // Reset the "scroll stopped" timer — fade overlay 250ms after last scroll
      if (scrollEndTimer.current) window.clearTimeout(scrollEndTimer.current);
      scrollEndTimer.current = window.setTimeout(() => {
        setOverlay((o) => o ? { ...o, visible: false } : null);
      }, 250);
    };
    const onScroll = () => {
      if (rafQueued.current) return;
      rafQueued.current = true;
      window.requestAnimationFrame(compute);
    };

    container.addEventListener("scroll", onScroll, { passive: true });
    // Initial check so the button state is right at mount
    setTodayInView(isTodayInViewport(container, todayKey));
    return () => {
      container.removeEventListener("scroll", onScroll);
      if (scrollEndTimer.current) window.clearTimeout(scrollEndTimer.current);
    };
  }, [todayKey, visibleRows.length]);

  function handleJumpToday() {
    scrollToToday(tilesRef.current, todayKey, "smooth");
  }

  return (
    <div className="flex flex-col h-full" style={{ background: "#06070d" }}>
      {/* ── Top header: month + tools ─── hidden when embedded under the
          CalendarPage Segmented control (redesign) ───────────────────── */}
      {!embedded && (
      <>
      <header className="flex items-center justify-between px-eu-md pt-1 pb-2.5">
        <div className="flex items-baseline gap-2">
          <span
            className="font-display font-bold"
            style={{
              fontSize: 20, color: "#a4c2ff", letterSpacing: "-0.01em",
              textShadow: "0 0 14px rgba(111,158,255,0.4)",
            }}
          >
            {currentMonthLabel()}
          </span>
          <span
            className="font-mono"
            style={{
              fontSize: 11, color: "rgba(255,255,255,0.40)", letterSpacing: "0.14em",
            }}
          >
            {new Date().getFullYear()}
          </span>
        </div>
        <div className="flex gap-2 items-center">
          {/* M4-polish: 「显示空闲」toggle — default off so sparse calendars
              don't look empty. Persisted in localStorage. */}
          <button
            type="button"
            onClick={() => setShowEmpty((v) => !v)}
            className="font-mono"
            style={{
              padding: "4px 10px", borderRadius: 999,
              fontSize: 10.5, letterSpacing: "0.16em",
              background: showEmpty ? "rgba(111,158,255,0.14)" : "rgba(255,255,255,0.03)",
              color: showEmpty ? "#a4c2ff" : "rgba(255,255,255,0.55)",
              border: `1px solid ${showEmpty ? "rgba(111,158,255,0.32)" : "rgba(255,255,255,0.08)"}`,
              cursor: "pointer",
            }}
            title={showEmpty ? "隐藏空闲日" : "显示空闲日"}
          >
            {showEmpty ? "全部" : "仅有事"}
          </button>
          <IconChip glyph="⌕" />
          <IconChip glyph="⋮" />
        </div>
      </header>

      {/* RV2: filter chips removed — defaults to showing all types. Per-
          type display preferences will move to a Settings page in M5.
          A thin separator keeps the header / content visually divided. */}
      <div style={{ borderBottom: "1px solid rgba(255,255,255,0.04)" }} />
      </>
      )}

      {isLoading && (
        <div className="px-eu-md py-eu-md text-eu-sm text-eu-text-lo font-mono">加载…</div>
      )}

      {/* ── Rail + tile stream wrapper — relative so A overlay + E button
          can be absolute-positioned inside the scroll viewport ───────── */}
      <div className="relative flex-1 min-h-0">
      {/* A: floating distance overlay — big black text, centered on the
          current viewport-center day. fades in during scroll, out after
          250ms idle. Non-interactive (pointer-events:none) so scroll
          doesn't stutter under the cursor. */}
      {overlay && (
        <div
          className="pointer-events-none absolute z-10"
          style={{
            right: 18, top: "42%", transform: "translateY(-50%)",
            textAlign: "right",
            // Redesign: a faint light-gray watermark on the right (not a dark
            // centered block) — matches the spec's translucent diff indicator.
            opacity: overlay.visible ? 0.16 : 0,
            transition: "opacity 220ms cubic-bezier(.2,.7,.3,1)",
          }}
        >
          <div
            className="font-display select-none"
            style={{
              fontSize: 64, fontWeight: 700, lineHeight: 0.9,
              color: "var(--eu-text-hi)", letterSpacing: "-0.03em",
              whiteSpace: "nowrap",
            }}
          >
            {overlay.text}
          </div>
        </div>
      )}
      {/* E: 「跳回今天」 button — shows only when today is off-screen */}
      {!todayInView && (
        <button
          type="button"
          onClick={handleJumpToday}
          aria-label="跳回今天"
          className="absolute z-20 active:scale-95"
          style={{
            bottom: 16, left: "50%", transform: "translateX(-50%)",
            width: 44, height: 44, borderRadius: 999,
            background: "rgba(11,18,32,0.85)",
            backdropFilter: "blur(8px)",
            border: "1px solid rgba(255,255,255,0.10)",
            color: "rgba(255,255,255,0.85)",
            boxShadow: "0 6px 20px rgba(0,0,0,0.35)",
            fontSize: 18, cursor: "pointer",
            transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
          }}
        >
          ⌄
        </button>
      )}
      <div
        ref={tilesRef}
        className="absolute inset-0 overflow-y-auto eu-noscroll"
        // Bottom padding clears the floating dock so the last day tile can
        // scroll fully into view (mid tiles still pass behind the glass dock
        // → 背透). Matches the Library 最近 list clearance.
        style={{ paddingTop: 6, paddingBottom: "calc(env(safe-area-inset-bottom) + 104px)" }}
      >
        {visibleRows.map((row, idx) => {
          if (row.kind === "gap") {
            return (
              <GapRow
                key={`gap-${row.from}-${row.to}`}
                count={row.count}
                onExpand={() => setShowEmpty(true)}
              />
            );
          }

          const dayKey = row.dayKey;
          const dayItems = byDay.get(dayKey) ?? [];
          const empty = dayItems.length === 0;
          const tileHeight = tileHeightFor(dayItems.length);
          const isToday = dayKey === todayKey;
          const label =
            dayKey === todayKey    ? "TODAY"
          : dayKey === tomorrowKey ? "TOMORROW"
          : null;

          // B — render the "2026 年 X 月" vertical rail label on the first
          // day-row of every month boundary in the visible list. Compares
          // against the previous visible day-row's month (gap rows don't
          // count; they advance time but don't render a rail cell).
          const monthKey = dayKey.slice(0, 7); // YYYY-MM
          const prevDayKey = lookupPrevDayKey(visibleRows, idx);
          const monthBoundary = !prevDayKey || prevDayKey.slice(0, 7) !== monthKey;
          const isCurrentMonth = monthKey === todayKey.slice(0, 7);

          return (
            <div
              key={dayKey}
              data-day-key={dayKey}
              data-month-key={monthKey}
              className="grid"
              style={{
                gridTemplateColumns: "64px 1fr",
                marginBottom: 6,
                paddingRight: 16,
              }}
            >
              {/* Rail cell */}
              <div
                className="relative flex flex-col items-end justify-start pt-3 pr-2"
                style={{
                  height: tileHeight,
                  borderRight: "1px solid rgba(255,255,255,0.04)",
                }}
              >
                {isToday && (
                  <div
                    className="absolute"
                    style={{
                      top: 10, bottom: 10, right: 0, width: 2,
                      background: "#6f9eff",
                      boxShadow: "0 0 8px rgba(111,158,255,0.7)",
                    }}
                  />
                )}
                {/* B: vertical year-month label on first day of each month */}
                {monthBoundary && (
                  <span
                    className="font-mono absolute select-none"
                    style={{
                      writingMode: "vertical-rl",
                      transform: "rotate(180deg)",
                      top: 4, left: 4, bottom: 0,
                      fontSize: 10.5, letterSpacing: "0.20em",
                      color: isCurrentMonth ? "#a4c2ff" : "rgba(255,255,255,0.32)",
                      textShadow: isCurrentMonth ? "0 0 8px rgba(111,158,255,0.45)" : "none",
                      fontWeight: isCurrentMonth ? 600 : 500,
                      pointerEvents: "none",
                    }}
                  >
                    {formatYearMonth(dayKey)}
                  </span>
                )}
                <span
                  className="font-mono"
                  style={{
                    fontSize: 9.5, letterSpacing: "0.16em",
                    color: isToday ? "#6f9eff" : "rgba(255,255,255,0.40)",
                  }}
                >
                  {weekdayCap(dayKey)}
                </span>
                <span
                  className="font-display"
                  style={{
                    fontSize: isToday ? 22 : 18,
                    fontWeight: isToday ? 700 : 500,
                    color: isToday ? "#a4c2ff" : "rgba(255,255,255,0.85)",
                    letterSpacing: "-0.01em",
                    marginTop: 1,
                    textShadow: isToday ? "0 0 12px rgba(111,158,255,0.5)" : "none",
                  }}
                >
                  {dayOfMonth(dayKey)}
                </span>
              </div>

              {/* Tile cell — C: uniform tint, D: empty = blue space only */}
              <button
                type="button"
                onClick={() => onDayTap?.(dayKey)}
                className="relative overflow-hidden text-left flex flex-col ml-1.5"
                style={{
                  minHeight: tileHeight,
                  background: UNIFORM_TONE.bg,
                  borderRadius: 14,
                  padding: "14px 18px",
                  justifyContent: "flex-start",
                  gap: 8,
                  cursor: "pointer",
                  border: "none",
                }}
              >
                {label && (
                  <span
                    className="font-mono absolute"
                    style={{
                      top: 10, right: 14,
                      fontSize: 9.5, letterSpacing: "0.20em",
                      color: "rgba(255,255,255,0.55)", fontWeight: 600,
                    }}
                  >
                    {label}
                  </span>
                )}
                {!empty && dayItems.map((it) => (
                  <ItemRow
                    key={`${it.kind}-${it.id}`}
                    item={it}
                    tone={UNIFORM_TONE}
                    bySkill={bySkill}
                    onClick={(e) => { e.stopPropagation(); onItemTap(it); }}
                  />
                ))}
              </button>
            </div>
          );
        })}
      </div>
      </div>
    </div>
  );
}

/**
 * GapRow — collapsed-empty-days separator.
 * Replaces a sequence of empty days with one slim "N 天空闲" row that
 * expands into full empty tiles on click. Keeps the schedule scannable
 * when the user has only a few real items.
 */
function GapRow({ count }: { count: number; onExpand?: () => void }) {
  // Redesign: empty stretches are a quiet thin gradient line, not a prominent
  // "N 天空闲" chip (the user flagged 空闲 as redundant; the spec's flow renders
  // empty days as a faint line). Slightly taller for longer gaps.
  const h = Math.min(34, 16 + count * 2);
  return (
    <div
      className="grid"
      style={{ gridTemplateColumns: "64px 1fr", marginBottom: 6, paddingRight: 16 }}
    >
      <div style={{ borderRight: "1px solid rgba(255,255,255,0.04)", height: h }} />
      <div className="ml-1.5 flex items-center" style={{ height: h }}>
        <div
          style={{
            width: "100%",
            height: 1,
            background: "linear-gradient(90deg, rgba(255,255,255,0.10), transparent)",
          }}
        />
      </div>
    </div>
  );
}

/* ── Day tile item row ─────────────────────────────────────────────────── */

function ItemRow({
  item, tone, onClick, bySkill,
}: {
  item: TimelineItem;
  tone: DayTone;
  onClick: (e: React.MouseEvent) => void;
  bySkill: ReturnType<typeof useSkillRegistry>["bySkill"];
}) {
  const time = formatTime(item);
  const { glyph, glow } = timelineItemVisual(item, bySkill);
  return (
    <div
      onClick={onClick}
      className="flex items-center gap-3 active:scale-[0.99]"
      style={{ cursor: "pointer" }}
    >
      <span
        className="font-mono"
        style={{
          fontSize: 10.5, color: tone.meta, fontWeight: 500,
          minWidth: 44, letterSpacing: "0.02em",
        }}
      >
        {time}
      </span>
      {/* Type signal: the skill's own icon (emoji carries the kind) sitting in
          an accent-tinted halo, replacing the old type-agnostic 5px dot. */}
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
      <span
        style={{
          fontSize: 13.5, color: tone.text, fontWeight: 500,
          letterSpacing: "-0.005em", lineHeight: 1.35,
          flex: 1, minWidth: 0,
          overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
        }}
      >
        {item.title}
      </span>
    </div>
  );
}

function IconChip({ glyph }: { glyph: string }) {
  return (
    <button
      type="button"
      style={{
        width: 28, height: 28, borderRadius: 999,
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.08)",
        color: "rgba(255,255,255,0.65)",
        fontSize: 13, cursor: "pointer",
        fontFamily: '"JetBrains Mono", monospace',
      }}
    >
      {glyph}
    </button>
  );
}

/* ── tile tint (C: single brand blue everywhere) ──────────────────────── */

/**
 * Per the Timepage recording (frame analysis), every day tile uses the
 * SAME blue tint regardless of contents. Old code computed a per-day
 * dominant-accent gradient (purple if events, blue if todos, amber if
 * ideas, dark if empty) which made scrolling visually noisy. The single
 * tint reads as "one continuous river of days" and lets per-item accent
 * dots inside the tile carry the type signal.
 */
const TILE_BG     = "linear-gradient(135deg, rgba(111,158,255,0.20) 0%, rgba(82,128,200,0.10) 100%), #121a32";
const TILE_TEXT   = "#ffffff";
const TILE_META   = "rgba(255,255,255,0.65)";
const TILE_DOT_FALLBACK = "rgba(255,255,255,0.55)";

/** Backwards-compatible shape kept for the row renderer. */
interface DayTone {
  bg: string;
  text: string;
  meta: string;
  dot: string;
}
const UNIFORM_TONE: DayTone = {
  bg: TILE_BG, text: TILE_TEXT, meta: TILE_META, dot: TILE_DOT_FALLBACK,
};

const ACCENT_DOT: Record<string, string> = {
  event:   "#c4a8ff",
  todo:    "#8ab4ff",
  idea:    "#f5c977",
  expense: "#86e0a5",
  contact: "#d4dbe6",
  neutral: "rgba(255,255,255,0.55)",
};

/* ── sub-kind derivation ──────────────────────────────────────────────── */

/**
 * subKindOf — Schedule + filter logic groups items by a 5-way kind:
 * event / todo / idea / expense / contact. For asset items, the source skill
 * name dictates which bucket. Anything else returns null and falls into
 * the "all" bucket only.
 */
function subKindOf(it: TimelineItem): "event" | "todo" | "idea" | "expense" | "contact" | null {
  if (it.kind === "event") return "event";
  switch (it.skill_name) {
    case "todo":    return "todo";
    case "idea":    return "idea";
    case "expense": return "expense";
    case "contact": return "contact";
    default:        return null;
  }
}

/* ── window + bucket math ─────────────────────────────────────────────── */

/**
 * buildDayWindow — return a contiguous list of day keys (YYYY-MM-DD, asc)
 * covering the items' date range plus padding so the user sees context.
 *
 * Past edge: min(earliest item, today − 14d).
 * Future edge: max(latest item, today + 21d).
 *
 * Returned in DESCENDING order so newest is at the TOP of the rail —
 * matches the user's mental model: 「最近发生」 + 上面是「快来到」.
 *
 * Hmm — actually descending puts the future at TOP. Canvas's CalSchedule
 * appears to render days in the order shown (22, 23, 24=today, 25, 26, …)
 * which is ASCENDING. Match the canvas: ascending; scroll position can
 * snap to today on mount (TODO).
 */
function buildDayWindow(items: TimelineItem[], fwdDays: number): string[] {
  const today = new Date(); today.setHours(0, 0, 0, 0);
  let minMs = +addDays(today, -90);
  let maxMs = +addDays(today, fwdDays);
  for (const it of items) {
    const t = +new Date(it.effective_at);
    if (t < minMs) minMs = t;
    if (t > maxMs) maxMs = t;
  }
  // Past: clamp to ~1 year back (sanity). Future: driven by fwdDays, which the
  // scroll handler grows as the user nears the bottom → effectively infinite
  // forward scroll without scroll-position jumps.
  const PAST_MS = 365 * 24 * 3600 * 1000;
  minMs = Math.max(minMs, +today - PAST_MS);

  const days: string[] = [];
  for (let t = minMs; t <= maxMs; t += 24 * 3600 * 1000) {
    days.push(toLocalDayKey(new Date(t).toISOString()));
  }
  return days;
}

/**
 * RailRow — discriminated union of items rendered in the schedule stream.
 *   - { kind: "day", dayKey } → render a full day tile + rail cell
 *   - { kind: "gap", from, to, count } → render one slim "N 天空闲" separator
 *
 * Used by `buildRows` to compress a window's empty days into a single
 * collapsible row when `showEmpty=false`. Today and tomorrow are ALWAYS
 * shown as day rows (even empty) so the user always sees "现在 / 接下来"
 * even on a brand-new install with no data.
 */
type RailRow =
  | { kind: "day"; dayKey: string }
  | { kind: "gap"; from: string; to: string; count: number };

function buildRows(
  fullDayWindow: string[],
  byDay: Map<string, TimelineItem[]>,
  todayKey: string,
  tomorrowKey: string,
  showEmpty: boolean,
): RailRow[] {
  if (showEmpty) return fullDayWindow.map((k) => ({ kind: "day", dayKey: k }));

  const rows: RailRow[] = [];
  let gap: { from: string; to: string; count: number } | null = null;

  const flushGap = () => {
    if (gap && gap.count > 0) rows.push({ kind: "gap", ...gap });
    gap = null;
  };

  for (const k of fullDayWindow) {
    const isAnchored = k === todayKey || k === tomorrowKey || (byDay.get(k)?.length ?? 0) > 0;
    if (isAnchored) {
      flushGap();
      rows.push({ kind: "day", dayKey: k });
    } else {
      if (!gap) gap = { from: k, to: k, count: 0 };
      gap.to = k;
      gap.count += 1;
    }
  }
  flushGap();
  return rows;
}

function tileHeightFor(n: number): number {
  // Match canvas heights: 50 / 82 / 112 / 136+ for 0 / 1 / 2 / 3+ items.
  if (n === 0) return 50;
  if (n === 1) return 82;
  if (n === 2) return 112;
  return 136 + (n - 3) * 24;
}

/* ── formatters ────────────────────────────────────────────────────────── */

function formatTime(it: TimelineItem): string {
  if (it.kind === "event" && it.all_day) return "all-day";
  const d = new Date(it.effective_at);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function weekdayCap(dayKey: string): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  return ["SUN","MON","TUE","WED","THU","FRI","SAT"][new Date(y, m - 1, d).getDay()];
}

function dayOfMonth(dayKey: string): number {
  return Number(dayKey.split("-")[2]);
}

function currentMonthLabel(): string {
  return `${new Date().getMonth() + 1}月`;
}

function addDays(d: Date, delta: number): Date {
  const out = new Date(d); out.setDate(out.getDate() + delta); return out;
}

/* ── Timepage-mode helpers (A overlay / B vertical label / E jump) ──── */

/** Year + 月 label, e.g. "2026 年 5 月". Vertical writing-mode renders it
 *  along the rail. */
function formatYearMonth(dayKey: string): string {
  const [y, m] = dayKey.split("-").map(Number);
  return `${y} 年 ${m} 月`;
}

/** Find the prior visible day-row's dayKey in the rendered rows so we can
 *  detect month boundaries. Walks back skipping gap rows. */
function lookupPrevDayKey(rows: RailRow[], idx: number): string | null {
  for (let i = idx - 1; i >= 0; i--) {
    const r = rows[i];
    if (r.kind === "day") return r.dayKey;
  }
  return null;
}

/** Scroll today's tile to the viewport center. No-op if today isn't
 *  in the rendered window. */
function scrollToToday(container: HTMLDivElement | null, todayKey: string, behavior: ScrollBehavior) {
  if (!container) return;
  const el = container.querySelector<HTMLElement>(`[data-day-key="${todayKey}"]`);
  if (el) el.scrollIntoView({ block: "center", behavior });
}

/** Return the data-day-key of the row whose vertical midpoint sits closest
 *  to the container's vertical midpoint. Used for the A overlay. */
function dayKeyAtViewportCenter(container: HTMLDivElement): string | null {
  const rect = container.getBoundingClientRect();
  const centerY = rect.top + rect.height / 2;
  const rows = container.querySelectorAll<HTMLElement>("[data-day-key]");
  let bestKey: string | null = null;
  let bestDist = Infinity;
  for (const r of rows) {
    const rr = r.getBoundingClientRect();
    const mid = rr.top + rr.height / 2;
    const d = Math.abs(mid - centerY);
    if (d < bestDist) { bestDist = d; bestKey = r.getAttribute("data-day-key"); }
  }
  return bestKey;
}

/** Is today's tile at least partially inside the viewport? Used to gate
 *  the E jump-to-today button visibility. */
function isTodayInViewport(container: HTMLDivElement, todayKey: string): boolean {
  const el = container.querySelector<HTMLElement>(`[data-day-key="${todayKey}"]`);
  if (!el) return true; // not rendered → don't show the button, nothing to jump to
  const cont = container.getBoundingClientRect();
  const tile = el.getBoundingClientRect();
  return tile.bottom > cont.top && tile.top < cont.bottom;
}

/**
 * distanceLabel — Timepage-style "距离 today 多远" text.
 *
 *   0       → 「今天」
 *   ±1      → 「明天」/「昨天」
 *   ±2-±6   → 「N 天后/前」
 *   ±7-±27  → 「N 周后/前」   (rounded)
 *   ±28+    → 「N 月后/前」   (rounded; >= 1 month)
 *   ±365+   → 「N 年后/前」   (rounded)
 */
function distanceLabel(dayKey: string, todayKey: string): string {
  const days = daysBetween(dayKey, todayKey);
  if (days === 0)  return "今天";
  if (days === 1)  return "明天";
  if (days === -1) return "昨天";
  const abs = Math.abs(days);
  const suffix = days > 0 ? "后" : "前";
  if (abs < 7)   return `${abs} 天${suffix}`;
  if (abs < 28)  return `${Math.round(abs / 7)} 周${suffix}`;
  if (abs < 365) return `${Math.round(abs / 30)} 月${suffix}`;
  return `${Math.round(abs / 365)} 年${suffix}`;
}

function daysBetween(a: string, b: string): number {
  const [ya, ma, da] = a.split("-").map(Number);
  const [yb, mb, db] = b.split("-").map(Number);
  const ms = Date.UTC(ya, ma - 1, da) - Date.UTC(yb, mb - 1, db);
  return Math.round(ms / 86_400_000);
}

/* ── re-export — DayDetailSheet still uses TimelineRow shape for now ──── */

/**
 * Legacy export kept for DayDetailSheet's import compatibility. The new
 * DayDetailSheet (M3-redo) doesn't use this; once it's rewritten the
 * export can be removed.
 */
export function TimelineRow({
  item, onTap,
}: { item: TimelineItem; onTap: () => void }) {
  const time = formatTime(item);
  const accent = subKindOf(item) ?? "neutral";
  const rowStyle: CSSProperties = { cursor: "pointer" };
  return (
    <button
      type="button"
      onClick={onTap}
      className="w-full flex items-center gap-eu-md px-eu-md py-eu-sm rounded-eu-md border border-transparent hover:border-eu-border hover:bg-eu-surface-hover text-left"
      style={rowStyle}
    >
      <span className="font-mono" style={{ fontSize: 11, minWidth: 44, color: ACCENT_DOT[accent] }}>{time}</span>
      <span className="shrink-0 h-2 w-2 rounded-full" style={{ background: ACCENT_DOT[accent] }} />
      <span className="flex-1 truncate text-eu-base text-eu-text-hi">{item.title}</span>
    </button>
  );
}
