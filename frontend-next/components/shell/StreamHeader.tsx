"use client";

import { useState } from "react";

// ── helpers ────────────────────────────────────────────────────────────────────

function localDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

// ── Month Calendar Panel ───────────────────────────────────────────────────────

const HEAT_OPACITY: Record<number, number> = { 0: 0, 1: 0.35, 2: 0.65, 3: 1 };

function MonthCalPanel({
  heatMap,
  viewYear,
  viewMonth,
  onPrevMonth,
  onNextMonth,
  onDayClick,
}: {
  heatMap: Map<string, number>;
  viewYear: number;
  viewMonth: number; // 0-indexed
  onPrevMonth: () => void;
  onNextMonth: () => void;
  onDayClick: (dateStr: string) => void;
}) {
  const todayStr = localDateStr(new Date());
  const monthLabel = `${viewYear}年${viewMonth + 1}月`;

  const firstDOW = (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7; // Mon=0
  const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();

  const cells: (number | null)[] = [
    ...Array(firstDOW).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ];
  while (cells.length % 7 !== 0) cells.push(null);

  function heatLevel(day: number): 0 | 1 | 2 | 3 {
    const ds = `${viewYear}-${String(viewMonth + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    const n = heatMap.get(ds) ?? 0;
    if (n === 0) return 0;
    if (n <= 2) return 1;
    if (n <= 5) return 2;
    return 3;
  }

  function isTodayFn(day: number): boolean {
    const ds = `${viewYear}-${String(viewMonth + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    return ds === todayStr;
  }

  return (
    <div style={{
      padding: "10px 14px 14px",
      background: "var(--surface)",
      borderBottom: "1px solid var(--border)",
    }}>
      {/* Month navigation */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "10px" }}>
        <button
          onClick={onPrevMonth}
          style={{
            width: "28px", height: "28px", borderRadius: "50%",
            border: "1px solid var(--border)", background: "var(--surface2)",
            fontSize: "16px", cursor: "pointer", color: "var(--text2)",
            display: "grid", placeItems: "center",
          }}
        >‹</button>
        <span style={{ fontSize: "12px", fontWeight: 700, color: "var(--text)", letterSpacing: "-0.01em" }}>
          {monthLabel}
        </span>
        <button
          onClick={onNextMonth}
          style={{
            width: "28px", height: "28px", borderRadius: "50%",
            border: "1px solid var(--border)", background: "var(--surface2)",
            fontSize: "16px", cursor: "pointer", color: "var(--text2)",
            display: "grid", placeItems: "center",
          }}
        >›</button>
      </div>

      {/* DOW header row */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", marginBottom: "4px" }}>
        {["一", "二", "三", "四", "五", "六", "日"].map(d => (
          <div
            key={d}
            style={{ textAlign: "center", fontSize: "9px", fontWeight: 700, color: "var(--text3)", padding: "2px 0" }}
          >{d}</div>
        ))}
      </div>

      {/* Day cells */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: "2px" }}>
        {cells.map((day, i) => {
          if (!day) return <div key={`empty-${i}`} style={{ height: "34px" }} />;

          const isToday = isTodayFn(day);
          const heat = heatLevel(day);
          const ds = `${viewYear}-${String(viewMonth + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;

          return (
            <div
              key={day}
              onClick={() => onDayClick(ds)}
              style={{
                display: "flex", flexDirection: "column", alignItems: "center",
                justifyContent: "center",
                height: "34px", borderRadius: "8px", cursor: "pointer",
                background: isToday ? "var(--blue)" : "transparent",
              }}
            >
              <span style={{
                fontSize: "12px",
                fontWeight: isToday ? 800 : 500,
                color: isToday ? "#fff" : "var(--text2)",
                lineHeight: 1,
              }}>{day}</span>
              {heat > 0 && (
                <div style={{
                  width: "4px", height: "4px", borderRadius: "50%",
                  marginTop: "2px",
                  background: isToday ? "rgba(255,255,255,0.75)" : "var(--blue)",
                  opacity: isToday ? 1 : HEAT_OPACITY[heat],
                }} />
              )}
              {heat === 0 && (
                <div style={{ width: "4px", height: "4px", marginTop: "2px" }} />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── StreamHeader ───────────────────────────────────────────────────────────────

interface StreamHeaderProps {
  isCalOpen: boolean;
  onToggleCal: () => void;
  heatMap: Map<string, number>;
  onDayClick: (dateStr: string) => void;
}

export default function StreamHeader({
  isCalOpen,
  onToggleCal,
  heatMap,
  onDayClick,
}: StreamHeaderProps) {
  const now = new Date();
  const [viewYear, setViewYear] = useState(now.getFullYear());
  const [viewMonth, setViewMonth] = useState(now.getMonth()); // 0-indexed

  const monthLabel = `${now.getMonth() + 1}月 ${now.getFullYear()}`;

  function prevMonth() {
    if (viewMonth === 0) { setViewMonth(11); setViewYear(y => y - 1); }
    else setViewMonth(m => m - 1);
  }
  function nextMonth() {
    if (viewMonth === 11) { setViewMonth(0); setViewYear(y => y + 1); }
    else setViewMonth(m => m + 1);
  }

  return (
    <>
      {/* Header row */}
      <div style={{
        display: "grid",
        gridTemplateColumns: "1fr auto 1fr",
        alignItems: "center",
        padding: "10px 12px 8px",
        flexShrink: 0,
        background: "var(--surface)",
        borderBottom: isCalOpen ? "none" : "1px solid var(--border)",
        gap: "6px",
      }}>
        {/* Left: avatar + wordmark */}
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <div style={{
            width: "30px", height: "30px", borderRadius: "50%",
            background: "var(--blue10)", border: "2px solid var(--blue)",
            display: "grid", placeItems: "center",
            fontSize: "12px", fontWeight: 700, color: "var(--blue)",
            flexShrink: 0, cursor: "pointer",
          }}>我</div>
          <span style={{ fontSize: "16px", fontWeight: 800, letterSpacing: "-0.03em", color: "var(--text)" }}>
            <span style={{
              background: "var(--grad)",
              WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent", backgroundClip: "text",
            }}>Eureka</span>
            {" "}
            <em style={{ fontStyle: "normal", fontSize: "12px", fontWeight: 700, color: "var(--text3)" }}>3.0</em>
          </span>
        </div>

        {/* Center: month toggle */}
        <button
          onClick={onToggleCal}
          style={{
            display: "flex", alignItems: "center", gap: "4px",
            padding: "5px 12px", borderRadius: "999px",
            background: isCalOpen ? "var(--blue10)" : "var(--surface2)",
            border: `1px solid ${isCalOpen ? "var(--blue)" : "var(--border)"}`,
            fontSize: "12px", fontWeight: 700,
            color: isCalOpen ? "var(--blue)" : "var(--text2)",
            cursor: "pointer", whiteSpace: "nowrap", letterSpacing: "-0.01em",
            transition: "all 0.18s ease",
          }}
          title="切换月历"
        >
          {monthLabel}
          <span style={{
            fontSize: "10px", color: isCalOpen ? "var(--blue)" : "var(--text3)",
            display: "inline-block",
            transform: isCalOpen ? "rotate(180deg)" : "none",
            transition: "transform 0.18s ease",
          }}>▾</span>
        </button>

        {/* Right: hw chip + search */}
        <div style={{ display: "flex", alignItems: "center", gap: "6px", justifyContent: "flex-end" }}>
          <div style={{
            display: "flex", alignItems: "center", gap: "4px",
            padding: "4px 8px", borderRadius: "999px",
            background: "var(--surface2)", border: "1px solid var(--border)",
            fontSize: "10px", fontWeight: 600, color: "var(--text2)", whiteSpace: "nowrap",
          }}>
            <span style={{
              width: "6px", height: "6px", borderRadius: "50%",
              background: "var(--green)", flexShrink: 0, display: "inline-block",
            }} />
            已连接
          </div>
          <button
            style={{
              width: "30px", height: "30px", borderRadius: "50%",
              background: "var(--surface2)", border: "1px solid var(--border)",
              display: "grid", placeItems: "center",
              fontSize: "15px", cursor: "pointer",
            }}
            title="搜索"
          >🔍</button>
        </div>
      </div>

      {/* Calendar panel (conditional) */}
      {isCalOpen && (
        <MonthCalPanel
          heatMap={heatMap}
          viewYear={viewYear}
          viewMonth={viewMonth}
          onPrevMonth={prevMonth}
          onNextMonth={nextMonth}
          onDayClick={(ds) => {
            onDayClick(ds);
            onToggleCal(); // close after picking
          }}
        />
      )}
    </>
  );
}
