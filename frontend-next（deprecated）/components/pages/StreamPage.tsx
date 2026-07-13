"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import { useNav } from "@/context/NavContext";
import { useStream } from "@/hooks/useStream";
import { api } from "@/lib/api";
import StreamHeader from "@/components/shell/StreamHeader";
import TabBar, { type StreamTab } from "@/components/shell/TabBar";
import type { Asset, StreamView } from "@/lib/types";

// ── Helpers ───────────────────────────────────────────────────────────────────

function localDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
}
function assetDateStr(iso: string): string {
  try { return localDateStr(new Date(iso)); } catch { return ""; }
}
function getDOW(d: Date): string {
  return `周${["日","一","二","三","四","五","六"][d.getDay()]}`;
}
function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    return `${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`;
  } catch { return ""; }
}
function parseDueDate(raw: unknown, today: Date): string | null {
  if (!raw) return null;
  const s = String(raw).trim();
  const m = s.match(/^(\d{4}-\d{2}-\d{2})/);
  if (m) return m[1];
  const clone = (n: number) => { const d = new Date(today); d.setDate(today.getDate() + n); return localDateStr(d); };
  if (s.startsWith("明天")) return clone(1);
  if (s.startsWith("后天")) return clone(2);
  return null;
}
function formatDueTime(raw: unknown): string {
  if (!raw) return "";
  const m = String(raw).match(/(\d{1,2}:\d{2})/);
  if (!m) return "";
  // Midnight (00:00) means "date only, no explicit time" — don't show it
  return (m[1] === "0:00" || m[1] === "00:00") ? "" : m[1];
}

/**
 * Human-readable relative due date label for todo subtitle.
 * Returns labels like "今天截止" / "明天截止" / "已逾期 5/20" / "截止 5/25"
 */
function formatDueRelative(dueRaw: unknown, today: Date): string {
  if (!dueRaw) return "";
  const s = String(dueRaw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return s.slice(0, 16);
  const todayStr = localDateStr(today);
  const dueDateStr = `${m[1]}-${m[2]}-${m[3]}`;
  const diff = Math.round(
    (new Date(dueDateStr + "T12:00:00").getTime() - new Date(todayStr + "T12:00:00").getTime())
    / 86400000,
  );
  if (diff < -1) return `已逾期 · ${Number(m[2])}/${Number(m[3])}`;
  if (diff === -1) return "昨天截止";
  if (diff === 0)  return "今天截止";
  if (diff === 1)  return "明天截止";
  if (diff === 2)  return "后天截止";
  return `截止 ${Number(m[2])}/${Number(m[3])}`;
}

/**
 * Method B: effective date is when the asset "matters", not when it was created.
 * - expense  → payload.date  (AI-parsed spend date, e.g. "昨天" → actual YYYY-MM-DD)
 * - todo     → payload.due_date  (when it is due, can be future)
 * - others   → created_at
 */
function getEffectiveDateStr(asset: Asset, now: Date): string {
  const t = (asset.payload.asset_type as string) ?? "";
  if (t === "expense" && asset.payload.date) {
    const s = String(asset.payload.date).trim();
    const m = s.match(/^(\d{4}-\d{2}-\d{2})/);
    if (m) return m[1];
  }
  if (t === "todo") {
    const due = parseDueDate(asset.payload.due_date, now);
    if (due) return due;
  }
  return assetDateStr(asset.created_at);
}

// ── Constants ─────────────────────────────────────────────────────────────────

const TYPE_ICON: Record<string, string> = {
  expense: "💰", todo: "✅", contact: "👤", idea: "💡", note: "📄", transcript: "🎙",
};
const TYPE_LABEL: Record<string, string> = {
  expense: "记账", todo: "待办", contact: "联系人", idea: "想法", note: "笔记", transcript: "会议",
};
const TYPE_COLOR: Record<string, string> = {
  expense: "var(--green)", todo: "var(--blue)", contact: "var(--purple)",
  idea: "var(--amber)", note: "var(--text2)", transcript: "var(--text2)",
};

function derivedSummaryLine(types: string[]): string {
  const seen = new Set<string>();
  const parts: string[] = [];
  for (const t of types) {
    if (t && !seen.has(t)) { seen.add(t); parts.push(`${TYPE_ICON[t] ?? "📎"} ${TYPE_LABEL[t] ?? t}`); }
  }
  return parts.join(" · ") || "无衍生内容";
}

/**
 * Sort key for a non-flash asset within its day section.
 * Items with an explicit HH:MM (not midnight) sort by that time.
 * Items with only a date (or midnight 00:00) get sortMs = midnight of their day,
 * so they sink to the bottom when the row is sorted descending.
 */
function getAssetSortMs(asset: Asset, effectiveDateStr: string): number {
  const t = (asset.payload.asset_type as string) ?? "";
  if (t === "todo" && asset.payload.due_date) {
    const raw = String(asset.payload.due_date);
    const tm = raw.match(/T(\d{2}):(\d{2})/);
    // Has an explicit time that isn't midnight → use that datetime for sorting
    if (tm && !(tm[1] === "00" && tm[2] === "00")) {
      return new Date(raw).getTime();
    }
  }
  // Date-only or midnight → sink to bottom of the day section
  return new Date(effectiveDateStr + "T00:00:00").getTime();
}

// ── Timeline types ────────────────────────────────────────────────────────────

interface TimelineItem {
  kind: "flash" | "asset";
  sortMs: number;
  asset: Asset;
  // Flash-specific (populated during buildTimeline)
  turnNumber?: number;
  derivedCount?: number;
  derivedSummary?: string;
  derivedTypeSet?: Set<string>;
  hasAudio?: boolean;
}

interface DateRow {
  dateStr: string;
  type: "past" | "today" | "future";
  dow: string;
  dayNum: number;
  shortLabel: string;
  items: TimelineItem[];
}

// ── Build timeline ────────────────────────────────────────────────────────────

function buildTimeline(assets: Asset[]): { rows: DateRow[]; heatMap: Map<string, number> } {
  const now = new Date();
  const todayStr = localDateStr(now);

  // Heat map spans ALL assets (used by mini-calendar)
  const heatMap = new Map<string, number>();
  for (const a of assets) {
    const d = assetDateStr(a.created_at);
    if (d) heatMap.set(d, (heatMap.get(d) ?? 0) + 1);
  }

  // Only voice flashes (from MicModal, is_voice=true) appear in the timeline.
  // Text follow-ups (is_followup=true) and text FAB entries (is_voice=false) are excluded.
  // Their derived assets still appear as standalone asset rows.
  const flashCards = assets.filter(a =>
    (a.payload.asset_type as string) === "flash" &&
    !a.payload.is_followup &&
    !!(a.payload.is_voice)
  );
  const nonFlash   = assets.filter(a => (a.payload.asset_type as string) !== "flash");

  // Map inputId → derived assets for computing flash summaries
  const byInputId = new Map<string, Asset[]>();
  for (const a of nonFlash) {
    const iid = a.payload.input_id as string | undefined;
    if (iid) { const l = byInputId.get(iid) ?? []; l.push(a); byInputId.set(iid, l); }
  }

  // Accumulate TimelineItems grouped by their effective date
  const byDate = new Map<string, TimelineItem[]>();
  const addItem = (dateStr: string, item: TimelineItem) => {
    if (!dateStr) return;
    const l = byDate.get(dateStr) ?? []; l.push(item); byDate.set(dateStr, l);
  };

  // Flash cards → placed at created_at date (compact row; derived listed only as summary)
  for (const flash of flashCards) {
    const dateStr = assetDateStr(flash.created_at);
    const iid = flash.payload.input_id as string | undefined;
    const derived = (iid ? byInputId.get(iid) : undefined) ?? [];
    const derivedTypes = derived.map(d => (d.payload.asset_type as string)).filter(Boolean);
    addItem(dateStr, {
      kind: "flash",
      sortMs: new Date(flash.created_at).getTime(),
      asset: flash,
      derivedCount: derived.length,
      derivedSummary: derivedSummaryLine(derivedTypes),
      derivedTypeSet: new Set(derivedTypes),
      hasAudio: !!(flash.payload.audio_url),
    });
  }

  // Non-flash assets → placed at their semantic effective date (Method B)
  for (const a of nonFlash) {
    const dateStr = getEffectiveDateStr(a, now);
    addItem(dateStr, {
      kind: "asset",
      sortMs: getAssetSortMs(a, dateStr),
      asset: a,
    });
  }

  // Always ensure today's row exists even when empty
  if (!byDate.has(todayStr)) byDate.set(todayStr, []);

  // Build DateRows — sort DESCENDING (newest date first = today at top)
  const rows: DateRow[] = [];
  for (const dateStr of [...byDate.keys()].sort().reverse()) {
    const rawItems = byDate.get(dateStr)!;

    // Assign ascending turn numbers (Turn 1 = earliest flash of the day)
    const flashItems = rawItems
      .filter(i => i.kind === "flash")
      .sort((a, b) => a.sortMs - b.sortMs);
    flashItems.forEach((item, idx) => { item.turnNumber = idx + 1; });

    // Within the date row, also sort descending (latest activity first)
    const items = [...rawItems].sort((a, b) => b.sortMs - a.sortMs);

    const type = dateStr > todayStr ? "future" : dateStr === todayStr ? "today" : "past";
    const d = new Date(dateStr + "T12:00:00");
    const diffDays = Math.round(
      (new Date(todayStr + "T12:00:00").getTime() - d.getTime()) / 86400000,
    );
    const shortLabel =
      type === "today"        ? "今天" :
      diffDays === 1          ? "昨天" :
      diffDays === 2          ? "前天" :
      diffDays === -1         ? "明天" :
      diffDays === -2         ? "后天" : "";

    rows.push({ dateStr, type, dow: getDOW(d), dayNum: d.getDate(), shortLabel, items });
  }

  return { rows, heatMap };
}

// ── Tab filtering (shared between render + hasContent check) ──────────────────

function filterItems(items: TimelineItem[], tab: StreamTab): TimelineItem[] {
  if (tab === "all") return items;
  if (tab === "flash") return items.filter(i => i.kind === "flash");
  // Asset-type tabs: only show matching non-flash rows — never show flash cards
  return items.filter(i =>
    i.kind !== "flash" && (i.asset.payload.asset_type as string) === tab
  );
}

// ── Flash row (compact — no inline derived cards) ─────────────────────────────

function FlashRow({ item, onClick }: { item: TimelineItem; onClick: () => void }) {
  const flash = item.asset;
  const hasAudio = item.hasAudio ?? false;
  const hasDerived = (item.derivedCount ?? 0) > 0;
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: "8px",
        padding: "9px 10px",
        background: "var(--surface)", border: "1px solid var(--border)",
        borderRadius: "var(--rs)", boxShadow: "var(--sh-s)", cursor: "pointer",
      }}
    >
      <span style={{ fontSize: "10px", color: "var(--text3)", width: "30px", flexShrink: 0, textAlign: "right" }}>
        {formatTime(flash.created_at)}
      </span>
      <div style={{
        width: "28px", height: "28px", borderRadius: "8px",
        background: "color-mix(in srgb, var(--amber) 12%, transparent)",
        border: "1px solid color-mix(in srgb, var(--amber) 22%, transparent)",
        display: "grid", placeItems: "center", fontSize: "14px", flexShrink: 0,
      }}>🎙</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "12px", fontWeight: 700, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
          {((flash.payload.transcript ?? flash.payload.content ?? "") as string).slice(0, 40) || "闪念"}
        </div>
        <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
          {item.derivedSummary}
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "3px", flexShrink: 0 }}>
        {hasDerived ? (
          <span style={{
            fontSize: "9px", fontWeight: 700, padding: "1px 6px", borderRadius: "999px",
            background: "color-mix(in srgb, var(--green) 12%, transparent)",
            border: "1px solid color-mix(in srgb, var(--green) 25%, transparent)",
            color: "var(--green)",
          }}>{item.derivedCount} 项</span>
        ) : (
          <span style={{
            fontSize: "9px", fontWeight: 700, padding: "1px 6px", borderRadius: "999px",
            background: "color-mix(in srgb, var(--amber) 12%, transparent)",
            border: "1px solid color-mix(in srgb, var(--amber) 25%, transparent)",
            color: "var(--amber)",
          }}>待处理</span>
        )}
        <span style={{ fontSize: "14px", color: "var(--text3)" }}>›</span>
      </div>
    </div>
  );
}

// ── Todo checkbox ─────────────────────────────────────────────────────────────

/**
 * Circular checkbox for todo cards.
 *
 * States:
 *  pending_confirmation → dashed border, dimmed, no tap (user hasn't claimed it yet)
 *  pending              → solid border circle, empty inside, tappable
 *  done                 → filled blue circle with SVG checkmark
 *
 * Tapping toggles pending ↔ done optimistically; reverts on API failure.
 * Propagation stopped so parent card click (→ detail) is not triggered.
 */
function TodoCheckbox({
  asset, onToggled,
}: { asset: Asset; onToggled: () => void }) {
  const status = (asset.payload.status as string) ?? "pending";
  const isPendingConfirmation = status === "pending_confirmation";
  const [localDone, setLocalDone] = useState(status === "done");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setLocalDone(asset.payload.status === "done");
  }, [asset.payload.status]);

  const toggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (busy || isPendingConfirmation) return;
    const next = !localDone;
    setLocalDone(next);
    setBusy(true);
    const res = await api.updateAsset(asset.id, { status: next ? "done" : "pending" });
    setBusy(false);
    if (!res.ok) setLocalDone(!next);
    else onToggled();
  };

  const SIZE = 22;
  const STROKE = 1.8;
  // pending_confirmation: dashed ring
  if (isPendingConfirmation) {
    return (
      <div
        onClick={e => e.stopPropagation()}
        style={{
          width: SIZE, height: SIZE, borderRadius: "50%", flexShrink: 0,
          border: `${STROKE}px dashed var(--border)`,
          display: "grid", placeItems: "center", flexDirection: "column",
          opacity: 0.55,
        }}
      />
    );
  }

  return (
    <div
      onClick={toggle}
      style={{
        width: SIZE, height: SIZE, borderRadius: "50%", flexShrink: 0,
        background: localDone ? "var(--blue)" : "transparent",
        border: `${STROKE}px solid ${localDone ? "var(--blue)" : "var(--text3)"}`,
        display: "grid", placeItems: "center",
        cursor: busy ? "default" : "pointer",
        opacity: busy ? 0.5 : 1,
        transition: "background .15s, border-color .15s",
        boxSizing: "border-box",
      }}
    >
      {localDone && (
        /* SVG checkmark — cleaner than font "✓" */
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
          <polyline points="2,6.5 5,9.5 10,3" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </div>
  );
}

// ── Standalone asset row (Method B — derived assets at effective date) ─────────

/**
 * Rendered for every non-flash asset in the timeline.
 *
 * Tapping anywhere → detail page.
 * For todos: tapping the left icon/checkbox area toggles done state (stops propagation).
 *
 * Time column shows:
 *  - todo    → due time (HH:MM) if present, else "" (undated todos show nothing)
 *  - expense → nothing (date already shown in subtitle)
 *  - others  → creation time
 */
function StandaloneAssetRow({
  item, onRefresh,
}: { item: TimelineItem; onRefresh: () => void }) {
  const { navTo } = useNav();
  const a = item.asset;
  const t = (a.payload.asset_type as string) ?? "misc";
  const p = a.payload;
  const color = TYPE_COLOR[t] ?? "var(--text2)";

  let title    = "";
  let subtitle = "";
  let timeStr  = formatTime(a.created_at); // default; overridden below

  if (t === "expense") {
    const cat  = ((p.category ?? "") as string).trim();
    const desc = ((p.description ?? p.merchant ?? "") as string).trim();
    title    = `¥${p.amount ?? ""}${desc ? " " + desc : ""}`;
    subtitle = cat || TYPE_LABEL[t];
    timeStr  = "";
  } else if (t === "todo") {
    title = ((p.content ?? p.title ?? "待办") as string).slice(0, 48);
    const now2 = new Date();
    if (p.due_date) {
      subtitle = formatDueRelative(p.due_date, now2);
      timeStr  = formatDueTime(p.due_date);  // HH:MM only if time component exists
    } else {
      subtitle = p.status === "pending_confirmation" ? "待认领" : "待办";
      timeStr  = "";
    }
  } else if (t === "contact") {
    title    = (p.name ?? "联系人") as string;
    subtitle = `${TYPE_LABEL[t] ?? t}${p.company ? ` · ${p.company as string}` : ""}`;
  } else {
    title    = ((p.title ?? p.content ?? t) as string).slice(0, 48);
    subtitle = `${TYPE_LABEL[t] ?? t} · ${timeStr}`;
  }

  const isDone                = p.status === "done";
  const isPendingConfirm      = p.status === "pending_confirmation";
  const isOverdue             = t === "todo" && subtitle.startsWith("已逾期");
  // 今天截止 = amber warning
  const isTodayDue            = t === "todo" && subtitle === "今天截止";

  const subtitleColor =
    isOverdue   ? "var(--red)"   :
    isTodayDue  ? "var(--amber)" :
    "var(--text3)";

  const goDetail = () => {
    navTo("p-asset-detail", { asset_id: a.id, asset_json: JSON.stringify(a) });
  };

  return (
    <div
      onClick={goDetail}
      style={{
        display: "flex", alignItems: "center", gap: "8px",
        padding: "9px 10px",
        background: isDone ? "var(--surface2)" : "var(--surface)",
        border: `1px solid ${isPendingConfirm ? "color-mix(in srgb, var(--border) 60%, transparent)" : "var(--border)"}`,
        borderRadius: "var(--rs)", boxShadow: "var(--sh-s)", cursor: "pointer",
        opacity: isDone ? 0.6 : isPendingConfirm ? 0.75 : 1,
      }}
    >
      {/* Time axis */}
      <span style={{ fontSize: "10px", color: "var(--text3)", width: "30px", flexShrink: 0, textAlign: "right" }}>
        {timeStr}
      </span>

      {/* Icon / checkbox */}
      {t === "todo" ? (
        <TodoCheckbox asset={a} onToggled={onRefresh} />
      ) : (
        <div style={{
          width: "28px", height: "28px", borderRadius: "8px",
          background: `color-mix(in srgb, ${color} 10%, transparent)`,
          border: `1px solid color-mix(in srgb, ${color} 20%, transparent)`,
          display: "grid", placeItems: "center", fontSize: "14px", flexShrink: 0,
        }}>{TYPE_ICON[t] ?? "📎"}</div>
      )}

      {/* Content */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: "12px", fontWeight: isDone ? 400 : 600,
          color: isDone ? "var(--text3)" : "var(--text)",
          overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
          textDecoration: isDone ? "line-through" : "none",
        }}>
          {title}
        </div>
        {subtitle && (
          <div style={{
            fontSize: "10px", color: subtitleColor,
            marginTop: "1px", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
            fontWeight: (isOverdue || isTodayDue) ? 600 : 400,
          }}>
            {subtitle}
          </div>
        )}
      </div>

      <span style={{ fontSize: "14px", color: "var(--text3)", flexShrink: 0 }}>›</span>
    </div>
  );
}

// ── Date row view ─────────────────────────────────────────────────────────────

function DateRowView({ row, tab, onFlashClick, onDateClick, onRefresh }: {
  row: DateRow;
  tab: StreamTab;
  onFlashClick: (asset: Asset) => void;
  onDateClick: (dateStr: string) => void;
  onRefresh: () => void;
}) {
  const items    = filterItems(row.items, tab);
  const isToday  = row.type === "today";
  const isFuture = row.type === "future";

  // Hide empty past/future rows; always show today (even if empty)
  if (!items.length && !isToday) return null;

  return (
    <div
      id={isToday ? "today-row" : undefined}
      style={{ display: "flex", padding: "0 8px" }}
    >
      {/* ── Date column (tap → day view) ── */}
      <div
        onClick={() => onDateClick(row.dateStr)}
        style={{
          width: "44px", flexShrink: 0,
          display: "flex", flexDirection: "column",
          alignItems: "center", paddingTop: "8px", gap: "2px",
          cursor: "pointer",
        }}
      >
        <div style={{ fontSize: "9px", fontWeight: 700, color: "var(--text3)", letterSpacing: ".04em" }}>
          {row.dow}
        </div>
        {isToday ? (
          <div style={{
            width: "30px", height: "30px", borderRadius: "50%",
            background: "var(--blue)", color: "#fff",
            display: "grid", placeItems: "center",
            fontSize: "16px", fontWeight: 800, lineHeight: 1,
          }}>{row.dayNum}</div>
        ) : (
          <div style={{ fontSize: "22px", fontWeight: 800, lineHeight: 1, color: isFuture ? "var(--text3)" : "var(--text)" }}>
            {row.dayNum}
          </div>
        )}
        {row.shortLabel && (
          <div style={{
            fontSize: "8px", fontWeight: 700, letterSpacing: ".04em",
            color: isToday ? "var(--blue)" : "var(--text3)",
          }}>{row.shortLabel}</div>
        )}
        {/* Vertical timeline spine */}
        <div style={{ width: "1px", flex: 1, background: "var(--border)", marginTop: "6px", minHeight: "20px" }} />
      </div>

      {/* ── Content column ── */}
      <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: "6px", padding: "6px 0 16px" }}>
        {items.length === 0 && isToday && (
          <div style={{ padding: "14px 0", color: "var(--text3)", fontSize: "12px", fontStyle: "italic" }}>
            今天暂无记录
          </div>
        )}
        {items.map(item =>
          item.kind === "flash"
            ? <FlashRow key={item.asset.id} item={item} onClick={() => onFlashClick(item.asset)} />
            : <StandaloneAssetRow key={item.asset.id} item={item} onRefresh={onRefresh} />
        )}
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────
// Note: the old "grid" view has been removed. Asset browsing is now done via
// the Workspace view (WorkspacePage), toggled from the FABBar.

interface StreamPageProps {
  onRegisterRefresh?: (fn: () => void) => void;
  viewMode?: StreamView;
}

export default function StreamPage({ onRegisterRefresh, viewMode = "timeline" }: StreamPageProps) {
  const { navTo, usePageVisitCount } = useNav();
  const { assets, isLoading, error, refresh } = useStream();
  const [activeTab, setActiveTab] = useState<StreamTab>("all");
  const [calOpen, setCalOpen]     = useState(false);

  // Auto-scroll to today's row once on first data load
  const didScrollRef = useRef(false);
  useEffect(() => {
    if (!isLoading && !didScrollRef.current) {
      const el = document.getElementById("today-row");
      if (el) {
        el.scrollIntoView({ behavior: "auto", block: "start" });
        didScrollRef.current = true;
      }
    }
  }, [isLoading]);

  // Refetch when user navigates back to this page
  const visitCount = usePageVisitCount("p-stream");
  useEffect(() => {
    if (visitCount > 0) refresh();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visitCount]);

  useEffect(() => { onRegisterRefresh?.(refresh); }, [onRegisterRefresh, refresh]);

  const { rows: timeline, heatMap } = buildTimeline(assets);

  const handleDayClick = useCallback((dateStr: string) => {
    navTo("p-day-view", { date: dateStr });
  }, [navTo]);

  const hasContent = timeline.some(row => filterItems(row.items, activeTab).length > 0);
  const isEmpty    = !isLoading && !error && !hasContent;

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
      <StreamHeader
        isCalOpen={calOpen}
        onToggleCal={() => setCalOpen(o => !o)}
        heatMap={heatMap}
        onDayClick={handleDayClick}
      />
      <TabBar activeTab={activeTab} onTabChange={setActiveTab} />

      {/* Loading skeleton */}
      {isLoading && (
        <div className="no-scrollbar" style={{ flex: 1, display: "flex", flexDirection: "column", gap: "8px", padding: "8px 16px 100px", overflowY: "auto" }}>
          {[1,2,3].map(i => (
            <div key={i} style={{ height: "58px", borderRadius: "var(--rs)", background: "var(--surface)", border: "1px solid var(--border)", opacity: 1-i*0.2, animation: "pulse 1.4s ease-in-out infinite" }} />
          ))}
          <style>{`@keyframes pulse{0%,100%{opacity:.6}50%{opacity:.3}}`}</style>
        </div>
      )}

      {/* Error state */}
      {!isLoading && error && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "32px 24px 100px", gap: "10px", textAlign: "center" }}>
          <div style={{ fontSize: "36px" }}>⚠️</div>
          <div style={{ fontSize: "13px", color: "var(--red)", maxWidth: "240px" }}>加载失败: {error}</div>
          <button onClick={refresh} style={{ padding: "7px 18px", borderRadius: "999px", background: "var(--surface)", border: "1px solid var(--border)", fontSize: "12px", fontWeight: 600, color: "var(--blue)", cursor: "pointer" }}>重试</button>
        </div>
      )}

      {/* Empty state (timeline only) */}
      {isEmpty && viewMode === "timeline" && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "32px 24px 100px", gap: "16px", textAlign: "center" }}>
          <div style={{ fontSize: "40px" }}>{activeTab === "all" ? "✦" : TYPE_ICON[activeTab] ?? "📭"}</div>
          <div style={{ fontSize: "15px", fontWeight: 700, color: "var(--text)" }}>
            {activeTab === "all" ? "今日记录为空" : "暂无该类型记录"}
          </div>
          {activeTab === "all" && (
            <div style={{ fontSize: "12px", color: "var(--text2)", lineHeight: 1.7, maxWidth: "240px" }}>
              点击底部 <span style={{ fontWeight: 700, color: "var(--amber)" }}>＋</span> 记录闪念
            </div>
          )}
        </div>
      )}


      {/* Timeline — continuous vertical scroll, newest date at top */}
      {!isLoading && !error && viewMode === "timeline" && (
        <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "4px 0 100px" }}>
          {/* Refresh pill */}
          <div style={{ display: "flex", alignItems: "center", gap: "6px", padding: "4px 8px 4px 56px" }}>
            <span style={{ flex: 1, height: "1px", background: "var(--border)" }} />
            <button
              onClick={refresh}
              disabled={isLoading}
              style={{
                width: "20px", height: "20px", borderRadius: "50%",
                border: "1px solid var(--border)", background: "var(--surface2)",
                display: "grid", placeItems: "center",
                fontSize: "11px", cursor: isLoading ? "default" : "pointer",
                color: "var(--text3)", opacity: isLoading ? 0.5 : 1,
              }}
            >↺</button>
          </div>

          {timeline.map(row => (
            <DateRowView
              key={row.dateStr}
              row={row}
              tab={activeTab}
              onFlashClick={asset => navTo("p-flash-sess", {
                session_id: asset.session_id ?? "",
                flash_id: asset.id,
              })}
              onDateClick={handleDayClick}
              onRefresh={refresh}
            />
          ))}
        </div>
      )}
    </div>
  );
}
