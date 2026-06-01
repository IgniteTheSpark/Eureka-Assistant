"use client";

import { useEffect, useState } from "react";
import { useNav } from "@/context/NavContext";
import { api } from "@/lib/api";
import type { Asset } from "@/lib/types";

// ── Helpers ────────────────────────────────────────────────────────────────────

function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  } catch { return ""; }
}

// ── Type config ────────────────────────────────────────────────────────────────

const TYPE_ORDER = ["todo", "contact", "expense", "idea", "note", "transcript"] as const;
type KnownType = (typeof TYPE_ORDER)[number];

const TYPE_META: Record<string, { icon: string; label: string; color: string; bg: string }> = {
  todo:       { icon: "✅", label: "待办",   color: "var(--blue)",   bg: "color-mix(in srgb, var(--blue) 10%, transparent)"   },
  contact:    { icon: "👤", label: "联系人", color: "var(--purple)", bg: "color-mix(in srgb, var(--purple) 10%, transparent)" },
  expense:    { icon: "💰", label: "消费",   color: "var(--green)",  bg: "color-mix(in srgb, var(--green) 10%, transparent)"  },
  idea:       { icon: "💡", label: "想法",   color: "var(--amber)",  bg: "color-mix(in srgb, var(--amber) 10%, transparent)"  },
  note:       { icon: "📄", label: "笔记",   color: "var(--text2)",  bg: "var(--surface2)"                                    },
  transcript: { icon: "🎙", label: "会议",   color: "var(--text2)",  bg: "var(--surface2)"                                    },
};

function getTitle(a: Asset): string {
  const p = a.payload;
  const t = p.asset_type as string;
  if (t === "contact")  return (p.name ?? "联系人") as string;
  if (t === "todo")     return (p.content ?? p.title ?? "待办") as string;
  if (t === "expense")  return `¥${p.amount ?? ""} ${p.description ?? p.merchant ?? "消费"}`;
  if (t === "idea")     return (p.content ?? p.title ?? "想法") as string;
  return (p.content ?? p.title ?? t) as string;
}

function getSubtitle(a: Asset): string {
  const p = a.payload;
  const t = p.asset_type as string;
  if (t === "todo")    return p.due_date ? `截止 ${p.due_date}` : "";
  if (t === "expense") return [p.merchant, p.category].filter(Boolean).join(" · ");
  if (t === "contact") return [p.company, p.phone].filter(Boolean).join(" · ");
  return "";
}

// ── Sub-list view (single type) ────────────────────────────────────────────────

function TypeListView({
  type,
  assets,
  onBack,
}: {
  type: string;
  assets: Asset[];
  onBack: () => void;
}) {
  const meta = TYPE_META[type] ?? { icon: "📎", label: type, color: "var(--text2)", bg: "var(--surface2)" };

  // For expenses: compute total
  const totalExpense = type === "expense"
    ? assets.reduce((s, a) => s + Number(a.payload.amount ?? 0), 0)
    : null;

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 }}>
      {/* Sub-header */}
      <div style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px 9px", flexShrink: 0,
        background: "var(--surface)", borderBottom: "1px solid var(--border)",
      }}>
        <button
          onClick={onBack}
          style={{
            width: "30px", height: "30px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "18px", color: "var(--blue)", cursor: "pointer",
          }}
        >‹</button>
        <div style={{
          width: "28px", height: "28px", borderRadius: "8px",
          background: meta.bg,
          border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
          display: "grid", placeItems: "center", fontSize: "15px", flexShrink: 0,
        }}>{meta.icon}</div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: "14px", fontWeight: 800, color: "var(--text)" }}>{meta.label}</div>
          <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
            {assets.length} 条{totalExpense !== null ? ` · 合计 ¥${totalExpense.toFixed(0)}` : ""}
          </div>
        </div>
      </div>

      {/* Asset list */}
      <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "10px 12px 40px" }}>
        {assets.length === 0 ? (
          <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text3)", fontSize: "13px" }}>
            暂无{meta.label}
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
            {assets.map(a => {
              const title = getTitle(a).slice(0, 52);
              const sub = getSubtitle(a);
              return (
                <div key={a.id} style={{
                  display: "flex", alignItems: "center", gap: "10px",
                  padding: "10px 12px",
                  background: "var(--surface)", border: "1px solid var(--border)",
                  borderRadius: "var(--rs)", boxShadow: "var(--sh-s)",
                }}>
                  <div style={{
                    width: "30px", height: "30px", borderRadius: "8px", flexShrink: 0,
                    background: meta.bg,
                    border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
                    display: "grid", placeItems: "center", fontSize: "14px",
                  }}>{meta.icon}</div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: "12px", fontWeight: 600, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
                      {title}
                    </div>
                    {sub && (
                      <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>{sub}</div>
                    )}
                  </div>
                  <span style={{ fontSize: "10px", color: "var(--text3)", flexShrink: 0, whiteSpace: "nowrap" }}>
                    {formatTime(a.created_at)}
                  </span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Main Library page ──────────────────────────────────────────────────────────

export default function LibraryPage() {
  const { goBack } = useNav();
  const [assets, setAssets] = useState<Asset[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeType, setActiveType] = useState<string | null>(null);

  useEffect(() => {
    setIsLoading(true);
    api.getAssets({ limit: 200 })
      .then(res => {
        if (res.ok) setAssets((res.assets ?? []).filter(a => a.payload.asset_type !== "flash"));
        else setError(res.error ?? "加载失败");
      })
      .catch(e => setError(String(e)))
      .finally(() => setIsLoading(false));
  }, []);

  // Group by type
  const byType = new Map<string, Asset[]>();
  for (const a of assets) {
    const t = (a.payload.asset_type as string) ?? "misc";
    const arr = byType.get(t) ?? [];
    arr.push(a);
    byType.set(t, arr);
  }

  const sections = [
    ...TYPE_ORDER.filter(t => byType.has(t)).map(t => ({ type: t, assets: byType.get(t)! })),
    ...[...byType.entries()].filter(([t]) => !(TYPE_ORDER as readonly string[]).includes(t)).map(([t, a]) => ({ type: t, assets: a })),
  ];

  const totalExpenseAmt = (byType.get("expense") ?? []).reduce((s, a) => s + Number(a.payload.amount ?? 0), 0);

  // If drilling into a type, show sub-list
  if (activeType) {
    const typeAssets = byType.get(activeType) ?? [];
    return (
      <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
        <TypeListView type={activeType} assets={typeAssets} onBack={() => setActiveType(null)} />
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px 9px", flexShrink: 0,
        background: "var(--surface)", borderBottom: "1px solid var(--border)",
      }}>
        <button
          onClick={goBack}
          style={{
            width: "30px", height: "30px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "18px", color: "var(--blue)", cursor: "pointer",
          }}
        >‹</button>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: "15px", fontWeight: 800, color: "var(--text)", letterSpacing: "-0.02em" }}>
            Eureka Library
          </div>
          {!isLoading && (
            <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
              {assets.length} 条资产 · {sections.length} 种类型
            </div>
          )}
        </div>
        <button
          style={{
            width: "30px", height: "30px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center", fontSize: "15px", cursor: "pointer",
          }}
          title="搜索"
        >🔍</button>
      </div>

      {/* Loading */}
      {isLoading && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "8px", padding: "14px 12px" }}>
          {[1, 2, 3, 4].map(i => (
            <div key={i} style={{
              height: "64px", borderRadius: "var(--r)",
              background: "var(--surface)", border: "1px solid var(--border)",
              opacity: 1 - i * 0.18, animation: "pulse 1.4s ease-in-out infinite",
            }} />
          ))}
          <style>{`@keyframes pulse{0%,100%{opacity:.6}50%{opacity:.3}}`}</style>
        </div>
      )}

      {/* Error */}
      {!isLoading && error && (
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", padding: "32px 24px", flexDirection: "column", gap: "10px", textAlign: "center" }}>
          <div style={{ fontSize: "32px" }}>⚠️</div>
          <div style={{ fontSize: "13px", color: "var(--red)" }}>加载失败: {error}</div>
        </div>
      )}

      {/* Content */}
      {!isLoading && !error && (
        <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "12px 12px 40px" }}>
          {assets.length === 0 ? (
            <div style={{ textAlign: "center", padding: "48px 0", flexDirection: "column", display: "flex", alignItems: "center", gap: "12px" }}>
              <div style={{ fontSize: "40px" }}>📚</div>
              <div style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)" }}>知识库为空</div>
              <div style={{ fontSize: "12px", color: "var(--text2)" }}>记录闪念后，资产会自动归档到这里</div>
            </div>
          ) : (
            <>
              {/* Expense summary strip */}
              {totalExpenseAmt > 0 && (
                <div style={{
                  padding: "12px 14px", marginBottom: "12px",
                  background: "color-mix(in srgb, var(--green) 7%, transparent)",
                  border: "1px solid color-mix(in srgb, var(--green) 18%, transparent)",
                  borderRadius: "var(--r)",
                  display: "flex", alignItems: "center", gap: "10px",
                }}>
                  <span style={{ fontSize: "20px" }}>💰</span>
                  <div>
                    <div style={{ fontSize: "11px", color: "var(--text3)", fontWeight: 600 }}>累计消费</div>
                    <div style={{ fontSize: "20px", fontWeight: 800, color: "var(--green)", letterSpacing: "-0.02em" }}>
                      ¥{totalExpenseAmt.toFixed(0)}
                    </div>
                  </div>
                </div>
              )}

              {/* Type rows */}
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                {sections.map(({ type, assets: sAssets }) => {
                  const meta = TYPE_META[type] ?? { icon: "📎", label: type, color: "var(--text2)", bg: "var(--surface2)" };
                  const expAmt = type === "expense"
                    ? sAssets.reduce((s, a) => s + Number(a.payload.amount ?? 0), 0)
                    : null;
                  const badge = expAmt !== null
                    ? `¥${expAmt.toFixed(0)}`
                    : `${sAssets.length} 条`;

                  return (
                    <div
                      key={type}
                      onClick={() => setActiveType(type)}
                      style={{
                        display: "flex", alignItems: "center", gap: "12px",
                        padding: "13px 14px",
                        background: "var(--surface)", border: "1px solid var(--border)",
                        borderRadius: "var(--r)", boxShadow: "var(--sh-s)", cursor: "pointer",
                      }}
                    >
                      <div style={{
                        width: "38px", height: "38px", borderRadius: "11px", flexShrink: 0,
                        background: meta.bg,
                        border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
                        display: "grid", placeItems: "center", fontSize: "18px",
                      }}>{meta.icon}</div>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: "13px", fontWeight: 700, color: "var(--text)" }}>{meta.label}</div>
                        <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
                          {sAssets.length} 条记录
                        </div>
                      </div>
                      <span style={{
                        fontSize: "12px", fontWeight: 700,
                        color: meta.color,
                      }}>{badge}</span>
                      <span style={{ fontSize: "16px", color: "var(--text3)" }}>›</span>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}
