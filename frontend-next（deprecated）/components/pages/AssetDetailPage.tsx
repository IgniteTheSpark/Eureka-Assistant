"use client";

/**
 * AssetDetailPage — 资产详情 + 编辑页
 *
 * 设计规范：docs/workspace-spec.md §七 "Asset 详情页"
 *
 * 导航：navTo("p-asset-detail", { asset_id: "...", asset_json: "..." })
 *   asset_json 由调用方直接传入已加载的资产 JSON，避免额外 fetch。
 *
 * 编辑保存走 PUT /api/assets/{id}，后端同步更新 payload + asset_fields 倒排索引。
 * 不可编辑的保留字段：asset_type, is_followup, source_type, input_id
 *
 * 来源溯源：若 asset.session_id 存在，显示「查看来源 Session」按钮，
 *   点击跳转到 FlashSessionPage。
 */

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { useNav } from "@/context/NavContext";
import { api } from "@/lib/api";
import type { Asset } from "@/lib/types";

// ── Constants ─────────────────────────────────────────────────────────────────

const RESERVED_KEYS = new Set(["asset_type", "is_followup", "source_type", "input_id"]);

const ASSET_META: Record<string, { icon: string; label: string; color: string }> = {
  todo:    { icon: "✅", label: "待办",   color: "var(--blue)"  },
  idea:    { icon: "💡", label: "想法",   color: "var(--amber)" },
  note:    { icon: "📄", label: "笔记",   color: "var(--text2)" },
  expense: { icon: "💰", label: "消费",   color: "var(--green)" },
  misc:    { icon: "📎", label: "杂项",   color: "var(--text3)" },
};

function getMeta(type: string) {
  return ASSET_META[type] ?? { icon: "📦", label: type, color: "var(--text2)" };
}

// ── Shared input styles ────────────────────────────────────────────────────────

const inputStyle: CSSProperties = {
  width: "100%", boxSizing: "border-box",
  background: "var(--surface2)", border: "1px solid var(--border)",
  borderRadius: "var(--rs)", padding: "8px 10px",
  fontSize: "13px", color: "var(--text)",
  outline: "none",
};

const labelStyle: CSSProperties = {
  fontSize: "10px", fontWeight: 700, color: "var(--text3)",
  letterSpacing: "0.05em", marginBottom: "4px",
  display: "block",
};

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", marginBottom: "14px" }}>
      <span style={labelStyle}>{label.toUpperCase()}</span>
      {children}
    </div>
  );
}

// ── Type-specific edit forms ───────────────────────────────────────────────────

function toDatetimeLocal(raw: unknown): string {
  if (!raw) return "";
  const s = String(raw).trim();
  // YYYY-MM-DDTHH:MM (with optional seconds / timezone)
  const withTime = s.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/);
  if (withTime) return `${withTime[1]}T${withTime[2]}`;
  // Date-only: YYYY-MM-DD
  const dateOnly = s.match(/^(\d{4}-\d{2}-\d{2})$/);
  if (dateOnly) return `${dateOnly[1]}T00:00`;
  // Can't parse (e.g. relative strings like "明天") — return empty so input shows placeholder
  return "";
}

function TodoForm({
  draft, onChange,
}: { draft: Record<string, unknown>; onChange: (k: string, v: unknown) => void }) {
  return (
    <>
      <Field label="内容">
        <textarea
          value={(draft.content as string) ?? ""}
          onChange={e => onChange("content", e.target.value)}
          rows={3}
          style={{ ...inputStyle, resize: "vertical" }}
        />
      </Field>
      <Field label="状态">
        <select
          value={(draft.status as string) ?? "pending"}
          onChange={e => onChange("status", e.target.value)}
          style={inputStyle}
        >
          <option value="pending_confirmation">待认领</option>
          <option value="pending">进行中</option>
          <option value="done">已完成</option>
          <option value="dismissed">已忽略</option>
        </select>
      </Field>
      <Field label="截止时间">
        <input
          type="datetime-local"
          value={toDatetimeLocal(draft.due_date)}
          onChange={e => onChange("due_date", e.target.value || "")}
          style={inputStyle}
        />
      </Field>
    </>
  );
}

function ExpenseForm({
  draft, onChange,
}: { draft: Record<string, unknown>; onChange: (k: string, v: unknown) => void }) {
  return (
    <>
      <Field label="金额">
        <input
          type="number" step="0.01"
          value={(draft.amount as string) ?? ""}
          onChange={e => onChange("amount", e.target.value === "" ? "" : Number(e.target.value))}
          style={inputStyle}
        />
      </Field>
      <Field label="商家">
        <input
          type="text"
          value={(draft.merchant as string) ?? ""}
          onChange={e => onChange("merchant", e.target.value)}
          style={inputStyle}
        />
      </Field>
      <Field label="类别">
        <input
          type="text"
          value={(draft.category as string) ?? ""}
          onChange={e => onChange("category", e.target.value)}
          style={inputStyle}
        />
      </Field>
      <Field label="日期">
        <input
          type="date"
          value={(draft.date as string) ?? ""}
          onChange={e => onChange("date", e.target.value)}
          style={inputStyle}
        />
      </Field>
      <Field label="描述">
        <textarea
          value={(draft.description as string) ?? ""}
          onChange={e => onChange("description", e.target.value)}
          rows={2}
          style={{ ...inputStyle, resize: "vertical" }}
        />
      </Field>
    </>
  );
}

function NoteForm({
  draft, onChange,
}: { draft: Record<string, unknown>; onChange: (k: string, v: unknown) => void }) {
  return (
    <>
      <Field label="内容">
        <textarea
          value={(draft.content as string) ?? ""}
          onChange={e => onChange("content", e.target.value)}
          rows={6}
          style={{ ...inputStyle, resize: "vertical" }}
        />
      </Field>
      <Field label="笔记类型">
        <input
          type="text"
          placeholder="meeting_summary / conversation_note / manual"
          value={(draft.note_type as string) ?? ""}
          onChange={e => onChange("note_type", e.target.value)}
          style={inputStyle}
        />
      </Field>
    </>
  );
}

function IdeaForm({
  draft, onChange,
}: { draft: Record<string, unknown>; onChange: (k: string, v: unknown) => void }) {
  return (
    <Field label="内容">
      <textarea
        value={(draft.content as string) ?? (draft.title as string) ?? ""}
        onChange={e => onChange("content", e.target.value)}
        rows={7}
        style={{ ...inputStyle, resize: "vertical" }}
      />
    </Field>
  );
}

function SimpleContentForm({
  label, draft, onChange,
}: { label: string; draft: Record<string, unknown>; onChange: (k: string, v: unknown) => void }) {
  return (
    <Field label={label}>
      <textarea
        value={(draft.content as string) ?? ""}
        onChange={e => onChange("content", e.target.value)}
        rows={5}
        style={{ ...inputStyle, resize: "vertical" }}
      />
    </Field>
  );
}

/** Fallback: render every non-reserved key as a text input */
function GenericForm({
  draft, onChange,
}: { draft: Record<string, unknown>; onChange: (k: string, v: unknown) => void }) {
  const keys = Object.keys(draft).filter(k => !RESERVED_KEYS.has(k));
  return (
    <>
      {keys.map(k => (
        <Field key={k} label={k}>
          <input
            type="text"
            value={draft[k] == null ? "" : String(draft[k])}
            onChange={e => onChange(k, e.target.value)}
            style={inputStyle}
          />
        </Field>
      ))}
    </>
  );
}

// ── Detail header ──────────────────────────────────────────────────────────────

function DetailHeader({
  title, meta, onBack,
}: {
  title: string;
  meta: { icon: string; color: string };
  onBack: () => void;
}) {
  return (
    <div style={{
      display: "flex", alignItems: "center", gap: "10px",
      padding: "10px 12px 9px", flexShrink: 0,
      background: "var(--surface)", borderBottom: "1px solid var(--border)",
    }}>
      <button onClick={onBack} style={{
        width: "30px", height: "30px", borderRadius: "50%",
        background: "var(--surface2)", border: "1px solid var(--border)",
        display: "grid", placeItems: "center",
        fontSize: "18px", color: "var(--blue)", cursor: "pointer",
      }}>‹</button>
      <div style={{
        width: "28px", height: "28px", borderRadius: "8px",
        background: `color-mix(in srgb, ${meta.color} 12%, transparent)`,
        border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
        display: "grid", placeItems: "center", fontSize: "15px", flexShrink: 0,
      }}>{meta.icon}</div>
      <div style={{ fontSize: "15px", fontWeight: 800, color: "var(--text)", flex: 1, letterSpacing: "-0.02em" }}>
        {title}
      </div>
    </div>
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")} ${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`;
  } catch { return ""; }
}

const SOURCE_LABELS: Record<string, string> = {
  session: "⚡ 闪念",
  file_analysis: "📁 文件",
  manual: "✏️ 手动",
};

// ── Main page ──────────────────────────────────────────────────────────────────

export default function AssetDetailPage() {
  const { currentParams, goBack, navTo } = useNav();
  const assetId = currentParams.asset_id ?? "";

  const [asset,       setAsset]       = useState<Asset | null>(null);
  const [draft,       setDraft]       = useState<Record<string, unknown>>({});
  const [loading,     setLoading]     = useState(true);
  const [saving,      setSaving]      = useState(false);
  const [error,       setError]       = useState<string | null>(null);
  const [saveMsg,     setSaveMsg]     = useState<string | null>(null);
  const [sessionType, setSessionType] = useState<string | null>(null);

  // Load asset — try nav-passed JSON first (instant), fall back to API fetch
  useEffect(() => {
    if (!assetId) {
      setAsset(null); setDraft({}); setLoading(false); setError(null);
      return;
    }

    // Fast path: asset was serialised into nav params by the caller
    const assetJsonStr = currentParams.asset_json ?? "";
    if (assetJsonStr) {
      try {
        const parsed = JSON.parse(assetJsonStr) as Asset;
        setAsset(parsed);
        const editable: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(parsed.payload)) {
          if (!RESERVED_KEYS.has(k)) editable[k] = v;
        }
        setDraft(editable);
        setLoading(false);
        setError(null);
        return;
      } catch { /* fall through to fetch */ }
    }

    // Slow path: fetch from API
    setLoading(true);
    setError(null);
    api.getAsset(assetId).then(res => {
      if (res.ok && res.asset) {
        setAsset(res.asset);
        const editable: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(res.asset.payload)) {
          if (!RESERVED_KEYS.has(k)) editable[k] = v;
        }
        setDraft(editable);
      } else {
        setError(res.error ?? "加载失败");
      }
    }).catch(e => setError(String(e)))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [assetId, currentParams.asset_json]);

  const handleChange = (key: string, value: unknown) => {
    setDraft(prev => ({ ...prev, [key]: value }));
    setSaveMsg(null);
  };

  const handleSave = async () => {
    if (!assetId || saving) return;
    setSaving(true);
    setSaveMsg(null);
    const res = await api.updateAsset(assetId, draft);
    setSaving(false);
    if (res.ok) {
      setSaveMsg("已保存");
      if (res.asset) setAsset(res.asset);
    } else {
      setSaveMsg(`保存失败: ${res.error}`);
    }
  };

  // Fetch session type when asset has a session_id (determines "查看来源" destination)
  useEffect(() => {
    const sid = asset?.session_id;
    if (!sid) { setSessionType(null); return; }
    api.getSession(sid).then(res => {
      if (res.ok && res.session) setSessionType(res.session.session_type);
    }).catch(() => {});
  }, [asset?.session_id]);

  const assetType = (asset?.payload.asset_type as string) ?? "";
  const meta      = getMeta(assetType);

  // ── Loading ──────────────────────────────────────────────────────────────────
  if (loading) {
    return (
      <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
        <DetailHeader title="加载中…" meta={meta} onBack={goBack} />
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ fontSize: "13px", color: "var(--text3)" }}>Loading…</div>
        </div>
      </div>
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────────
  if (assetId && (error || !asset)) {
    return (
      <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
        <DetailHeader title="详情" meta={meta} onBack={goBack} />
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", flexDirection: "column", gap: "10px" }}>
          <div style={{ fontSize: "28px" }}>⚠️</div>
          <div style={{ fontSize: "13px", color: "var(--red)" }}>{error ?? "资产不存在"}</div>
        </div>
      </div>
    );
  }

  // ── No asset selected (background render) ────────────────────────────────────
  if (!asset) return null;

  const sourceType  = asset.payload.source_type as string | undefined;
  const sessionId   = asset.session_id;
  // When navigated from AgentChatPage, it passes from_page="p-agent-chat"
  const fromAgentChat = currentParams.from_page === "p-agent-chat";

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
      <DetailHeader title={meta.label} meta={meta} onBack={goBack} />

      {/* Scroll area */}
      <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "14px 14px 100px" }}>

        {/* ── Provenance strip ── */}
        <div style={{
          display: "flex", alignItems: "center", justifyContent: "space-between",
          padding: "8px 12px", marginBottom: "16px",
          background: "var(--surface2)", border: "1px solid var(--border)",
          borderRadius: "var(--rs)",
        }}>
          <div style={{ fontSize: "10px", color: "var(--text3)", lineHeight: 1.6 }}>
            <div>创建于 {formatTime(asset.created_at)}</div>
            {sourceType && sourceType !== "manual" && (
              <div style={{ marginTop: "1px" }}>
                来源：{SOURCE_LABELS[sourceType] ?? sourceType}
              </div>
            )}
          </div>

          {/* Back to agent chat (when navigated from agent chat page) */}
          {fromAgentChat && (
            <button
              onClick={goBack}
              style={{
                display: "flex", alignItems: "center", gap: "4px",
                padding: "5px 10px", borderRadius: "999px",
                background: "color-mix(in srgb, var(--blue) 10%, transparent)",
                border: "1px solid color-mix(in srgb, var(--blue) 30%, transparent)",
                color: "var(--blue)", fontSize: "10px", fontWeight: 700,
                cursor: "pointer", whiteSpace: "nowrap",
              }}
            >
              ← 返回对话
            </button>
          )}

          {/* Jump to source session — only when not already navigated from agent chat */}
          {sessionId && !fromAgentChat && sessionType && (
            <button
              onClick={() => {
                if (sessionType === "agent_chat") {
                  // Load that conversation in AgentChatPage
                  navTo("p-agent-chat");
                  // Brief delay to let the page mount before loadSession is called
                  // The AgentChatPage will restore from localStorage; we rely on the
                  // drawer "点击session" path instead for now
                } else {
                  navTo("p-flash-sess", { session_id: sessionId });
                }
              }}
              style={{
                display: "flex", alignItems: "center", gap: "4px",
                padding: "5px 10px", borderRadius: "999px",
                background: sessionType === "agent_chat"
                  ? "color-mix(in srgb, var(--blue) 10%, transparent)"
                  : "color-mix(in srgb, var(--amber) 10%, transparent)",
                border: `1px solid ${sessionType === "agent_chat"
                  ? "color-mix(in srgb, var(--blue) 30%, transparent)"
                  : "color-mix(in srgb, var(--amber) 30%, transparent)"}`,
                color: sessionType === "agent_chat" ? "var(--blue)" : "var(--amber)",
                fontSize: "10px", fontWeight: 700,
                cursor: "pointer", whiteSpace: "nowrap",
              }}
            >
              {sessionType === "agent_chat" ? "✦ 查看对话 →" : "⚡ 查看来源 →"}
            </button>
          )}
        </div>

        {/* ── Type-specific edit form ── */}
        {assetType === "todo"    && <TodoForm draft={draft} onChange={handleChange} />}
        {assetType === "expense" && <ExpenseForm draft={draft} onChange={handleChange} />}
        {assetType === "note"    && <NoteForm draft={draft} onChange={handleChange} />}
        {assetType === "idea"    && <IdeaForm draft={draft} onChange={handleChange} />}
        {assetType === "misc"    && <SimpleContentForm label="内容" draft={draft} onChange={handleChange} />}
        {!ASSET_META[assetType]  && <GenericForm draft={draft} onChange={handleChange} />}
      </div>

      {/* ── Sticky save bar ── */}
      <div style={{
        position: "absolute", bottom: 0, left: 0, right: 0,
        padding: "10px 14px 16px",
        background: "var(--surface)", borderTop: "1px solid var(--border)",
        display: "flex", alignItems: "center", gap: "10px",
      }}>
        {saveMsg ? (
          <span style={{
            flex: 1, fontSize: "12px",
            color: saveMsg.startsWith("保存失败") ? "var(--red)" : "var(--green)",
          }}>{saveMsg}</span>
        ) : (
          <span style={{ flex: 1 }} />
        )}
        <button
          onClick={handleSave}
          disabled={saving}
          style={{
            padding: "8px 22px", borderRadius: "var(--rs)",
            background: saving ? "var(--surface2)" : "var(--blue)",
            border: "none", color: saving ? "var(--text3)" : "#fff",
            fontSize: "13px", fontWeight: 700,
            cursor: saving ? "not-allowed" : "pointer",
          }}
        >
          {saving ? "保存中…" : "保存"}
        </button>
      </div>
    </div>
  );
}
