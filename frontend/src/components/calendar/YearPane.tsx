import { useMemo, useState } from "react";

import { useTimeline, toLocalDayKey } from "@/hooks/useTimeline";

/**
 * YearPane — SW: the third swipe-deck pane. 12 mini-month grids in a 3-col
 * layout (mirrors design-system §5.4 / canvas CalYear). Days with any
 * timeline item are dotted; today is a filled white circle. Tapping a month
 * calls onPickMonth(monthKey) → CalendarPage swipes to the Month pane and
 * scrolls it to that month.
 *
 * A year stepper (‹ 2026 ›) lets the user move across years without needing
 * the Month pane.
 */

interface YearPaneProps {
  /** Initial year to show (defaults to current). */
  initialYear?: number;
  onPickMonth: (monthKey: string) => void; // "YYYY-MM"
}

const MONTH_NAMES = ["1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"];

export function YearPane({ initialYear, onPickMonth }: YearPaneProps) {
  const { byDay } = useTimeline();
  const [year, setYear] = useState(initialYear ?? new Date().getFullYear());
  const todayKey = toLocalDayKey(new Date().toISOString());

  // Precompute which day-keys in this year have any items (for dotting).
  const activeDays = useMemo(() => {
    const set = new Set<string>();
    for (const [k, items] of byDay.entries()) {
      if (k.startsWith(`${year}-`) && items.length > 0) set.add(k);
    }
    return set;
  }, [byDay, year]);

  return (
    <div
      className="flex flex-col h-full"
      style={{
        background: "#06070d",
        color: "#d4dbe6",
        fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      }}
    >
      {/* Header: ‹ year › — borderless + tight top padding so switching to the
          年 tab matches the headerless 流/月 panes' rhythm under the Segmented
          control (the year stepper stays — it's the only year-nav affordance). */}
      <header
        className="shrink-0 flex items-center gap-3"
        style={{ padding: "6px 20px 12px" }}
      >
        <YearStep dir="-" onClick={() => setYear((y) => y - 1)} />
        <div
          className="font-display"
          style={{
            fontSize: 30, fontWeight: 700, color: "#a4c2ff",
            letterSpacing: "-0.02em", textShadow: "0 0 20px rgba(111,158,255,0.45)",
            lineHeight: 1,
          }}
        >
          {year}
        </div>
        <YearStep dir="+" onClick={() => setYear((y) => y + 1)} />
        <span
          className="font-mono ml-auto"
          style={{ fontSize: 10, letterSpacing: "0.18em", color: "rgba(255,255,255,0.35)" }}
        >
          {activeDays.size} DAYS
        </span>
      </header>

      {/* 12 mini months */}
      <div
        className="flex-1 overflow-y-auto eu-noscroll grid"
        style={{ gridTemplateColumns: "repeat(3, 1fr)", gap: 14, padding: "14px 16px 20px", alignContent: "start" }}
      >
        {MONTH_NAMES.map((name, mi) => (
          <MiniMonth
            key={mi}
            year={year}
            monthIndex={mi}
            label={name}
            activeDays={activeDays}
            todayKey={todayKey}
            onClick={() => onPickMonth(`${year}-${String(mi + 1).padStart(2, "0")}`)}
          />
        ))}
      </div>
    </div>
  );
}

function YearStep({ dir, onClick }: { dir: "+" | "-"; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={dir === "-" ? "上一年" : "下一年"}
      className="font-mono"
      style={{
        width: 28, height: 28, borderRadius: 999,
        background: "rgba(255,255,255,0.04)", border: "1px solid rgba(255,255,255,0.08)",
        color: "rgba(255,255,255,0.7)", fontSize: 14, cursor: "pointer",
        display: "flex", alignItems: "center", justifyContent: "center",
      }}
    >
      {dir === "-" ? "‹" : "›"}
    </button>
  );
}

function MiniMonth({
  year, monthIndex, label, activeDays, todayKey, onClick,
}: {
  year: number;
  monthIndex: number;
  label: string;
  activeDays: Set<string>;
  todayKey: string;
  onClick: () => void;
}) {
  const isCurrentMonth = todayKey.startsWith(`${year}-${String(monthIndex + 1).padStart(2, "0")}`);
  // 6×7 day cells (leading blanks for the 1st's weekday).
  const cells = useMemo(() => {
    const first = new Date(year, monthIndex, 1);
    const lead = first.getDay();
    const daysInMonth = new Date(year, monthIndex + 1, 0).getDate();
    const out: (number | null)[] = [];
    for (let i = 0; i < lead; i++) out.push(null);
    for (let d = 1; d <= daysInMonth; d++) out.push(d);
    while (out.length % 7 !== 0) out.push(null);
    return out;
  }, [year, monthIndex]);

  return (
    <button
      type="button"
      onClick={onClick}
      className="flex flex-col text-left active:scale-95"
      style={{
        gap: 6, padding: "8px 6px", borderRadius: 8,
        background: isCurrentMonth ? "rgba(156,128,240,0.06)" : "transparent",
        border: `1px solid ${isCurrentMonth ? "rgba(196,168,255,0.20)" : "transparent"}`,
        cursor: "pointer",
        transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
      }}
    >
      <div
        className="font-display"
        style={{
          fontSize: 12, fontWeight: 700,
          color: isCurrentMonth ? "#a4c2ff" : "rgba(255,255,255,0.7)",
          letterSpacing: "0.02em",
          textShadow: isCurrentMonth ? "0 0 8px rgba(111,158,255,0.4)" : "none",
        }}
      >
        {label}
      </div>
      <div className="grid" style={{ gridTemplateColumns: "repeat(7, 1fr)", gap: 1.5 }}>
        {cells.map((d, i) => {
          if (d == null) return <span key={i} style={{ height: 11 }} />;
          const key = `${year}-${String(monthIndex + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
          const isToday = key === todayKey;
          const active = activeDays.has(key);
          return (
            <div
              key={i}
              className="font-mono"
              style={{
                height: 11, display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 8.5, letterSpacing: "0.02em",
                borderRadius: 999,
                color: isToday ? "#1a1735" : active ? "#c4a8ff" : "rgba(255,255,255,0.42)",
                background: isToday ? "#ffffff" : "transparent",
                fontWeight: isToday || active ? 700 : 400,
              }}
            >
              {d}
            </div>
          );
        })}
      </div>
    </button>
  );
}
