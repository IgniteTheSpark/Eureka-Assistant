"use client";

/**
 * WorkspacePage — 所有内容的分类管理入口
 *
 * 设计规范：docs/workspace-spec.md
 *
 * 系统区（始终置顶）：
 *   👤 联系人（contacts 表，独立体系）
 *   📁 文件（占位，待实现）
 *   ⚡ 闪念（assets 表，asset_type=flash，is_followup=false）
 *
 * 资产区：
 *   todo / idea / note / expense / misc（assets 表）
 *   新 Skill 产出的 asset_type 自动追加末尾
 *
 * 不展示：flash 在资产区（改为系统区）、contact（独立）、transcript（原始）
 */

import { useEffect, useState } from "react";
import { useNav } from "@/context/NavContext";
import { api } from "@/lib/api";
import type { Asset, ContactItem } from "@/lib/types";

// ── Source badge (tappable → jump to session) ─────────────────────────────────

function SourceBadge({ asset }: { asset: Asset }) {
  const { navTo } = useNav();
  const src = asset.payload.source_type as string | undefined;
  if (!src || src === "manual") return null;
  const label = src === "session" ? "⚡ 闪念" : src === "file_analysis" ? "📁 文件" : src;
  const canNav = !!(asset.session_id);
  return (
    <span
      onClick={canNav ? (e) => { e.stopPropagation(); navTo("p-flash-sess", { session_id: asset.session_id! }); } : undefined}
      style={{
        fontSize: "9px", padding: "1px 5px", borderRadius: "4px",
        background: "var(--surface2)", border: "1px solid var(--border)",
        color: "var(--text3)", flexShrink: 0, whiteSpace: "nowrap",
        cursor: canNav ? "pointer" : "default",
        textDecoration: canNav ? "underline dotted" : "none",
      }}
    >{label}</span>
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  } catch { return ""; }
}

function formatDate(iso: string): string {
  try {
    const d = new Date(iso);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  } catch { return ""; }
}

function dateLabel(iso: string): string {
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
  const d = new Date(iso); d.setHours(0, 0, 0, 0);
  if (d.getTime() === today.getTime()) return "今天";
  if (d.getTime() === yesterday.getTime()) return "昨天";
  return formatDate(iso);
}

// ── Section registry ───────────────────────────────────────────────────────────

const ASSET_ORDER = ["todo", "idea", "note", "expense", "misc"] as const;

const ASSET_META: Record<string, { icon: string; label: string; color: string; bg: string }> = {
  todo:    { icon: "✅", label: "待办", color: "var(--blue)",  bg: "color-mix(in srgb, var(--blue) 10%, transparent)"  },
  idea:    { icon: "💡", label: "想法", color: "var(--amber)", bg: "color-mix(in srgb, var(--amber) 10%, transparent)" },
  note:    { icon: "📄", label: "笔记", color: "var(--text2)", bg: "var(--surface2)"                                   },
  expense: { icon: "💰", label: "消费", color: "var(--green)", bg: "color-mix(in srgb, var(--green) 10%, transparent)" },
  misc:    { icon: "📎", label: "杂项", color: "var(--text3)", bg: "var(--surface2)"                                   },
};

function getAssetMeta(type: string) {
  return ASSET_META[type] ?? { icon: "📦", label: type, color: "var(--text2)", bg: "var(--surface2)" };
}

// ── Asset display helpers ──────────────────────────────────────────────────────

function getAssetTitle(a: Asset): string {
  const p = a.payload;
  const t = p.asset_type as string;
  if (t === "todo")    return (p.content ?? p.title ?? "待办") as string;
  if (t === "expense") return `¥${p.amount ?? ""} ${p.description ?? p.merchant ?? "消费"}`;
  if (t === "idea")    return (p.title ?? p.content ?? "想法") as string;
  if (t === "misc")    return (p.content ?? p.title ?? "杂项记录") as string;
  return (p.content ?? p.title ?? t) as string;
}

function formatDueRelativeWS(dueRaw: unknown): string {
  if (!dueRaw) return "";
  const s = String(dueRaw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return s.slice(0, 16);
  const today = new Date(); today.setHours(12, 0, 0, 0);
  const due = new Date(`${m[1]}-${m[2]}-${m[3]}T12:00:00`);
  const diff = Math.round((due.getTime() - today.getTime()) / 86400000);
  if (diff < -1) return `已逾期 · ${Number(m[2])}/${Number(m[3])}`;
  if (diff === -1) return "昨天截止";
  if (diff === 0)  return "今天截止";
  if (diff === 1)  return "明天截止";
  if (diff === 2)  return "后天截止";
  return `截止 ${Number(m[2])}/${Number(m[3])}`;
}

function getAssetSubtitle(a: Asset): string {
  const p = a.payload;
  const t = p.asset_type as string;
  if (t === "todo") {
    if (p.status === "pending_confirmation") return "待认领";
    if (p.status === "done") return "已完成";
    return p.due_date ? formatDueRelativeWS(p.due_date) : "";
  }
  if (t === "expense") return [p.merchant, p.category].filter(Boolean).join(" · ");
  if (t === "note")    return (p.note_type ?? "") as string;
  return "";
}


// ── Row components ─────────────────────────────────────────────────────────────

function AssetRow({
  asset, meta, onClick,
}: { asset: Asset; meta: ReturnType<typeof getAssetMeta>; onClick: () => void }) {
  const title             = getAssetTitle(asset).slice(0, 52);
  const sub               = getAssetSubtitle(asset);
  const status            = asset.payload.status as string | undefined;
  const isPendingConfirm  = status === "pending_confirmation";
  const isDone            = status === "done";
  const isOverdue         = sub.startsWith("已逾期");
  const isTodayDue        = sub === "今天截止";
  const subtitleColor     = isOverdue ? "var(--red)" : isTodayDue ? "var(--amber)" : "var(--text3)";

  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px",
        background: isDone ? "var(--surface2)" : "var(--surface)",
        border: `1px solid ${isPendingConfirm ? "color-mix(in srgb, var(--border) 60%, transparent)" : "var(--border)"}`,
        borderRadius: "var(--rs)", boxShadow: "var(--sh-s)",
        opacity: isDone ? 0.6 : isPendingConfirm ? 0.75 : 1, cursor: "pointer",
      }}
    >
      <div style={{
        width: "30px", height: "30px", borderRadius: "8px", flexShrink: 0,
        background: meta.bg,
        border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
        display: "grid", placeItems: "center", fontSize: "14px",
      }}>{meta.icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: "12px", fontWeight: isDone ? 400 : 600,
          color: isDone ? "var(--text3)" : "var(--text)",
          overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
          textDecoration: isDone ? "line-through" : "none",
        }}>
          {title}
        </div>
        {sub && (
          <div style={{
            fontSize: "10px", color: subtitleColor, marginTop: "1px",
            fontWeight: (isOverdue || isTodayDue) ? 600 : 400,
          }}>{sub}</div>
        )}
      </div>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "3px", flexShrink: 0 }}>
        <SourceBadge asset={asset} />
        <span style={{ fontSize: "10px", color: "var(--text3)", whiteSpace: "nowrap" }}>{formatTime(asset.created_at)}</span>
      </div>
    </div>
  );
}

function ContactRow({ contact, onClick }: { contact: ContactItem; onClick: () => void }) {
  const sub = [contact.company, contact.title].filter(Boolean).join(" · ");
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px",
        background: "var(--surface)", border: "1px solid var(--border)",
        borderRadius: "var(--rs)", boxShadow: "var(--sh-s)", cursor: "pointer",
      }}
    >
      <div style={{
        width: "30px", height: "30px", borderRadius: "50%", flexShrink: 0,
        background: "color-mix(in srgb, var(--purple) 15%, transparent)",
        border: "1px solid color-mix(in srgb, var(--purple) 25%, transparent)",
        display: "grid", placeItems: "center",
        fontSize: "12px", fontWeight: 800, color: "var(--purple)",
      }}>
        {contact.name.slice(0, 1)}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "12px", fontWeight: 600, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
          {contact.name}
        </div>
        {sub && <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>{sub}</div>}
      </div>
      {contact.phone && (
        <span style={{ fontSize: "10px", color: "var(--text3)", flexShrink: 0, whiteSpace: "nowrap" }}>{contact.phone}</span>
      )}
      <span style={{ fontSize: "14px", color: "var(--text3)" }}>›</span>
    </div>
  );
}

// ── Contact detail sheet (slide-up panel) ─────────────────────────────────────

function ContactDetailSheet({
  contact, onClose,
}: { contact: ContactItem; onClose: () => void }) {
  const inputStyle: React.CSSProperties = {
    width: "100%", boxSizing: "border-box",
    background: "var(--surface2)", border: "1px solid var(--border)",
    borderRadius: "var(--rs)", padding: "8px 10px",
    fontSize: "13px", color: "var(--text)", outline: "none",
  };
  const labelStyle: React.CSSProperties = {
    fontSize: "10px", fontWeight: 700, color: "var(--text3)",
    letterSpacing: "0.05em", marginBottom: "4px", display: "block",
  };

  return (
    <>
      <div onClick={onClose} style={{ position: "absolute", inset: 0, zIndex: 20, background: "rgba(10,14,30,.3)" }} />
      <div style={{
        position: "absolute", bottom: 0, left: 0, right: 0, zIndex: 30,
        background: "var(--surface)", borderRadius: "20px 20px 0 0",
        boxShadow: "0 -4px 32px rgba(15,23,42,.18)",
        padding: "0 0 32px",
        maxHeight: "75%", overflowY: "auto",
      }}>
        {/* Handle */}
        <div style={{ display: "flex", justifyContent: "center", padding: "12px 0 4px" }}>
          <div style={{ width: "36px", height: "4px", borderRadius: "2px", background: "var(--border)" }} />
        </div>
        {/* Avatar + name */}
        <div style={{ display: "flex", alignItems: "center", gap: "12px", padding: "8px 16px 16px" }}>
          <div style={{
            width: "44px", height: "44px", borderRadius: "50%", flexShrink: 0,
            background: "color-mix(in srgb, var(--purple) 15%, transparent)",
            border: "1px solid color-mix(in srgb, var(--purple) 25%, transparent)",
            display: "grid", placeItems: "center",
            fontSize: "18px", fontWeight: 800, color: "var(--purple)",
          }}>{contact.name.slice(0, 1)}</div>
          <div>
            <div style={{ fontSize: "16px", fontWeight: 800, color: "var(--text)" }}>{contact.name}</div>
            {contact.company && <div style={{ fontSize: "11px", color: "var(--text3)", marginTop: "2px" }}>{contact.company}{contact.title ? ` · ${contact.title}` : ""}</div>}
          </div>
          <button onClick={onClose} style={{ marginLeft: "auto", width: "28px", height: "28px", borderRadius: "50%", background: "var(--surface2)", border: "1px solid var(--border)", display: "grid", placeItems: "center", fontSize: "14px", color: "var(--text3)", cursor: "pointer" }}>×</button>
        </div>
        {/* Fields */}
        <div style={{ padding: "0 16px", display: "flex", flexDirection: "column", gap: "12px" }}>
          {[
            { label: "电话", value: contact.phone },
            { label: "邮箱", value: contact.email },
            { label: "公司", value: contact.company },
            { label: "职位", value: contact.title },
          ].filter(f => f.value).map(f => (
            <div key={f.label}>
              <span style={labelStyle}>{f.label.toUpperCase()}</span>
              <div style={inputStyle}>{f.value}</div>
            </div>
          ))}
          {contact.notes && contact.notes.length > 0 && (
            <div>
              <span style={labelStyle}>备注</span>
              <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
                {contact.notes.map((n, i) => (
                  <div key={i} style={{ ...inputStyle, fontSize: "12px" }}>{n}</div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
}

function FlashRow({
  flash, onClick,
}: { flash: Asset; onClick: () => void }) {
  const summary = (flash.payload.summary ?? flash.payload.transcript ?? "闪念") as string;
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "flex-start", gap: "10px",
        padding: "10px 12px",
        background: "var(--surface)", border: "1px solid var(--border)",
        borderRadius: "var(--rs)", boxShadow: "var(--sh-s)", cursor: "pointer",
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: "12px", fontWeight: 500, color: "var(--text)",
          display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical",
          overflow: "hidden",
        }}>
          {summary.slice(0, 120)}
        </div>
      </div>
      <span style={{ fontSize: "10px", color: "var(--text3)", flexShrink: 0, paddingTop: "1px", whiteSpace: "nowrap" }}>
        {formatTime(flash.created_at)}
      </span>
    </div>
  );
}

// ── Sub-list shared header ─────────────────────────────────────────────────────

function SubListHeader({
  icon, label, count, meta, onBack,
}: {
  icon: string; label: string; count: number;
  meta: { color: string; bg: string };
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
        background: meta.bg,
        border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
        display: "grid", placeItems: "center", fontSize: "15px", flexShrink: 0,
      }}>{icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "14px", fontWeight: 800, color: "var(--text)" }}>{label}</div>
        <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>{count} 条</div>
      </div>
    </div>
  );
}

// ── Flash sub-list ─────────────────────────────────────────────────────────────

function FlashListView({ flashes, onBack }: { flashes: Asset[]; onBack: () => void }) {
  const { navTo } = useNav();

  // Group by calendar date (today / yesterday / older dates)
  type Group = { label: string; key: string; items: Asset[] };
  const groupMap = new Map<string, Asset[]>();
  for (const f of flashes) {
    const key = formatDate(f.created_at);
    const arr = groupMap.get(key) ?? [];
    arr.push(f);
    groupMap.set(key, arr);
  }
  const groups: Group[] = [...groupMap.entries()].map(([key, items]) => ({
    key,
    label: dateLabel(items[0].created_at),
    items,
  }));

  const handleFlashClick = (flash: Asset) => {
    if (flash.session_id) {
      navTo("p-flash-sess", { session_id: flash.session_id });
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 }}>
      <SubListHeader
        icon="⚡" label="闪念" count={flashes.length}
        meta={{ color: "var(--amber)", bg: "color-mix(in srgb, var(--amber) 10%, transparent)" }}
        onBack={onBack}
      />
      <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "10px 12px 40px" }}>
        {flashes.length === 0 ? (
          <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text3)", fontSize: "13px" }}>暂无闪念</div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {groups.map(g => (
              <div key={g.key}>
                <div style={{
                  fontSize: "10px", fontWeight: 700, color: "var(--text3)",
                  letterSpacing: "0.05em", marginBottom: "6px", padding: "0 2px",
                }}>{g.label}</div>
                <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                  {g.items.map(f => (
                    <FlashRow key={f.id} flash={f} onClick={() => handleFlashClick(f)} />
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Contacts sub-list ─────────────────────────────────────────────────────────

function ContactsListView({ contacts, onBack }: { contacts: ContactItem[]; onBack: () => void }) {
  const [selected, setSelected] = useState<ContactItem | null>(null);
  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, position: "relative" }}>
      <SubListHeader
        icon="👤" label="联系人" count={contacts.length}
        meta={{ color: "var(--purple)", bg: "color-mix(in srgb, var(--purple) 10%, transparent)" }}
        onBack={onBack}
      />
      <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "10px 12px 40px" }}>
        {contacts.length === 0
          ? <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text3)", fontSize: "13px" }}>暂无联系人</div>
          : <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
              {contacts.map(c => <ContactRow key={c.id} contact={c} onClick={() => setSelected(c)} />)}
            </div>
        }
      </div>
      {selected && <ContactDetailSheet contact={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

// ── Asset sub-list ─────────────────────────────────────────────────────────────

function AssetListView({
  type, assets, onBack,
}: { type: string; assets: Asset[]; onBack: () => void }) {
  const { navTo } = useNav();
  const meta = getAssetMeta(type);
  const pendingConfirm = type === "todo" ? assets.filter(a => a.payload.status === "pending_confirmation") : [];
  const activeAssets   = type === "todo" ? assets.filter(a => a.payload.status !== "pending_confirmation") : assets;

  const handleRowClick = (asset: Asset) => {
    navTo("p-asset-detail", { asset_id: asset.id, asset_json: JSON.stringify(asset) });
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 }}>
      <SubListHeader
        icon={meta.icon} label={meta.label} count={assets.length}
        meta={{ color: meta.color, bg: meta.bg }}
        onBack={onBack}
      />
      <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "10px 12px 40px" }}>
        {assets.length === 0
          ? <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text3)", fontSize: "13px" }}>暂无{meta.label}</div>
          : <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
              {pendingConfirm.length > 0 && (
                <>
                  <div style={{ fontSize: "10px", fontWeight: 700, color: "var(--text3)", padding: "4px 2px 2px", letterSpacing: "0.04em" }}>待认领</div>
                  {pendingConfirm.map(a => <AssetRow key={a.id} asset={a} meta={meta} onClick={() => handleRowClick(a)} />)}
                  {activeAssets.length > 0 && (
                    <div style={{ fontSize: "10px", fontWeight: 700, color: "var(--text3)", padding: "8px 2px 2px", letterSpacing: "0.04em" }}>进行中</div>
                  )}
                </>
              )}
              {activeAssets.map(a => <AssetRow key={a.id} asset={a} meta={meta} onClick={() => handleRowClick(a)} />)}
            </div>
        }
      </div>
    </div>
  );
}

// ── Section entry card ─────────────────────────────────────────────────────────

function SectionCard({
  icon, label, color, bg, count, badge, onClick,
}: {
  icon: string; label: string; color: string; bg: string;
  count: number; badge?: string;
  onClick: () => void;
}) {
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: "12px",
        padding: "13px 14px",
        background: "var(--surface)", border: "1px solid var(--border)",
        borderRadius: "var(--r)", boxShadow: "var(--sh-s)", cursor: "pointer",
      }}
    >
      <div style={{
        width: "38px", height: "38px", borderRadius: "11px", flexShrink: 0,
        background: bg,
        border: `1px solid color-mix(in srgb, ${color} 22%, transparent)`,
        display: "grid", placeItems: "center", fontSize: "18px",
      }}>{icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "13px", fontWeight: 700, color: "var(--text)" }}>{label}</div>
        <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>{count} 条记录</div>
      </div>
      {badge && <span style={{ fontSize: "12px", fontWeight: 700, color }}>{badge}</span>}
      <span style={{ fontSize: "16px", color: "var(--text3)" }}>›</span>
    </div>
  );
}

// ── Active sub-view type ───────────────────────────────────────────────────────

type ActiveView =
  | { kind: "contacts" }
  | { kind: "files" }
  | { kind: "flash" }
  | { kind: "asset"; type: string };

// ── Main Workspace page ────────────────────────────────────────────────────────

// Asset types excluded from the ASSETS section (handled separately or hidden)
const ASSET_EXCLUDED = new Set(["contact", "transcript"]);
// flash is pulled out into its own system section, not shown in asset grid

export default function WorkspacePage({ onClose }: { onClose?: () => void }) {
  const { goBack, usePageVisitCount } = useNav();
  const handleBack = onClose ?? goBack;

  const [assets,   setAssets]   = useState<Asset[]>([]);
  const [flashes,  setFlashes]  = useState<Asset[]>([]);
  const [contacts, setContacts] = useState<ContactItem[]>([]);
  const [isLoading, setLoading] = useState(true);
  const [error,    setError]    = useState<string | null>(null);
  const [active,   setActive]   = useState<ActiveView | null>(null);

  const visitCount = usePageVisitCount("p-workspace");

  useEffect(() => {
    setLoading(true);
    Promise.all([
      api.getAssets({ limit: 200 }),
      api.getContacts({ limit: 200 }),
    ]).then(([assetRes, contactRes]) => {
      if (assetRes.ok) {
        const all = assetRes.assets ?? [];
        // Flash system section: non-followup flashes only
        setFlashes(all.filter(a =>
          a.payload.asset_type === "flash" && !a.payload.is_followup
        ));
        // Asset section: exclude flash, contact, transcript
        setAssets(all.filter(a =>
          !ASSET_EXCLUDED.has(a.payload.asset_type as string) &&
          a.payload.asset_type !== "flash"
        ));
      } else {
        setError(assetRes.error ?? "资产加载失败");
      }
      if (contactRes.ok) {
        setContacts(contactRes.contacts ?? []);
      }
    }).catch(e => setError(String(e)))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visitCount]);

  // Group assets by type
  const byType = new Map<string, Asset[]>();
  for (const a of assets) {
    const t = (a.payload.asset_type as string) ?? "misc";
    const arr = byType.get(t) ?? []; arr.push(a); byType.set(t, arr);
  }

  // Drill-down view
  if (active) {
    return (
      <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
        {active.kind === "contacts" && (
          <ContactsListView contacts={contacts} onBack={() => setActive(null)} />
        )}
        {active.kind === "flash" && (
          <FlashListView flashes={flashes} onBack={() => setActive(null)} />
        )}
        {active.kind === "files" && (
          <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 }}>
            <SubListHeader
              icon="📁" label="文件" count={0}
              meta={{ color: "var(--blue)", bg: "color-mix(in srgb, var(--blue) 10%, transparent)" }}
              onBack={() => setActive(null)}
            />
            <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", flexDirection: "column", gap: "10px", color: "var(--text3)", fontSize: "13px" }}>
              <div style={{ fontSize: "32px" }}>📁</div>
              <div>文件功能即将上线</div>
            </div>
          </div>
        )}
        {active.kind === "asset" && (
          <AssetListView
            type={active.type}
            assets={byType.get(active.type) ?? []}
            onBack={() => setActive(null)}
          />
        )}
      </div>
    );
  }

  // Asset sections: known types first, then unknown new skill types
  const assetSections = [
    ...ASSET_ORDER.filter(t => byType.has(t)).map(t => ({ type: t, assets: byType.get(t)! })),
    ...[...byType.entries()]
      .filter(([t]) => !(ASSET_ORDER as readonly string[]).includes(t))
      .map(([t, a]) => ({ type: t, assets: a })),
  ];

  const totalCount = contacts.length + flashes.length + assets.length;

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)" }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px 9px", flexShrink: 0,
        background: "var(--surface)", borderBottom: "1px solid var(--border)",
      }}>
        <button onClick={handleBack} style={{
          width: "30px", height: "30px", borderRadius: "50%",
          background: "var(--surface2)", border: "1px solid var(--border)",
          display: "grid", placeItems: "center",
          fontSize: "18px", color: "var(--blue)", cursor: "pointer",
        }}>‹</button>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: "15px", fontWeight: 800, color: "var(--text)", letterSpacing: "-0.02em" }}>
            Workspace
          </div>
          {!isLoading && (
            <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
              {totalCount} 条内容
            </div>
          )}
        </div>
        <button style={{
          width: "30px", height: "30px", borderRadius: "50%",
          background: "var(--surface2)", border: "1px solid var(--border)",
          display: "grid", placeItems: "center", fontSize: "15px", cursor: "pointer",
        }} title="搜索">🔍</button>
      </div>

      {/* Loading */}
      {isLoading && (
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "8px", padding: "14px 12px" }}>
          {[1, 2, 3, 4, 5].map(i => (
            <div key={i} style={{
              height: "64px", borderRadius: "var(--r)",
              background: "var(--surface)", border: "1px solid var(--border)",
              opacity: 1 - i * 0.15, animation: "pulse 1.4s ease-in-out infinite",
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

          {/* System sections: Contacts + Files + Flash */}
          <div style={{ display: "flex", flexDirection: "column", gap: "8px", marginBottom: assetSections.length > 0 ? "16px" : "0" }}>
            <SectionCard
              icon="👤" label="联系人"
              color="var(--purple)" bg="color-mix(in srgb, var(--purple) 10%, transparent)"
              count={contacts.length}
              onClick={() => setActive({ kind: "contacts" })}
            />
            <SectionCard
              icon="📁" label="文件"
              color="var(--blue)" bg="color-mix(in srgb, var(--blue) 10%, transparent)"
              count={0}
              onClick={() => setActive({ kind: "files" })}
            />
            <SectionCard
              icon="⚡" label="闪念"
              color="var(--amber)" bg="color-mix(in srgb, var(--amber) 10%, transparent)"
              count={flashes.length}
              onClick={() => setActive({ kind: "flash" })}
            />
          </div>

          {/* Divider */}
          {assetSections.length > 0 && (
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "12px" }}>
              <span style={{ fontSize: "10px", fontWeight: 700, color: "var(--text3)", letterSpacing: "0.06em" }}>ASSETS</span>
              <div style={{ flex: 1, height: "1px", background: "var(--border)" }} />
            </div>
          )}

          {/* Asset sections */}
          <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
            {assetSections.map(({ type, assets: sAssets }) => {
              const meta = getAssetMeta(type);
              return (
                <SectionCard
                  key={type}
                  icon={meta.icon} label={meta.label}
                  color={meta.color} bg={meta.bg}
                  count={sAssets.length}
                  onClick={() => setActive({ kind: "asset", type })}
                />
              );
            })}
          </div>

          {/* True empty state */}
          {assetSections.length === 0 && contacts.length === 0 && flashes.length === 0 && (
            <div style={{ textAlign: "center", padding: "32px 0", flexDirection: "column", display: "flex", alignItems: "center", gap: "12px" }}>
              <div style={{ fontSize: "36px" }}>🗂</div>
              <div style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)" }}>Workspace 为空</div>
              <div style={{ fontSize: "12px", color: "var(--text2)" }}>通过闪念录入内容，结构化资产会自动归档到这里</div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
