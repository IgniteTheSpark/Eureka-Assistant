"use client";

import { useCallback, useEffect, useState } from "react";
import { useNav } from "@/context/NavContext";
import { api } from "@/lib/api";
import type { Asset } from "@/lib/types";

// ── Helpers ───────────────────────────────────────────────────────────────────

function todayLocalDateStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
}
function assetDateStr(iso: string) {
  try {
    const d = new Date(iso);
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
  } catch { return ""; }
}
function formatTime(iso: string) {
  try {
    const d = new Date(iso);
    return `${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`;
  } catch { return ""; }
}

// ── Type config ───────────────────────────────────────────────────────────────

const SECTION_ORDER = ["contact", "todo", "expense", "idea", "note", "transcript"];

const TYPE_META: Record<string, { icon: string; label: string; bg: string; border: string; color: string }> = {
  contact:    { icon: "👤", label: "联系人", bg: "color-mix(in srgb, var(--purple) 8%, transparent)", border: "color-mix(in srgb, var(--purple) 18%, transparent)", color: "var(--purple)" },
  todo:       { icon: "✅", label: "待办",   bg: "color-mix(in srgb, var(--blue) 8%, transparent)",   border: "color-mix(in srgb, var(--blue) 18%, transparent)",   color: "var(--blue)"   },
  expense:    { icon: "💰", label: "消费",   bg: "color-mix(in srgb, var(--green) 8%, transparent)",  border: "color-mix(in srgb, var(--green) 18%, transparent)",  color: "var(--green)"  },
  idea:       { icon: "💡", label: "想法",   bg: "color-mix(in srgb, var(--amber) 8%, transparent)",  border: "color-mix(in srgb, var(--amber) 18%, transparent)",  color: "var(--amber)"  },
  note:       { icon: "📄", label: "笔记",   bg: "var(--surface2)",                                   border: "var(--border)",                                      color: "var(--text2)"  },
  transcript: { icon: "🎙", label: "转录",   bg: "var(--surface2)",                                   border: "var(--border)",                                      color: "var(--text2)"  },
};

function formatDueShort(raw: unknown): string {
  if (!raw) return "";
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return s.slice(0, 16);
  const month = Number(m[2]);
  const day   = Number(m[3]);
  const tm = s.match(/T(\d{2}):(\d{2})/);
  if (tm && !(tm[1] === "00" && tm[2] === "00")) {
    return `${month}月${day}日 ${tm[1]}:${tm[2]}`;
  }
  return `${month}月${day}日截止`;
}

function getTitle(asset: Asset): string {
  const p = asset.payload;
  const t = p.asset_type as string;
  if (t === "contact")  return p.name ?? "联系人";
  if (t === "todo")     return p.content ?? p.title ?? "待办";
  if (t === "expense")  return `¥${p.amount ?? ""} ${p.description ?? p.merchant ?? "消费"}`;
  if (t === "idea")     return p.title ?? p.content ?? "想法";
  if (t === "note")     return p.title ?? p.content ?? "笔记";
  if (t === "transcript") return p.title ?? "转录";
  return p.title ?? p.content ?? t;
}

function getSubtitle(asset: Asset): string {
  const p = asset.payload;
  const t = p.asset_type as string;
  if (t === "contact")  return [p.company, p.phone].filter(Boolean).join(" · ");
  if (t === "todo")     return formatDueShort(p.due_date);
  if (t === "expense")  return [p.category, p.merchant].filter(Boolean).join(" · ");
  if (t === "idea")     return "";
  return "";
}

// ── Flash group (for Turn N lookup) ──────────────────────────────────────────

interface FlashTurnRef { flashId: string; turnNumber: number; created_at: string; }

// ── Asset row ─────────────────────────────────────────────────────────────────

function AssetRow({
  asset,
  turnRef,
  onGoToTurn,
}: {
  asset: Asset;
  turnRef?: FlashTurnRef;
  onGoToTurn?: () => void;
}) {
  const t = asset.payload.asset_type as string;
  const meta = TYPE_META[t] ?? { icon: "📎", label: t, bg: "var(--surface2)", border: "var(--border)", color: "var(--text2)" };
  const title = getTitle(asset);
  const sub   = getSubtitle(asset);

  return (
    <div style={{
      display: "flex", alignItems: "center", gap: "10px",
      padding: "10px 14px",
      background: "var(--surface)", border: "1px solid var(--border)",
      borderRadius: "var(--rs)", boxShadow: "var(--sh-s)",
    }}>
      <div style={{
        width: "32px", height: "32px", borderRadius: "9px", flexShrink: 0,
        background: meta.bg, border: `1px solid ${meta.border}`,
        display: "grid", placeItems: "center", fontSize: "15px",
      }}>{meta.icon}</div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "12px", fontWeight: 700, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
          {title}
        </div>
        {sub && (
          <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>{sub}</div>
        )}
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: "6px", flexShrink: 0 }}>
        {turnRef && (
          <button
            onClick={onGoToTurn}
            style={{
              fontSize: "9px", fontWeight: 700, padding: "2px 7px",
              borderRadius: "999px",
              background: "color-mix(in srgb, var(--blue) 8%, transparent)",
              border: "1px solid color-mix(in srgb, var(--blue) 20%, transparent)",
              color: "var(--blue)", cursor: "pointer",
            }}
          >Turn {turnRef.turnNumber} ↗</button>
        )}
        <span style={{ fontSize: "10px", color: "var(--text3)" }}>{formatTime(asset.created_at)}</span>
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function FlashOverallPage() {
  const { goBack, navTo, currentParams } = useNav();
  const targetSessionId = currentParams.session_id ?? "";

  const [derived, setDerived]     = useState<Asset[]>([]);
  const [turnRefs, setTurnRefs]   = useState<Map<string, FlashTurnRef>>(new Map());
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError]         = useState<string | null>(null);

  const load = useCallback(async () => {
    setIsLoading(true); setError(null);
    try {
      // Prefer session-scoped assets; fall back to today's global assets
      let allAssets: Asset[];
      if (targetSessionId) {
        const res = await api.getAssets({ session_id: targetSessionId, limit: 200 });
        if (!res.ok) { setError(res.error ?? "加载失败"); return; }
        allAssets = res.assets ?? [];
      } else {
        const res = await api.getAssets({ limit: 200 });
        if (!res.ok) { setError(res.error ?? "加载失败"); return; }
        const today = todayLocalDateStr();
        allAssets = (res.assets ?? []).filter((a) => assetDateStr(a.created_at) === today);
      }

      // Build turn number map: input_id → { flashId, turnNumber, created_at }
      const flashCards = allAssets
        .filter((a) => a.payload.asset_type === "flash")
        .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

      const refs = new Map<string, FlashTurnRef>();
      flashCards.forEach((flash, idx) => {
        const iid = flash.payload.input_id as string | undefined;
        if (iid) refs.set(iid, { flashId: flash.id, turnNumber: idx + 1, created_at: flash.created_at });
      });

      const derivedAssets = allAssets.filter((a) => a.payload.asset_type !== "flash");
      setDerived(derivedAssets);
      setTurnRefs(refs);
    } catch (e) { setError(String(e)); }
    finally { setIsLoading(false); }
  }, [targetSessionId]);

  useEffect(() => { load(); }, [load]);

  // Group derived by type
  const byType = new Map<string, Asset[]>();
  for (const a of derived) {
    const t = (a.payload.asset_type as string) ?? "misc";
    const arr = byType.get(t) ?? [];
    arr.push(a);
    byType.set(t, arr);
  }

  const sections = SECTION_ORDER
    .filter((t) => byType.has(t))
    .map((t) => ({ type: t, assets: byType.get(t)! }));

  // Types not in SECTION_ORDER
  for (const [t, assets] of byType) {
    if (!SECTION_ORDER.includes(t)) sections.push({ type: t, assets });
  }

  const today = new Date();
  const dateLabel = `${today.getFullYear()}年${String(today.getMonth()+1).padStart(2,"0")}月${String(today.getDate()).padStart(2,"0")}日`;

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px 9px", flexShrink: 0,
        background: "var(--surface)", borderBottom: "1px solid var(--border)",
      }}>
        <button onClick={goBack} style={{
          width: "30px", height: "30px", borderRadius: "50%",
          background: "var(--surface2)", border: "1px solid var(--border)",
          display: "grid", placeItems: "center",
          fontSize: "18px", color: "var(--blue)", cursor: "pointer",
        }}>‹</button>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: "14px", fontWeight: 800, color: "var(--text)" }}>总资产</div>
          <div style={{ fontSize: "9px", color: "var(--text3)", marginTop: "1px" }}>
            {dateLabel} 闪念{!isLoading && ` · ${derived.length} 项`}
          </div>
        </div>
        <button onClick={load} disabled={isLoading} style={{
          width: "28px", height: "28px", borderRadius: "50%",
          background: "var(--surface2)", border: "1px solid var(--border)",
          display: "grid", placeItems: "center",
          fontSize: "13px", color: "var(--text3)", cursor: isLoading ? "default" : "pointer",
          opacity: isLoading ? 0.5 : 1,
        }}>↺</button>
      </div>

      {/* Body */}
      <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "12px 12px 80px" }}>
        {isLoading && (
          <>
            {[1,2,3].map((i) => <div key={i} style={{ height: "50px", borderRadius: "var(--rs)", background: "var(--surface)", border: "1px solid var(--border)", marginBottom: "6px", opacity: 1-i*0.25, animation: "pulse 1.4s ease-in-out infinite" }} />)}
            <style>{`@keyframes pulse{0%,100%{opacity:.6}50%{opacity:.3}}`}</style>
          </>
        )}

        {!isLoading && error && (
          <div style={{ textAlign: "center", color: "var(--red)", fontSize: "12px", padding: "32px 0" }}>{error}</div>
        )}

        {!isLoading && !error && derived.length === 0 && (
          <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text3)", fontSize: "13px" }}>
            暂无衍生资产
          </div>
        )}

        {!isLoading && !error && sections.map(({ type, assets }) => {
          const meta = TYPE_META[type] ?? { icon: "📎", label: type, color: "var(--text2)" };
          return (
            <div key={type} style={{ marginBottom: "16px" }}>
              {/* Section header */}
              <div style={{
                display: "flex", alignItems: "center", gap: "6px",
                padding: "6px 0 8px",
              }}>
                <span style={{ fontSize: "13px" }}>{meta.icon}</span>
                <span style={{ fontSize: "11px", fontWeight: 800, color: meta.color, letterSpacing: ".04em" }}>
                  {meta.label}
                </span>
                <span style={{ fontSize: "11px", color: "var(--text3)", fontWeight: 600 }}>· {assets.length}</span>
                <span style={{ flex: 1, height: "1px", background: "var(--border)", marginLeft: "4px" }} />
              </div>

              {/* Asset rows */}
              <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                {assets.map((asset) => {
                  const iid = asset.payload.input_id as string | undefined;
                  const tref = iid ? turnRefs.get(iid) : undefined;
                  return (
                    <AssetRow
                      key={asset.id}
                      asset={asset}
                      turnRef={tref}
                      onGoToTurn={() => {
                        if (tref) {
                          navTo("p-flash-sess", { session_id: targetSessionId, flash_id: tref.flashId });
                        }
                      }}
                    />
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
