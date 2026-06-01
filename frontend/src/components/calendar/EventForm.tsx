import { useState } from "react";
import { Loader2, Trash2, X } from "lucide-react";

import { useModalMount } from "@/context/ModalContext";
import { useEventMutations, type EventInput } from "@/hooks/useEvents";
import type { Event } from "@/lib/types";

/**
 * EventForm — drawer-shape event create / edit (M4-bugfix-3).
 *
 * Replaces the previous Timepage-style EventEditor (purple panel + scrub bar
 * + mode tabs + toolbar + recent-events tray). Per user "我希望 event 的
 * 创建、edit 和 展示 在全产品内都用 这个形式" — uses the same drawer shell
 * as AssetDetailDrawer (mobile bottom sheet / desktop right drawer 480),
 * with label/input rows instead of read-only GenericFields.
 *
 * Same component handles both create and edit (toggle via `existing` prop).
 * View is owned by AssetDetailDrawer; tap-to-edit on a card opens this form.
 *
 * Action row:
 *   - 删除           (edit only, red, double-tap to confirm)
 *
 * No inline 「在 chat 里讨论」: the global FloatingDock's Agent button
 * registers an AgentTarget on the event's detail drawer (AssetDetailDrawer)
 * and enters the bound session directly. Close form → tap dock Agent.
 *
 * Footer:
 *   - 取消 / 保存
 *
 * Form fields (kept lean — the bespoke time scrubber + mode tabs are gone,
 * a standard datetime-local + "全天" toggle does the job):
 *   - 标题       (required)
 *   - 开始时间    (datetime-local OR date when 全天)
 *   - 结束时间    (datetime-local OR date when 全天)
 *   - 全天        (toggle — when on, end_at auto-set to 23:59 of start day)
 *   - 地点
 */

interface EventFormProps {
  existing?:     Event;
  defaultStart?: Date;
  onClose:       () => void;
  onSaved?:      (eventId: string) => void;
}

export function EventForm(props: EventFormProps) {
  useModalMount();
  return <EventFormBody {...props} />;
}

function EventFormBody({ existing, defaultStart, onClose, onSaved }: EventFormProps) {
  const isEdit = !!existing;
  const { create, update, remove } = useEventMutations();

  // ── initial state ──────────────────────────────────────────────────
  const initStart = existing
    ? new Date(existing.start_at)
    : (defaultStart ?? roundToNextHalfHour(new Date()));
  const initEnd = existing?.end_at
    ? new Date(existing.end_at)
    : addMinutes(initStart, 60);
  const initAllDay = Boolean(existing?.all_day);

  const [title,    setTitle]    = useState(existing?.title    ?? "");
  const [start,    setStart]    = useState<Date>(initStart);
  const [end,      setEnd]      = useState<Date>(initEnd);
  const [allDay,   setAllDay]   = useState<boolean>(initAllDay);
  const [location, setLocation] = useState(existing?.location ?? "");
  const [busy,     setBusy]     = useState(false);
  const [error,    setError]    = useState<string | null>(null);
  const [confirmDel,     setConfirmDel]     = useState(false);

  // ── save ──────────────────────────────────────────────────────────
  async function handleSave() {
    if (!title.trim()) { setError("请输入标题"); return; }
    setBusy(true); setError(null);
    try {
      const body: EventInput = {
        title:    title.trim(),
        start_at: toIsoWithOffset(allDay ? startOfDay(start) : start),
        end_at:   toIsoWithOffset(allDay ? endOfDay(start)   : end),
        all_day:  allDay,
        location: location.trim(),
      };
      let id: string;
      if (isEdit && existing) {
        await update(existing.event_id, body);
        id = existing.event_id;
      } else {
        id = await create(body);
      }
      onSaved?.(id);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  }

  async function handleDelete() {
    if (!existing) return;
    setBusy(true);
    try {
      await remove(existing.event_id);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md eu-fade-in"
      onClick={onClose}
    >
      <aside
        onClick={(e) => e.stopPropagation()}
        className={[
          // VF: phone-frame is always mobile-shaped, so bottom sheet only.
          "fixed inset-x-0 bottom-0 max-h-[88vh] rounded-t-eu-xl",
          "eu-sheet-up",
          "bg-eu-surface-raised border-t border-eu-border",
          "shadow-eu-lg pt-eu-md pb-safe overflow-y-auto eu-noscroll",
          "flex flex-col gap-eu-md",
        ].join(" ")}
      >
        {/* drag handle (mobile only) */}
        <div className="md:hidden h-1 w-12 rounded-full bg-eu-rule mx-auto" />

        {/* ── Header: 📅 icon + EVENT caps + title input + close ─────── */}
        <header className="flex items-start gap-eu-md px-eu-lg">
          <div className="shrink-0 h-10 w-10 rounded-eu-md border border-eu-accent-purple-edge bg-eu-accent-purple-bg text-eu-accent-purple-fg flex items-center justify-center text-eu-lg">
            📅
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
              event
            </div>
            <input
              autoFocus={!isEdit}
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="事件名称…"
              className="w-full mt-0.5 bg-transparent border-none outline-none text-eu-lg text-eu-text-hi font-medium tracking-tight"
            />
          </div>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="shrink-0 p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </header>

        {/* No inline 「在 chat 里讨论」 — dock Agent is the global entry. */}

        {/* ── Form rows ──────────────────────────────────────────────── */}
        <div className="px-eu-lg flex flex-col gap-eu-md pt-eu-md">
          {/* 全天 toggle */}
          <FieldRow label="全天">
            <button
              type="button"
              onClick={() => setAllDay((v) => !v)}
              className={[
                "inline-flex items-center gap-2 px-eu-sm py-1 rounded-eu-full text-eu-sm",
                "border transition-colors duration-eu-fast",
                allDay
                  ? "bg-eu-brand-faint text-eu-brand-hi border-eu-brand-line"
                  : "bg-eu-surface text-eu-text-mid border-eu-border hover:text-eu-text-hi",
              ].join(" ")}
            >
              <span
                className={[
                  "inline-block h-3 w-3 rounded-full border",
                  allDay ? "bg-eu-brand border-eu-brand" : "border-eu-text-lo",
                ].join(" ")}
              />
              {allDay ? "全天" : "指定时间"}
            </button>
          </FieldRow>

          <FieldRow label={allDay ? "日期" : "开始时间"}>
            <DateOrTimeInput
              value={start}
              dateOnly={allDay}
              onChange={(d) => {
                setStart(d);
                if (!allDay && +d >= +end) setEnd(addMinutes(d, 60));
              }}
            />
          </FieldRow>

          {!allDay && (
            <FieldRow label="结束时间">
              <DateOrTimeInput value={end} dateOnly={false} onChange={setEnd} />
            </FieldRow>
          )}

          <FieldRow label="地点">
            <input
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              placeholder="(可选)"
              className="w-full bg-eu-surface border border-eu-border rounded-eu-md px-eu-sm py-1.5 text-eu-base text-eu-text-hi focus:outline-none focus:border-eu-brand"
            />
          </FieldRow>

          {error && (
            <div className="text-eu-sm text-eu-accent-red-fg bg-eu-accent-red-bg border border-eu-accent-red-edge rounded-eu-md px-eu-sm py-1.5 font-mono">
              {error}
            </div>
          )}
        </div>

        {/* ── Footer: 删除 (edit only) / 取消 / 保存 ───────────────── */}
        <footer className="mt-auto px-eu-lg pt-eu-md pb-eu-md border-t border-eu-rule flex items-center gap-eu-sm">
          {isEdit && (
            <button
              type="button"
              onClick={() => (confirmDel ? handleDelete() : setConfirmDel(true))}
              disabled={busy}
              className={[
                "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm",
                confirmDel
                  ? "bg-eu-accent-red-bg text-eu-accent-red-fg border border-eu-accent-red-edge"
                  : "text-eu-accent-red-fg hover:bg-eu-accent-red-bg",
              ].join(" ")}
            >
              <Trash2 size={14} strokeWidth={1.75} />
              {confirmDel ? "确认删除" : "删除"}
            </button>
          )}
          <div className="ml-auto flex gap-eu-sm">
            <button
              type="button"
              onClick={onClose}
              className="px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:text-eu-text-hi"
            >
              取消
            </button>
            <button
              type="button"
              onClick={handleSave}
              disabled={busy || !title.trim()}
              className={[
                "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
                "bg-eu-brand text-white hover:bg-eu-brand-hi",
                "disabled:opacity-50 disabled:cursor-not-allowed",
                "transition-colors duration-eu-fast",
              ].join(" ")}
            >
              {busy && <Loader2 size={14} strokeWidth={2} className="animate-spin" />}
              {isEdit ? "保存" : "创建"}
            </button>
          </div>
        </footer>
      </aside>
    </div>
  );
}

/* ── Sub-components ───────────────────────────────────────────────── */

function FieldRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
        {label}
      </div>
      {children}
    </div>
  );
}

/**
 * DateOrTimeInput — wraps native datetime-local / date input with a
 * uniform style. When dateOnly, the time part is hidden and the value
 * snaps to midnight.
 */
function DateOrTimeInput({
  value, dateOnly, onChange,
}: { value: Date; dateOnly: boolean; onChange: (d: Date) => void }) {
  const pad = (n: number) => String(n).padStart(2, "0");
  const text = dateOnly
    ? `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}`
    : `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}T${pad(value.getHours())}:${pad(value.getMinutes())}`;
  return (
    <input
      type={dateOnly ? "date" : "datetime-local"}
      value={text}
      onChange={(e) => {
        const v = e.target.value;
        if (!v) return;
        const next = dateOnly
          ? new Date(v + "T00:00:00")
          : new Date(v);
        if (!isNaN(+next)) onChange(next);
      }}
      className="w-full bg-eu-surface border border-eu-border rounded-eu-md px-eu-sm py-1.5 text-eu-base text-eu-text-hi font-mono focus:outline-none focus:border-eu-brand"
    />
  );
}

/* ── helpers (kept inline to avoid coupling EventForm to EventEditor) ── */

function addMinutes(d: Date, m: number): Date {
  return new Date(+d + m * 60_000);
}
function roundToNextHalfHour(d: Date): Date {
  const out = new Date(d);
  out.setSeconds(0, 0);
  const m = out.getMinutes();
  out.setMinutes(m < 30 ? 30 : 60);
  return out;
}
function startOfDay(d: Date): Date {
  const out = new Date(d); out.setHours(0, 0, 0, 0); return out;
}
function endOfDay(d: Date): Date {
  const out = new Date(d); out.setHours(23, 59, 0, 0); return out;
}
function toIsoWithOffset(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const offMin = -d.getTimezoneOffset();
  const sign = offMin >= 0 ? "+" : "-";
  const oh = pad(Math.floor(Math.abs(offMin) / 60));
  const om = pad(Math.abs(offMin) % 60);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}${sign}${oh}:${om}`;
}
