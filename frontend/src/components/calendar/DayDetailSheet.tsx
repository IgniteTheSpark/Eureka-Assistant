import { useMemo, useRef, useState, useEffect } from "react";
import { ArrowLeft, CalendarClock, List } from "lucide-react";

import { EventCard } from "@/components/calendar/EventCard";
import { SkillCard } from "@/components/skill/SkillCard";
import { useModalMount } from "@/context/ModalContext";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useTimeline } from "@/hooks/useTimeline";
import { useToggleTodo } from "@/hooks/useToggleTodo";
import { buildCard } from "@/lib/render-spec";
import type { TimelineItem } from "@/lib/types";

/**
 * DayDetailSheet — hour-grid day view (TP2-J refactor).
 *
 * Replaces the M3-redo grouped-list (事件 / 待办 / 今日捕捉 / 来源 玻璃卡)
 * with a Timepage-style hour grid: 24 hour rows, each event absolute-
 * positioned over the slots it covers, all-day events as a chip row above
 * the grid. Eureka-specific captures (idea / expense / contact / notes
 * — assets without a time anchor) live in a small section BELOW the grid
 * so they aren't lost.
 *
 *   ┌──────────────────────────────────────┐
 *   │ 星期一 · 8 天 之前 · 5月18日          │  top header
 *   ├──────────────────────────────────────┤
 *   │ 全天 [Memorial Day]  [Public Holiday] │  all-day chip row
 *   ├─────┬────────────────────────────────┤
 *   │ 上午 │                                │  hour grid:
 *   │ 8时 │                                │  - left rail = "上午/下午 N 时"
 *   │ 9时 │ ┌───────────────────────────┐ │  - right column = event blocks
 *   │     │ │ 10:00 — 11:00              │ │    absolute-positioned by
 *   │ 10时 │ │ 产品评审 · Eureka v2      │ │    start/end_at, color = purple
 *   │ 11时 │ └───────────────────────────┘ │    (event accent)
 *   │ 下午 │                                │  - "now" red line on today
 *   │ 12时 │                                │
 *   │ ...  │                                │
 *   ├─────┴────────────────────────────────┤
 *   │ 今日捕捉                              │  Eureka-only section below
 *   │ [◇ IDEA  …]  [¥ EXPENSE  …]          │  (skill cards for time-less
 *   │                                        │   assets created that day)
 *   ├──────────────────────────────────────┤
 *   │ [←]                            [+]   │  bottom toolbar (K)
 *   └──────────────────────────────────────┘
 *
 * Hour-row height fixed at 56px for legibility; an event spanning 10:00 →
 * 11:00 covers exactly one row, 10:30 → 11:00 covers half, etc. Events
 * that start before 8 AM or end after 10 PM clip to grid edges with a ▲/▼
 * visual hint (TODO).
 */

const GRID_START_HOUR = 0;   // start the grid at midnight so cross-day fits
const GRID_END_HOUR   = 24;  // exclusive — last row shown is 23 时
const HOUR_HEIGHT     = 56;

interface DayDetailSheetProps {
  dayKey: string;
  onClose: () => void;
  onItemTap: (item: TimelineItem) => void;
}

export function DayDetailSheet({
  dayKey, onClose, onItemTap,
}: DayDetailSheetProps) {
  // OP10: keep the floating dock visible over DayDetail (it's a page-like
  // view, not a transient picker). The dock's + is the single create
  // entry — DayDetail no longer has its own top-right + (OP-fix #3).
  useModalMount({ keepDock: true });
  const { byDay } = useTimeline();
  const items = byDay.get(dayKey) ?? [];

  // Bucket into all-day events / timed events (event w/ start_at) / captured
  // (anything else — idea / expense / contact / notes / todo without time).
  const { allDay, timed, captured } = useMemo(() => bucket(items), [items]);

  // View toggle (per design chat2 #4): the day view DEFAULTS to a flat LIST
  // of every asset that day (events + todos + ideas + notes + expenses —
  // including non-time captures the hour grid can't surface), and a 日程
  // toggle flips to the Timepage-style hour-grid timeline.
  const [view, setView] = useState<"list" | "schedule">("list");
  const listItems = useMemo(
    () => [...items].sort((a, b) => a.effective_at.localeCompare(b.effective_at)),
    [items],
  );

  // Auto-scroll anchor: prefer "couple hours before earliest event" so we
  // don't hide events above the fold. Fallback: a few hours before now
  // (today) / 7 AM (other days). Never push past the earliest event.
  const gridRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (!gridRef.current) return;
    const today = new Date();
    const isToday = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,"0")}-${String(today.getDate()).padStart(2,"0")}` === dayKey;
    const firstEventHour = timed.length > 0
      ? new Date(timed[0].effective_at).getHours()
      : null;
    const fallback = isToday ? Math.max(7, today.getHours() - 2) : 7;
    const anchorHour = firstEventHour != null
      ? Math.max(0, Math.min(fallback, firstEventHour - 1))
      : fallback;
    gridRef.current.scrollTop = (anchorHour - GRID_START_HOUR) * HOUR_HEIGHT;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dayKey, timed.length, view]);

  return (
    <div
      className="fixed inset-0 z-50"
      style={{ background: "rgba(6,7,13,0.75)", backdropFilter: "blur(8px)" }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="fixed flex flex-col overflow-hidden"
        style={{
          inset: 0,
          background: "linear-gradient(180deg, #1f3a7a 0%, #131f48 100%)",
          color: "#ffffff",
          fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
        }}
      >
        {/* ── Header: ← / weekday + date / +  (OP7: top toolbar) ──── */}
        <header
          className="shrink-0 flex items-center"
          style={{ padding: "16px 16px 12px", gap: 12 }}
        >
          <button
            type="button"
            onClick={onClose}
            aria-label="返回"
            className="shrink-0"
            style={{
              width: 36, height: 36, borderRadius: 999,
              background: "rgba(255,255,255,0.10)",
              border: "1px solid rgba(255,255,255,0.18)",
              color: "#fff", fontSize: 16, cursor: "pointer",
              display: "flex", alignItems: "center", justifyContent: "center",
            }}
          >
            <ArrowLeft size={16} strokeWidth={2} />
          </button>
          <div className="flex-1 min-w-0">
            <div
              className="font-display"
              style={{
                fontSize: 22, fontWeight: 700, letterSpacing: "0.04em",
                color: "#ffffff",
                textShadow: "0 0 24px rgba(255,255,255,0.30)",
              }}
            >
              {weekdayLabel(dayKey)}
            </div>
            <div
              className="font-mono mt-0.5"
              style={{
                fontSize: 11, color: "rgba(255,255,255,0.70)",
                letterSpacing: "0.18em",
              }}
            >
              {distanceLabel(dayKey)} · {monthDayCaps(dayKey)}
            </div>
          </div>
          {/* 日程 toggle — flips between the default LIST view and the
              hour-grid timeline. (OP-fix #3: the create "+" lives on the
              persistent dock now, so the only top-right control is this.) */}
          <button
            type="button"
            onClick={() => setView((v) => (v === "list" ? "schedule" : "list"))}
            aria-pressed={view === "schedule"}
            className="shrink-0 inline-flex items-center gap-1.5 active:scale-[0.97]"
            style={{
              height: 36, padding: "0 13px", borderRadius: 999,
              background: view === "schedule"
                ? "rgba(196,168,255,0.22)"
                : "rgba(255,255,255,0.10)",
              border: `1px solid ${view === "schedule"
                ? "rgba(196,168,255,0.45)"
                : "rgba(255,255,255,0.18)"}`,
              color: "#fff", fontSize: 12.5, fontWeight: 600,
              letterSpacing: "0.02em", cursor: "pointer",
              transition: "all 180ms cubic-bezier(.2,.7,.3,1)",
            }}
          >
            {view === "schedule"
              ? <List size={14} strokeWidth={2} />
              : <CalendarClock size={14} strokeWidth={2} />}
            {view === "schedule" ? "列表" : "日程"}
          </button>
        </header>

        {/* ── LIST view (default) — every asset that day, chronological ── */}
        {view === "list" && (
          <div
            className="flex-1 overflow-y-auto eu-noscroll"
            style={{ padding: "4px 16px 24px" }}
          >
            {listItems.length === 0 ? (
              <div
                className="text-center"
                style={{
                  marginTop: 96, color: "rgba(255,255,255,0.55)",
                  fontSize: 14, fontStyle: "italic",
                }}
              >
                这一天什么都没有
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                {listItems.map((it) => (
                  <CapturedCard
                    key={`${it.kind}-${it.id}`}
                    item={it}
                    onClick={() => onItemTap(it)}
                  />
                ))}
              </div>
            )}
          </div>
        )}

        {/* ── SCHEDULE view (toggle on) — all-day chips + 今日捕捉 + hour grid ── */}
        {view === "schedule" && (
        <>
        {/* ── All-day chip row (only when present) ─────────────────── */}
        {allDay.length > 0 && (
          <div
            className="shrink-0 flex items-center gap-2"
            style={{
              padding: "8px 20px 14px",
              borderBottom: "1px solid rgba(255,255,255,0.08)",
            }}
          >
            <span
              className="font-mono shrink-0"
              style={{
                fontSize: 10, letterSpacing: "0.22em",
                color: "rgba(255,255,255,0.50)", fontWeight: 600,
              }}
            >
              全天
            </span>
            <div className="flex-1 flex flex-wrap gap-1.5">
              {allDay.map((it) => (
                <AllDayChip
                  key={`${it.kind}-${it.id}`}
                  item={it}
                  onClick={() => onItemTap(it)}
                />
              ))}
            </div>
          </div>
        )}

        {/* ── 今日捕捉 (OP6 above-grid + #4 tabbed fixed-height). Renders
            idea / expense / contact / notes — assets without a time anchor.
            Tabs by type so a card-heavy day doesn't push the hour grid
            infinitely down; container capped to ~3 cards, scrolls inside. */}
        {captured.length > 0 && (
          <CapturedSection items={captured} onItemTap={onItemTap} />
        )}

        {/* ── Hour grid (scrollable) ─────────────────────────────── */}
        <div
          ref={gridRef}
          className="flex-1 overflow-y-auto eu-noscroll relative"
        >
          <div
            className="relative"
            style={{
              height: (GRID_END_HOUR - GRID_START_HOUR) * HOUR_HEIGHT,
            }}
          >
            {/* Hour rows */}
            {Array.from({ length: GRID_END_HOUR - GRID_START_HOUR }).map((_, i) => {
              const hour = GRID_START_HOUR + i;
              return (
                <div
                  key={hour}
                  className="absolute left-0 right-0 flex items-start"
                  style={{
                    top: i * HOUR_HEIGHT,
                    height: HOUR_HEIGHT,
                    borderTop: i > 0 ? "1px solid rgba(255,255,255,0.06)" : "none",
                  }}
                >
                  <span
                    className="font-mono shrink-0 text-right"
                    style={{
                      width: 64, paddingRight: 10, paddingTop: 4,
                      fontSize: 10.5, color: "rgba(255,255,255,0.55)",
                      letterSpacing: "0.06em",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {hourLabel(hour)}
                  </span>
                </div>
              );
            })}

            {/* Timed events — absolute-positioned over the grid */}
            {timed.map((it) => {
              const block = computeBlock(it);
              if (!block) return null;
              return (
                <button
                  key={`${it.kind}-${it.id}`}
                  type="button"
                  onClick={() => onItemTap(it)}
                  className="absolute text-left active:scale-[0.99] overflow-hidden"
                  style={{
                    top: block.top, height: block.height,
                    left: 70, right: 14,
                    background: "linear-gradient(135deg, rgba(196,168,255,0.55) 0%, rgba(156,128,240,0.40) 100%)",
                    borderLeft: "3px solid #c4a8ff",
                    borderRadius: 10,
                    padding: "6px 12px",
                    cursor: "pointer",
                    transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
                  }}
                >
                  {/* Title is the headline — the block's vertical position on the
                      hour grid already conveys the time, so we don't repeat it
                      in the card. Clamp to 2 lines (a short block height clips to
                      one) so the text leads and never overflows. */}
                  <div
                    className="line-clamp-2"
                    style={{
                      fontSize: 13, fontWeight: 600, color: "#ffffff",
                      letterSpacing: "-0.005em", lineHeight: 1.3,
                    }}
                  >
                    {it.title}
                  </div>
                  {it.location && block.height > 56 && (
                    <div
                      className="line-clamp-1"
                      style={{
                        fontSize: 11, color: "rgba(255,255,255,0.72)",
                        marginTop: 2,
                      }}
                    >
                      {it.location}
                    </div>
                  )}
                </button>
              );
            })}

            {/* "now" line — only on today */}
            <NowLine dayKey={dayKey} />
          </div>

          {items.length === 0 && (
            <div
              className="absolute inset-x-0 text-center"
              style={{
                top: HOUR_HEIGHT * 8 + 80,
                color: "rgba(255,255,255,0.55)", fontSize: 14,
                fontStyle: "italic",
              }}
            >
              这一天什么都没有
            </div>
          )}
        </div>
        </>
        )}
      </div>
    </div>
  );
}

/* ── Bucket logic ─────────────────────────────────────────────────── */

function bucket(items: TimelineItem[]) {
  const allDay:   TimelineItem[] = [];
  const timed:    TimelineItem[] = [];
  const captured: TimelineItem[] = [];
  for (const it of items) {
    if (it.kind === "event") {
      if (it.all_day) allDay.push(it);
      else            timed.push(it);
    } else if (it.skill_name === "todo") {
      // typed todo: if it has a time-of-day on effective_at use timed
      // (deadline rendered as a thin marker), else captured. Heuristic:
      // we don't have a separate "has time" flag, but typed dispatch
      // produces todos with 09:00 default for no-time, which is OK to
      // show on the grid.
      timed.push(it);
    } else {
      captured.push(it);
    }
  }
  // Sort timed by start so they don't overlap visually when stacked.
  timed.sort((a, b) => a.effective_at.localeCompare(b.effective_at));
  return { allDay, timed, captured };
}

/* ── Hour-grid block math ─────────────────────────────────────────── */

interface Block { top: number; height: number; }
function computeBlock(it: TimelineItem): Block | null {
  const start = new Date(it.effective_at);
  const startMin = start.getHours() * 60 + start.getMinutes();
  let endMin: number;
  if (it.end_at) {
    const end = new Date(it.end_at);
    endMin = end.getHours() * 60 + end.getMinutes();
    if (endMin <= startMin) endMin = startMin + 30; // safety
  } else {
    endMin = startMin + 30; // todo / single-point: 30-min visual block
  }
  const minPerPx = 60 / HOUR_HEIGHT;
  const clampedStart = Math.max(GRID_START_HOUR * 60, startMin);
  const clampedEnd   = Math.min(GRID_END_HOUR * 60,   endMin);
  if (clampedEnd <= clampedStart) return null;
  return {
    top:    (clampedStart - GRID_START_HOUR * 60) / minPerPx,
    height: (clampedEnd - clampedStart) / minPerPx,
  };
}

/* ── Sub-renders ──────────────────────────────────────────────────── */

function AllDayChip({ item, onClick }: { item: TimelineItem; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex items-center gap-1.5"
      style={{
        padding: "5px 10px", borderRadius: 999,
        background: "rgba(196,168,255,0.20)",
        border: "1px solid rgba(196,168,255,0.40)",
        color: "#ffffff", fontSize: 12,
        cursor: "pointer", maxWidth: 220,
      }}
      title={item.title}
    >
      <span style={{
        width: 5, height: 5, borderRadius: 999, background: "#c4a8ff",
        boxShadow: "0 0 5px rgba(196,168,255,0.6)",
      }} />
      <span
        style={{
          overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
        }}
      >
        {item.title}
      </span>
    </button>
  );
}

/**
 * CapturedSection — #4: tabbed, fixed-height 今日捕捉.
 *
 * Groups the day's time-less assets by skill type into tabs. The card
 * container is capped to ~3 cards tall and scrolls internally, so a day
 * with many captures no longer pushes the hour grid down indefinitely.
 * When only one type exists, the tab row collapses to a single label.
 */
const CAPTURE_LABELS: Record<string, string> = {
  idea: "想法", expense: "记账", contact: "名片", notes: "笔记",
  todo: "待办", misc: "其它",
};

function CapturedSection({
  items, onItemTap,
}: { items: TimelineItem[]; onItemTap: (it: TimelineItem) => void }) {
  // Distinct types present, in a stable order.
  const types = useMemo(() => {
    const seen: string[] = [];
    for (const it of items) {
      const k = it.skill_name ?? "misc";
      if (!seen.includes(k)) seen.push(k);
    }
    return seen;
  }, [items]);

  const [active, setActive] = useState<string>(types[0] ?? "misc");
  // Keep active valid if the day's types change.
  const activeType = types.includes(active) ? active : (types[0] ?? "misc");
  const shown = items.filter((it) => (it.skill_name ?? "misc") === activeType);

  return (
    <div
      className="shrink-0"
      style={{ padding: "10px 20px 14px", borderBottom: "1px solid rgba(255,255,255,0.08)" }}
    >
      <div className="flex items-center justify-between mb-2">
        <span
          className="font-mono"
          style={{ fontSize: 10, letterSpacing: "0.22em", color: "rgba(255,255,255,0.50)", fontWeight: 600 }}
        >
          今日捕捉
        </span>
        {/* Tab row — only when >1 type */}
        {types.length > 1 && (
          <div className="flex items-center gap-1 overflow-x-auto eu-noscroll">
            {types.map((t) => {
              const isActive = t === activeType;
              const count = items.filter((it) => (it.skill_name ?? "misc") === t).length;
              return (
                <button
                  key={t}
                  type="button"
                  onClick={() => setActive(t)}
                  className="font-mono shrink-0"
                  style={{
                    fontSize: 10.5, padding: "3px 9px", borderRadius: 999,
                    letterSpacing: "0.04em",
                    background: isActive ? "rgba(255,255,255,0.16)" : "rgba(255,255,255,0.05)",
                    color: isActive ? "#fff" : "rgba(255,255,255,0.55)",
                    border: `1px solid ${isActive ? "rgba(255,255,255,0.24)" : "transparent"}`,
                    cursor: "pointer", whiteSpace: "nowrap",
                  }}
                >
                  {CAPTURE_LABELS[t] ?? t} {count}
                </button>
              );
            })}
          </div>
        )}
      </div>
      {/* Fixed ~3-card container; scrolls inside. 1 card ≈ 60px + gap. */}
      <div
        className="flex flex-col gap-1.5 overflow-y-auto eu-noscroll"
        style={{ maxHeight: 204 }}
      >
        {shown.map((it) => (
          <CapturedCard
            key={`${it.kind}-${it.id}`}
            item={it}
            onClick={() => onItemTap(it)}
          />
        ))}
      </div>
    </div>
  );
}

function CapturedCard({ item, onClick }: { item: TimelineItem; onClick: () => void }) {
  // OP2: route ALL non-event captured items through the universal SkillCard
  // so DayDetail's 今日捕捉 visual matches Library Recent / Chat tool_result
  // exactly (same icon block, same title/subtitle/meta layout, same hover
  // affordances, todo checkbox auto-enabled when spec includes "check").
  const { bySkill } = useSkillRegistry();
  const toggleTodo = useToggleTodo();

  if (item.kind === "event") {
    return (
      <EventCard
        event={{
          event_id: item.event_id ?? item.id,
          title: item.title,
          start_at: item.effective_at,
          end_at:   item.end_at,
          all_day:  item.all_day,
          location: item.location,
        }}
        onClick={onClick}
      />
    );
  }

  const skillName = item.skill_name ?? "asset";
  const skill = bySkill.get(skillName);
  const card = buildCard({
    payload: (item.payload as Record<string, unknown>) ?? { title: item.title },
    spec:    skill?.render_spec ?? null,
    assetId: item.id,
    cardType: skillName,
    displayName: skill?.display_name ?? item.title,
  });
  return (
    <SkillCard
      data={card}
      onClick={onClick}
      onToggleCheck={card.checkDone !== undefined
        ? (next) => toggleTodo(item.id, next)
        : undefined}
    />
  );
}

function NowLine({ dayKey }: { dayKey: string }) {
  const today = new Date();
  const todayKey = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,"0")}-${String(today.getDate()).padStart(2,"0")}`;
  if (dayKey !== todayKey) return null;
  const nowMin = today.getHours() * 60 + today.getMinutes();
  const top = ((nowMin - GRID_START_HOUR * 60) / 60) * HOUR_HEIGHT;
  return (
    <div
      className="absolute left-0 right-0 pointer-events-none"
      style={{ top, height: 2 }}
    >
      <div
        style={{
          height: 2, background: "#ec6a83",
          boxShadow: "0 0 8px rgba(236,106,131,0.7)",
        }}
      />
      <div
        style={{
          position: "absolute", left: 56, top: -4,
          width: 10, height: 10, borderRadius: 999,
          background: "#ec6a83",
          boxShadow: "0 0 8px rgba(236,106,131,0.8)",
        }}
      />
    </div>
  );
}

/* ── Formatters ───────────────────────────────────────────────────── */

function hourLabel(hour: number): string {
  if (hour === 0)  return "午夜";
  if (hour === 12) return "中午 12时";
  if (hour < 12)   return `上午 ${hour}时`;
  return `下午 ${hour - 12}时`;
}

function weekdayLabel(dayKey: string): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  return ["星期日","星期一","星期二","星期三","星期四","星期五","星期六"][new Date(y, m - 1, d).getDay()];
}

function monthDayCaps(dayKey: string): string {
  const [, m, d] = dayKey.split("-").map(Number);
  return `${m}月${d}日`;
}

/** Same distance-from-today helper as ScheduleView. */
function distanceLabel(dayKey: string): string {
  const today = new Date(); today.setHours(0,0,0,0);
  const todayKey = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,"0")}-${String(today.getDate()).padStart(2,"0")}`;
  const [ya, ma, da] = dayKey.split("-").map(Number);
  const [yb, mb, db] = todayKey.split("-").map(Number);
  const days = Math.round(
    (Date.UTC(ya, ma - 1, da) - Date.UTC(yb, mb - 1, db)) / 86_400_000,
  );
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
