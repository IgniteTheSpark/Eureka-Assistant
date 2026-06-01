"use client";

import { useEffect, useState } from "react";
import { useNav } from "@/context/NavContext";
import { api } from "@/lib/api";
import type { Asset } from "@/lib/types";

// ── Helpers ────────────────────────────────────────────────────────────────────

function localDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function assetDateStr(iso: string): string {
  try { return localDateStr(new Date(iso)); } catch { return ""; }
}
function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  } catch { return ""; }
}
function formatDate(dateStr: string): string {
  // dateStr = "YYYY-MM-DD"
  try {
    const d = new Date(dateStr + "T12:00:00");
    const DOW = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][d.getDay()];
    const todayStr = localDateStr(new Date());
    const yStr = localDateStr(new Date(new Date().setDate(new Date().getDate() - 1)));
    const label = dateStr === todayStr ? "今天" : dateStr === yStr ? "昨天" : "";
    return `${d.getMonth() + 1}月${d.getDate()}日 ${DOW}${label ? " · " + label : ""}`;
  } catch { return dateStr; }
}

// ── Asset type meta ────────────────────────────────────────────────────────────

const TYPE_META: Record<string, { icon: string; label: string; color: string }> = {
  contact:    { icon: "👤", label: "联系人", color: "var(--green)"  },
  todo:       { icon: "✅", label: "待办",   color: "var(--blue)"   },
  expense:    { icon: "💰", label: "消费",   color: "var(--amber)"  },
  idea:       { icon: "💡", label: "想法",   color: "var(--purple)" },
  note:       { icon: "📄", label: "笔记",   color: "var(--text2)"  },
  transcript: { icon: "🎙", label: "会议",   color: "var(--text2)"  },
  flash:      { icon: "⚡", label: "闪念",   color: "var(--amber)"  },
};

function getTitle(a: Asset): string {
  const p = a.payload;
  const t = p.asset_type as string;
  if (t === "contact")  return (p.name ?? "联系人") as string;
  if (t === "todo")     return (p.content ?? p.title ?? "待办") as string;
  if (t === "expense")  return `¥${p.amount ?? ""} ${p.description ?? p.merchant ?? "消费"}`;
  if (t === "idea")     return (p.title ?? p.content ?? "想法") as string;
  if (t === "flash")    return (p.content ?? "闪念") as string;
  return (p.content ?? p.title ?? t) as string;
}

// ── Flash grouping (same logic as StreamPage) ──────────────────────────────────

interface FlashGroup { flash: Asset; derived: Asset[]; turnNumber: number; }

function buildGroups(assets: Asset[]): { flashGroups: FlashGroup[]; orphans: Asset[] } {
  const sorted = [...assets].sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
  const flashCards = sorted.filter(a => a.payload.asset_type === "flash");
  const derived = sorted.filter(a => a.payload.asset_type !== "flash");

  const byInputId = new Map<string, Asset[]>();
  const orphans: Asset[] = [];
  for (const d of derived) {
    const iid = d.payload.input_id as string | undefined;
    if (iid) { const l = byInputId.get(iid) ?? []; l.push(d); byInputId.set(iid, l); }
    else orphans.push(d);
  }

  const flashGroups: FlashGroup[] = flashCards.map((flash, idx) => {
    const iid = flash.payload.input_id as string | undefined;
    return { flash, derived: (iid ? byInputId.get(iid) : undefined) ?? [], turnNumber: idx + 1 };
  });

  const claimedIds = new Set(flashCards.map(f => f.payload.input_id as string).filter(Boolean));
  for (const [iid, list] of byInputId) {
    if (!claimedIds.has(iid)) orphans.push(...list);
  }
  return { flashGroups, orphans };
}

// ── Flash Group Card ───────────────────────────────────────────────────────────

function FlashGroupCard({ group, onNavigate }: { group: FlashGroup; onNavigate: () => void }) {
  const { flash, derived, turnNumber } = group;
  const hasAudio = !!(flash.payload.audio_url);
  return (
    <div style={{ marginBottom: "10px" }}>
      {/* Flash turn header */}
      <div
        onClick={onNavigate}
        style={{
          display: "flex", alignItems: "center", gap: "8px",
          padding: "10px 12px",
          background: "var(--surface)", border: "1px solid var(--border)",
          borderRadius: derived.length > 0 ? "10px 10px 0 0" : "10px",
          boxShadow: "var(--sh-s)", cursor: "pointer",
          borderBottom: derived.length > 0 ? "none" : undefined,
        }}
      >
        <div style={{
          width: "30px", height: "30px", borderRadius: "8px", flexShrink: 0,
          background: "color-mix(in srgb, var(--amber) 12%, transparent)",
          border: "1px solid color-mix(in srgb, var(--amber) 22%, transparent)",
          display: "grid", placeItems: "center", fontSize: "15px",
        }}>{hasAudio ? "🎙" : "⚡"}</div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: "12px", fontWeight: 700, color: "var(--text)" }}>
            {hasAudio ? "录音闪念" : "闪念"} Turn {turnNumber}
          </div>
          <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
            {(flash.payload.content as string ?? "").slice(0, 60) || "无内容"}
          </div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "2px", flexShrink: 0 }}>
          <span style={{ fontSize: "10px", color: "var(--text3)" }}>{formatTime(flash.created_at)}</span>
          <span style={{ fontSize: "14px", color: "var(--blue)" }}>›</span>
        </div>
      </div>

      {/* Derived assets */}
      {derived.length > 0 && (
        <div style={{
          background: "var(--surface)", border: "1px solid var(--border)",
          borderTop: "1px dashed var(--border)", borderRadius: "0 0 10px 10px",
          boxShadow: "var(--sh-s)", overflow: "hidden",
        }}>
          {derived.map((asset, idx) => {
            const t = (asset.payload.asset_type as string) ?? "misc";
            const meta = TYPE_META[t] ?? { icon: "📎", label: t, color: "var(--text2)" };
            const title = getTitle(asset).slice(0, 48);
            return (
              <div
                key={asset.id}
                style={{
                  display: "flex", alignItems: "center", gap: "8px",
                  padding: "8px 12px",
                  borderTop: idx > 0 ? "1px solid var(--border)" : "none",
                }}
              >
                <div style={{
                  width: "24px", height: "24px", borderRadius: "6px", flexShrink: 0,
                  background: `color-mix(in srgb, ${meta.color} 10%, transparent)`,
                  border: `1px solid color-mix(in srgb, ${meta.color} 20%, transparent)`,
                  display: "grid", placeItems: "center", fontSize: "12px",
                }}>{meta.icon}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: "11px", fontWeight: 600, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
                    {title}
                  </div>
                  <div style={{ fontSize: "9px", color: "var(--text3)" }}>{meta.label}</div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ── Orphan asset row ───────────────────────────────────────────────────────────

function OrphanRow({ asset }: { asset: Asset }) {
  const t = (asset.payload.asset_type as string) ?? "misc";
  const meta = TYPE_META[t] ?? { icon: "📎", label: t, color: "var(--text2)" };
  const title = getTitle(asset).slice(0, 52);
  return (
    <div style={{
      display: "flex", alignItems: "center", gap: "8px",
      padding: "10px 12px", marginBottom: "6px",
      background: "var(--surface)", border: "1px solid var(--border)",
      borderRadius: "10px", boxShadow: "var(--sh-s)",
    }}>
      <div style={{
        width: "28px", height: "28px", borderRadius: "8px", flexShrink: 0,
        background: `color-mix(in srgb, ${meta.color} 10%, transparent)`,
        border: `1px solid color-mix(in srgb, ${meta.color} 20%, transparent)`,
        display: "grid", placeItems: "center", fontSize: "14px",
      }}>{meta.icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "12px", fontWeight: 600, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
          {title}
        </div>
        <div style={{ fontSize: "9px", color: "var(--text3)", marginTop: "1px" }}>{meta.label}</div>
      </div>
      <span style={{ fontSize: "10px", color: "var(--text3)", flexShrink: 0 }}>
        {formatTime(asset.created_at)}
      </span>
    </div>
  );
}

// ── Stats summary bar ──────────────────────────────────────────────────────────

function StatsSummary({ assets }: { assets: Asset[] }) {
  const derived = assets.filter(a => a.payload.asset_type !== "flash");
  const flashCount = assets.filter(a => a.payload.asset_type === "flash").length;

  const counts: Record<string, number> = {};
  for (const a of derived) {
    const t = (a.payload.asset_type as string) ?? "misc";
    counts[t] = (counts[t] ?? 0) + 1;
  }

  const chips = Object.entries(counts).map(([t, n]) => {
    const meta = TYPE_META[t] ?? { icon: "📎", label: t, color: "var(--text2)" };
    return { t, n, meta };
  });

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "6px", padding: "8px 12px 4px", flexWrap: "wrap" }}>
      <span style={{ fontSize: "10px", fontWeight: 700, color: "var(--text3)" }}>
        {flashCount} 条闪念
      </span>
      {chips.map(({ t, n, meta }) => (
        <span
          key={t}
          style={{
            fontSize: "9px", fontWeight: 700, padding: "2px 7px", borderRadius: "999px",
            background: `color-mix(in srgb, ${meta.color} 10%, transparent)`,
            border: `1px solid color-mix(in srgb, ${meta.color} 20%, transparent)`,
            color: meta.color,
          }}
        >{meta.icon} {n}</span>
      ))}
    </div>
  );
}

// ── Main DayViewPage ───────────────────────────────────────────────────────────

export default function DayViewPage() {
  const { currentParams, goBack, navTo } = useNav();
  const date = currentParams.date ?? localDateStr(new Date());

  const [assets, setAssets] = useState<Asset[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setIsLoading(true);
    setError(null);
    api.getAssets({ limit: 200 })
      .then(res => {
        if (res.ok) {
          const filtered = (res.assets ?? []).filter(a => assetDateStr(a.created_at) === date);
          setAssets(filtered);
        } else {
          setError(res.error ?? "加载失败");
        }
      })
      .catch(err => setError(String(err)))
      .finally(() => setIsLoading(false));
  }, [date]);

  const { flashGroups, orphans } = buildGroups(assets);
  const total = flashGroups.length + orphans.length;
  const dateLabel = formatDate(date);

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px 8px", flexShrink: 0,
        background: "var(--surface)", borderBottom: "1px solid var(--border)",
      }}>
        <button
          onClick={goBack}
          style={{
            width: "32px", height: "32px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "18px", color: "var(--blue)", cursor: "pointer", flexShrink: 0,
          }}
        >‹</button>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: "15px", fontWeight: 800, color: "var(--text)", letterSpacing: "-0.02em" }}>
            {dateLabel}
          </div>
          {!isLoading && (
            <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
              {total > 0 ? `${total} 条记录` : "暂无记录"}
            </div>
          )}
        </div>
        <button
          style={{
            width: "32px", height: "32px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "14px", cursor: "pointer", color: "var(--text2)",
          }}
          onClick={() => {
            setIsLoading(true);
            api.getAssets({ limit: 200 })
              .then(res => {
                if (res.ok) setAssets((res.assets ?? []).filter(a => assetDateStr(a.created_at) === date));
                else setError(res.error ?? "刷新失败");
              })
              .catch(err => setError(String(err)))
              .finally(() => setIsLoading(false));
          }}
        >↺</button>
      </div>

      {/* Stats */}
      {!isLoading && assets.length > 0 && <StatsSummary assets={assets} />}

      {/* Loading */}
      {isLoading && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "8px", padding: "12px 16px 40px", overflowY: "auto" }}>
          {[1, 2, 3].map(i => (
            <div key={i} style={{
              height: "64px", borderRadius: "10px",
              background: "var(--surface)", border: "1px solid var(--border)",
              opacity: 1 - i * 0.2, animation: "pulse 1.4s ease-in-out infinite",
            }} />
          ))}
          <style>{`@keyframes pulse{0%,100%{opacity:.6}50%{opacity:.3}}`}</style>
        </div>
      )}

      {/* Error */}
      {!isLoading && error && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "32px 24px", gap: "10px", textAlign: "center" }}>
          <div style={{ fontSize: "32px" }}>⚠️</div>
          <div style={{ fontSize: "13px", color: "var(--red)", maxWidth: "240px" }}>加载失败: {error}</div>
        </div>
      )}

      {/* Empty */}
      {!isLoading && !error && total === 0 && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "32px 24px", gap: "12px", textAlign: "center" }}>
          <div style={{ fontSize: "40px" }}>📅</div>
          <div style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)" }}>当日暂无记录</div>
          <div style={{ fontSize: "12px", color: "var(--text2)", maxWidth: "220px", lineHeight: 1.6 }}>
            该日期没有闪念或资产记录
          </div>
        </div>
      )}

      {/* Content */}
      {!isLoading && !error && total > 0 && (
        <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "10px 12px 40px" }}>
          {flashGroups.map(g => (
            <FlashGroupCard
              key={g.flash.id}
              group={g}
              onNavigate={() => navTo("p-flash-sess", {
                session_id: g.flash.session_id ?? "",
                flash_id: g.flash.id,
              })}
            />
          ))}
          {orphans.map(a => <OrphanRow key={a.id} asset={a} />)}
        </div>
      )}
    </div>
  );
}
