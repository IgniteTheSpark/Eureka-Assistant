import { useEffect, useState } from "react";
import { useSWRConfig } from "swr";
import { ExternalLink, History, Pencil, Trash2, X, Loader2 } from "lucide-react";
import { useLocation, useNavigate } from "react-router-dom";

import { EventForm } from "@/components/calendar/EventForm";
import { ContactForm } from "@/components/contact/ContactForm";
import { GenericField } from "@/components/skill/GenericField";
import { McpBrandMark, isMcpBrand } from "@/components/skill/McpBrandMark";
import { SkillCreateForm } from "@/components/skill/SkillCreateForm";
import { useAgentTarget, useModalMount } from "@/context/ModalContext";
import { useEvents } from "@/hooks/useEvents";
import { useSessionDetail } from "@/hooks/useSessions";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { apiFetch } from "@/lib/api";
import type { CardData, FieldFormat } from "@/lib/render-spec";
import type { Asset, Contact } from "@/lib/types";

/**
 * AssetDetailDrawer — read-only detail + actions (M2.2).
 *
 * Mobile: bottom sheet (~85vh max). Desktop: right-side drawer 480px wide.
 *
 * Actions:
 *   - 编辑 / 删除          → opens the matching edit form / confirms delete.
 *   - 来源 chip            → if Agent created the asset, taps into that
 *                            source session (read the original conversation).
 *
 * No inline 「在 chat 里讨论」 — the global FloatingDock's Agent button is
 * the entry. The drawer registers an AgentTarget on mount, so the dock's
 * Agent opens the asset's bound session directly. Same doctrine across
 * EventForm / ContactForm — dock = global, context-bound agent entry.
 */

interface AssetDetailDrawerProps {
  card: CardData;
  payload: Record<string, unknown>;
  onClose: () => void;
  /** Asset's session_id (creator session) — for the source-trace button */
  sourceSessionId?: string | null;
}

export function AssetDetailDrawer({ card, payload, onClose, sourceSessionId }: AssetDetailDrawerProps) {
  // keepDock: the global dock stays visible over the detail — its Agent button
  // is now the entry into this asset's bound session (no in-drawer discuss btn).
  useModalMount({ keepDock: true });
  const navigate = useNavigate();
  const location = useLocation();
  const { mutate } = useSWRConfig();
  const { bySkill } = useSkillRegistry();
  const { events } = useEvents();
  const { setAgentTarget } = useAgentTarget();

  // Source provenance: flash (闪念 capture) vs agent (chat) vs manual. Look up
  // the creating session's type so we can label + route correctly. flash and
  // chat both open the session on tap; manual has no session.
  const { session: sourceSession } = useSessionDetail(sourceSessionId ?? null);
  const sourceKind: "flash" | "agent" | "manual" =
    !sourceSessionId ? "manual"
      : sourceSession?.session_type === "flash" ? "flash"
        : "agent";

  // Register this asset as the dock's Agent target while the detail is open.
  useEffect(() => {
    if (!card.assetId) return;
    const subjectType = card.cardType === "contact" ? "contact"
      : card.cardType === "event" ? "event"
      : card.cardType === "file" ? "file"
      : "asset";
    setAgentTarget({ subject: { type: subjectType, id: card.assetId }, label: card.title });
    return () => setAgentTarget(null);
  }, [card.assetId, card.cardType, card.title, setAgentTarget]);

  // RV3: edit + delete state.
  // - editing: which inner form is open (event / asset / null)
  // - confirmDel: double-click delete pattern (same as EventForm)
  // - busy: prevents re-clicks during the delete API call
  const [editing,    setEditing]    = useState<"event" | "asset" | "contact" | null>(null);
  const [confirmDel, setConfirmDel] = useState(false);
  const [busy,       setBusy]       = useState(false);

  // Esc to close
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  // Look up the matching skill + event row (for the edit branch).
  const isEvent  = card.cardType === "event";
  const isContact = card.cardType === "contact";
  const skill    = bySkill.get(card.cardType);
  const eventRow = isEvent
    ? events.find((e) => e.event_id === card.assetId)
    : undefined;
  // CF: contact-edit now has a ContactForm, so contacts are editable +
  // deletable too. Edit/delete still need an id + a known edit path.
  const editable   = !!card.assetId && (isEvent ? !!eventRow : (isContact || !!skill));
  const deletable  = !!card.assetId;

  async function handleDelete() {
    if (!card.assetId || busy) return;
    setBusy(true);
    try {
      const url = isEvent   ? `/api/events/${card.assetId}`
                : isContact ? `/api/contacts/${card.assetId}`
                : `/api/assets/${card.assetId}`;
      const resp = await apiFetch<{ ok: boolean; error?: string }>(
        url, { method: "DELETE" },
      );
      if (!resp.ok) throw new Error(resp.error ?? "删除失败");
      await mutate((key) => typeof key === "string" && (
        key.startsWith("/api/assets") ||
        key.startsWith("/api/events")  ||
        key.startsWith("/api/contacts") ||
        key.startsWith("/api/timeline")
      ));
      onClose();
    } catch (e) {
      // eslint-disable-next-line no-alert
      alert((e as Error).message ?? "删除失败");
      setBusy(false);
      setConfirmDel(false);
    }
  }

  function handleEdit() {
    setEditing(isEvent ? "event" : isContact ? "contact" : "asset");
  }

  // Build the Contact-shaped object ContactForm needs for prefill from the
  // drawer's payload (contact opened from Library has name/phone/... fields).
  const contactForEdit: Contact | null = card.assetId && isContact ? {
    id:      card.assetId,
    name:    String((payload as Record<string, unknown>).name ?? card.title ?? ""),
    phone:   (payload.phone   as string) ?? null,
    company: (payload.company as string) ?? null,
    title:   (payload.title   as string) ?? null,
    email:   (payload.email   as string) ?? null,
    notes:   Array.isArray(payload.notes) ? (payload.notes as string[]) : [],
    created_at: "",
  } : null;

  // Build the Asset-shaped object the SkillCreateForm needs for prefill.
  // We have payload + assetId + cardType so this is straightforward.
  const assetForEdit: Asset | null = card.assetId && !isEvent ? {
    id: card.assetId,
    user_skill_name: card.cardType,
    payload: payload,
    session_id: sourceSessionId ?? null,
    source_input_turn_id: null,
    created_at: "",
  } : null;

  /** 跳到创建该 asset 的 session — opens chat with the existing creator session. */
  function openSourceSession() {
    if (!sourceSessionId) return;
    window.localStorage.setItem("eureka:active_chat_session", sourceSessionId);
    onClose();
    navigate("/chat", {
      state: { from: location.pathname, fromLabel: card.title || "上一页" },
    });
  }

  // RV3: when an edit form is open, hand off to it entirely (the form is
  // a fullscreen modal on its own). Closing it just clears the editing
  // state — the parent drawer stays mounted underneath so the user lands
  // back on the detail view, where SWR cache invalidation already
  // refreshed the displayed payload.
  if (editing === "event" && eventRow) {
    return <EventForm existing={eventRow} onClose={() => setEditing(null)} />;
  }
  if (editing === "contact" && contactForEdit) {
    return <ContactForm existing={contactForEdit} onClose={() => setEditing(null)} />;
  }
  if (editing === "asset" && assetForEdit && skill) {
    return (
      <SkillCreateForm
        skill={skill}
        existing={assetForEdit}
        onClose={() => setEditing(null)}
      />
    );
  }

  return (
    <div
      // Heavy backdrop so the FloatingDock fades behind the drawer cleanly
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md eu-fade-in"
      onClick={onClose}
    >
      <aside
        onClick={(e) => e.stopPropagation()}
        className={[
          // VF: phone-frame is always mobile-shaped, so bottom sheet only —
          // killed the old md: right-drawer override which used to width
          // 480px (escapes the 393px frame).
          "fixed inset-x-0 bottom-0 max-h-[85vh] rounded-t-eu-xl",
          "bg-eu-surface-raised border-t border-eu-border",
          "shadow-eu-lg pt-eu-md overflow-y-auto eu-noscroll",
          "flex flex-col gap-eu-md eu-sheet-up",
        ].join(" ")}
        // Bottom clearance so the (now-visible) floating dock doesn't cover the
        // last fields — the dock's Agent button is this asset's session entry.
        style={{ paddingBottom: "calc(env(safe-area-inset-bottom) + 92px)" }}
      >
        {/* drag handle (mobile only) */}
        <div className="md:hidden h-1 w-12 rounded-full bg-eu-rule mx-auto" />

        {/* Hero — column layout per the design's AssetHero (big gradient icon
            → prominent title → subtitle), replacing the old compact row. */}
        <header className="px-eu-lg">
          <div className="flex items-center justify-between">
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
              {card.cardType}
            </div>
            <button
              type="button"
              aria-label="关闭"
              onClick={onClose}
              className="shrink-0 p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
            >
              <X size={18} strokeWidth={1.75} />
            </button>
          </div>
          {isMcpBrand(card.icon) ? (
            <div className="mt-3">
              <McpBrandMark icon={card.icon} size={54} radius={14} />
            </div>
          ) : (
            <div
              className={[
                "mt-3 flex items-center justify-center border font-mono font-semibold",
                ACCENT_BG[card.accentColor],
                ACCENT_FG[card.accentColor],
                ACCENT_BORDER[card.accentColor],
              ].join(" ")}
              style={{ width: 54, height: 54, borderRadius: 14, fontSize: 22, boxShadow: "inset 0 0 18px rgba(255,255,255,0.05)" }}
            >
              {card.icon}
            </div>
          )}
          <h2 className="mt-3.5 text-eu-text-hi font-semibold tracking-tight break-words" style={{ fontSize: 22, lineHeight: 1.25 }}>
            {card.title}
          </h2>
          {card.subtitle && (
            <div className="text-eu-text-mid mt-2" style={{ fontSize: 14 }}>{card.subtitle}</div>
          )}
        </header>

        {/* Action row */}
        <div className="px-eu-lg flex flex-wrap gap-eu-sm">
          {editable && (
            <ActionButton
              icon={<Pencil size={14} strokeWidth={1.75} />}
              label="编辑"
              onClick={handleEdit}
            />
          )}
          {deletable && (
            <button
              type="button"
              onClick={() => (confirmDel ? handleDelete() : setConfirmDel(true))}
              disabled={busy}
              className={[
                "px-eu-md py-1.5 rounded-eu-md text-eu-sm inline-flex items-center gap-1.5",
                "transition-all duration-eu-fast",
                confirmDel
                  ? "bg-eu-accent-red-bg text-eu-accent-red-fg border border-eu-accent-red-edge"
                  : "text-eu-accent-red-fg hover:bg-eu-accent-red-bg border border-transparent",
                "disabled:opacity-50",
              ].join(" ")}
            >
              {busy
                ? <Loader2 size={14} strokeWidth={1.75} className="animate-spin" />
                : <Trash2 size={14} strokeWidth={1.75} />}
              {confirmDel ? "确认删除" : "删除"}
            </button>
          )}
          {externalUrl(payload) && (
            <a
              href={externalUrl(payload) ?? "#"}
              target="_blank"
              rel="noopener"
              className={[
                "px-eu-md py-1.5 rounded-eu-md text-eu-sm",
                "bg-eu-accent-purple-bg text-eu-accent-purple-fg border border-eu-accent-purple-edge",
                "hover:brightness-110 inline-flex items-center gap-1.5",
                "transition-all duration-eu-fast",
              ].join(" ")}
            >
              <ExternalLink size={14} strokeWidth={1.75} />
              打开外部链接
            </a>
          )}
        </div>

        {/* 来源 · SOURCE — R6: brief source only (manual vs agent-session),
            not the full source detail. The agent line is tappable → opens the
            creating session. */}
        <div className="px-eu-lg pt-eu-md">
          <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono mb-2">
            来源 · SOURCE
          </div>
          {sourceKind === "manual" ? (
            <div className="w-full flex items-center gap-2.5 px-eu-md py-2.5 rounded-eu-md bg-eu-surface border border-eu-border">
              <span
                className="shrink-0 grid place-items-center font-mono"
                style={{ width: 24, height: 24, borderRadius: 7, background: "var(--eu-accent-neutral-bg)", border: "1px solid var(--eu-accent-neutral-edge)", color: "var(--eu-accent-neutral-fg)", fontSize: 13 }}
              >✎</span>
              <div className="flex-1">
                <div className="text-eu-xs uppercase tracking-eu-caps font-mono text-eu-text-lo">Manual</div>
                <div className="text-eu-sm text-eu-text-hi mt-0.5">手动创建</div>
              </div>
            </div>
          ) : sourceKind === "flash" ? (
            <button
              type="button"
              onClick={openSourceSession}
              className="w-full flex items-center gap-2.5 px-eu-md py-2.5 rounded-eu-md bg-eu-accent-blue-bg border border-eu-accent-blue-edge text-left hover:brightness-110 transition-all duration-eu-fast"
            >
              <span
                className="shrink-0 grid place-items-center font-mono"
                style={{ width: 24, height: 24, borderRadius: 7, background: "var(--eu-accent-blue-bg)", border: "1px solid var(--eu-accent-blue-edge)", color: "var(--eu-accent-blue-fg)", fontSize: 13, fontWeight: 600 }}
              >⚡</span>
              <div className="flex-1 min-w-0">
                <div className="text-eu-xs uppercase tracking-eu-caps font-mono text-eu-accent-blue-fg">闪念 · FLASH</div>
                <div className="text-eu-sm text-eu-text-hi mt-0.5">闪念录入时整理 · 点开看原始记录</div>
              </div>
              <History size={14} strokeWidth={1.75} className="text-eu-text-mid shrink-0" />
            </button>
          ) : (
            <button
              type="button"
              onClick={openSourceSession}
              className="w-full flex items-center gap-2.5 px-eu-md py-2.5 rounded-eu-md bg-eu-accent-amber-bg border border-eu-accent-amber-edge text-left hover:brightness-110 transition-all duration-eu-fast"
            >
              <span
                className="shrink-0 grid place-items-center font-mono"
                style={{ width: 24, height: 24, borderRadius: 7, background: "var(--eu-accent-amber-bg)", border: "1px solid var(--eu-accent-amber-edge)", color: "var(--eu-accent-amber-fg)", fontSize: 13, fontWeight: 600 }}
              >●</span>
              <div className="flex-1 min-w-0">
                <div className="text-eu-xs uppercase tracking-eu-caps font-mono text-eu-accent-amber-fg">Agent · 对话</div>
                <div className="text-eu-sm text-eu-text-hi mt-0.5">由 Agent 在对话中创建 · 点开看对话</div>
              </div>
              <History size={14} strokeWidth={1.75} className="text-eu-text-mid shrink-0" />
            </button>
          )}
        </div>

        <div className="px-eu-lg border-t border-eu-rule pt-eu-md flex flex-col gap-eu-md">
          {/* Payload fields */}
          {Object.entries(payload).map(([key, value]) => {
            if (shouldSkipField(key, value)) return null;
            // Arrays get a custom string-list renderer (attendees etc.)
            if (Array.isArray(value)) {
              return <ArrayField key={key} label={fieldLabel(key)} items={value} />;
            }
            return (
              <GenericField
                key={key}
                label={fieldLabel(key)}
                value={value}
                format={inferFormat(key, value)}
                multiline={MULTILINE_KEYS.has(key)}
              />
            );
          })}
        </div>
      </aside>
    </div>
  );
}

/* ── Helpers ────────────────────────────────────────────────────────────── */

// Fields that are internal plumbing — never useful to show
const SKIP_KEYS = new Set([
  "ok",                  // RV3: tool_result envelope flag, never user-facing
  "when",                // OP12: synthetic subtitle field (event drawer)
  "card_type",           // RV3: synthesized by extractCardFromToolResult
  "kind",                // timeline kind discriminator
  "skill_name",          // duplicate of cardType caps
  "user_skill_name",     // ditto
  "user_id",             // implementation detail
  "all_day",             // RV3: shown via the time-range formatting in the header
  "status",              // mostly always "scheduled" — noise
  "task_id",             // internal — not user-facing
  "external_id",         // shown via the link button
  "external_url",        // shown via the link button
  "external_system",     // shown via the link button styling
  "external_type",       // not interesting on the detail page
  "event_id",            // shown in header context
  "asset_id",            // duplicate of context
  "id",                  // ditto (event row uses `id` too sometimes)
  "contact_id",          // ditto
  "file_id",             // ditto
  "source_input_turn_id", // M4 surfaces as SessionTurnCard
  "session_id",          // M4 surfaces via "在 chat 里讨论" routing
  "sync_source",         // implementation detail
  "sync_external_id",    // implementation detail
  "recurrence_rule",     // shown elsewhere when UI for it exists (post-MVP)
  "updated_at",          // not interesting except for audit
  "user_skill_id",       // implementation detail
  "logId",               // some MCP responses include this trace id
  "trace_id",            // same
  // Render-spec / CardData keys that leak into `payload` when a chat-built
  // card dict is opened (prebuilt flash cards). These are presentation
  // metadata, never user content — hide them so the body reads cleanly
  // (was the「ICON / ACTIONS / ACCENT_COLOR」junk the user flagged).
  "icon", "accent_color", "accentColor", "actions",
  "card_layout", "layout", "cardType", "checkDone",
  "primary_field", "primary_format", "secondary_field", "secondary_format",
  "meta_fields", "metaFields", "timeline_position", "calendar_render",
  "field_units", "primary_label", "primary_unit", "secondary_label", "secondary_unit",
]);

/** Friendly Chinese labels for common payload keys (raw machine keys read as
 *  unintelligible「DUE_DATE」caps otherwise). Unmapped keys fall back to the
 *  key itself. */
const FIELD_LABEL: Record<string, string> = {
  title: "标题", subtitle: "摘要", content: "内容", note: "备注", notes: "备注",
  description: "描述", summary: "摘要", body: "正文", markdown: "正文",
  due_date: "截止时间", date: "日期", time: "时间", start_at: "开始", end_at: "结束",
  amount: "金额", price: "价格", currency: "币种", category: "分类",
  location: "地点", distance: "距离", duration: "时长", pace: "配速", mood: "心情",
  name: "名称", company: "公司", title_role: "职位", phone: "电话", email: "邮箱",
  asr_text: "原始语音", reps: "次数", weight: "重量", pages_read: "阅读页数",
};
function fieldLabel(key: string): string {
  return FIELD_LABEL[key] ?? key;
}

/** Heuristic: should this field be hidden from the drawer? */
function shouldSkipField(key: string, value: unknown): boolean {
  if (SKIP_KEYS.has(key)) return true;
  // Empty containers contribute no information
  if (value == null) return true;
  if (Array.isArray(value) && value.length === 0) return true;
  if (typeof value === "object" && !Array.isArray(value) && Object.keys(value as object).length === 0) return true;
  return false;
}

/** Render array fields specially — strings as a chip list, objects as
 *  "name (role)" or just JSON-stringified primitives. */
function ArrayField({ label, items }: { label: string; items: unknown[] }) {
  // Pull a sensible label out of each item
  const display = items.map((it) => {
    if (it == null) return "—";
    if (typeof it === "string" || typeof it === "number") return String(it);
    if (typeof it === "object") {
      const o = it as Record<string, unknown>;
      const name = o.name ?? o.title ?? o.display_name;
      const role = o.role;
      if (name && role) return `${name} (${role})`;
      if (name) return String(name);
      return JSON.stringify(o).slice(0, 80);
    }
    return String(it);
  });
  return (
    <div className="flex flex-col gap-1">
      <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">{label}</div>
      <div className="flex flex-wrap gap-1.5">
        {display.map((d, i) => (
          <span
            key={`${label}-${i}`}
            className="px-2 py-0.5 rounded-eu-sm bg-eu-surface border border-eu-border text-eu-sm text-eu-text"
          >
            {d}
          </span>
        ))}
      </div>
    </div>
  );
}

const MULTILINE_KEYS = new Set([
  "content", "description", "summary", "notes", "markdown", "body", "asr_text",
]);

function inferFormat(key: string, value: unknown): FieldFormat | undefined {
  if (typeof value !== "string") return undefined;
  if (key === "amount" || key === "price")  return "currency";
  // due_date is the only field where the "截止" (deadline) suffix makes
  // sense (todo). Event start_at/end_at + created_at etc. use the plain
  // absolute date — otherwise an event shows "5月28日截止" which reads as
  // a deadline.
  if (key === "due_date")                    return "relative_date";
  if (key.endsWith("_date") || key.endsWith("_at")) return "absolute_date";
  if (key === "date" || key === "time")      return "absolute_date";
  if (key === "duration_sec")                return undefined;
  // Last resort: any string that parses as an ISO datetime (e.g., a
  // user-defined skill's `time` / `at` / `recorded_at` field whose name
  // doesn't match the heuristics above) — render it as 「5月30日 12:00」
  // instead of dumping「2026-05-30T12:00:00+08:00」on the user.
  if (looksLikeIsoDatetime(value))            return "absolute_date";
  return undefined;
}

const ISO_DT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/;
function looksLikeIsoDatetime(s: string): boolean {
  return ISO_DT_RE.test(s);
}

function externalUrl(payload: Record<string, unknown>): string | null {
  const v = payload.external_url;
  return typeof v === "string" && v.length > 0 ? v : null;
}

function ActionButton({
  icon, label, onClick, disabled, variant = "default",
}: {
  icon: React.ReactNode;
  label: string;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "default" | "primary";
}) {
  const primary = variant === "primary";
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={[
        "px-eu-md py-1.5 rounded-eu-md text-eu-sm inline-flex items-center gap-1.5",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        "transition-all duration-eu-fast",
        primary
          ? "bg-eu-brand text-white hover:bg-eu-brand-hi"
          : "bg-eu-surface border border-eu-border text-eu-text-mid hover:bg-eu-surface-hover hover:text-eu-text-hi",
      ].join(" ")}
    >
      {icon}
      {label}
    </button>
  );
}

// Per-accent class maps so Tailwind's purge keeps them
const ACCENT_BG: Record<string, string> = {
  blue: "bg-eu-accent-blue-bg",       amber:  "bg-eu-accent-amber-bg",
  green: "bg-eu-accent-green-bg",     red:    "bg-eu-accent-red-bg",
  purple: "bg-eu-accent-purple-bg",   gray:   "bg-eu-accent-gray-bg",
  neutral: "bg-eu-accent-neutral-bg",
};
const ACCENT_FG: Record<string, string> = {
  blue: "text-eu-accent-blue-fg",     amber:  "text-eu-accent-amber-fg",
  green: "text-eu-accent-green-fg",   red:    "text-eu-accent-red-fg",
  purple: "text-eu-accent-purple-fg", gray:   "text-eu-accent-gray-fg",
  neutral: "text-eu-accent-neutral-fg",
};
const ACCENT_BORDER: Record<string, string> = {
  blue: "border-eu-accent-blue-edge",     amber:  "border-eu-accent-amber-edge",
  green: "border-eu-accent-green-edge",   red:    "border-eu-accent-red-edge",
  purple: "border-eu-accent-purple-edge", gray:   "border-eu-accent-gray-edge",
  neutral: "border-eu-accent-neutral-edge",
};
