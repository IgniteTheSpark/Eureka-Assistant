"use client";

import type { Asset } from "@/lib/types";

const TYPE_META: Record<string, { icon: string; label: string; color: string }> = {
  flash:      { icon: "⚡", label: "闪念", color: "var(--amber)" },
  todo:       { icon: "☐",  label: "待办", color: "var(--blue)" },   // icon overridden by checkbox render
  expense:    { icon: "💰", label: "记账", color: "var(--green)" },
  contact:    { icon: "👤", label: "联系人", color: "var(--purple)" },
  idea:       { icon: "💡", label: "想法", color: "var(--amber)" },
  note:       { icon: "📄", label: "笔记", color: "var(--text2)" },
  transcript: { icon: "🎙", label: "会议", color: "var(--red)" },
  misc:       { icon: "📎", label: "其他", color: "var(--text3)" },
};

function formatTime(isoStr: string) {
  try {
    const d = new Date(isoStr);
    const h = String(d.getHours()).padStart(2, "0");
    const m = String(d.getMinutes()).padStart(2, "0");
    return `${h}:${m}`;
  } catch {
    return "";
  }
}

function getTitle(asset: Asset): string {
  const p = asset.payload;
  const type = (p.asset_type ?? "") as string;
  if (type === "expense") {
    if (p.description) return String(p.description).slice(0, 60);
    if (p.merchant)    return String(p.merchant).slice(0, 60);
    if (p.raw)         return String(p.raw).slice(0, 60);
  }
  if (p.content) return String(p.content).slice(0, 60);
  if (p.title)   return String(p.title).slice(0, 60);
  if (p.name)    return String(p.name).slice(0, 60);
  if (p.raw)     return String(p.raw).slice(0, 60);
  return "（无标题）";
}

function getSubtitle(asset: Asset): string | null {
  const p = asset.payload;
  const type = (p.asset_type ?? "") as string;

  if (type === "expense") {
    const parts: string[] = [];
    if (p.amount != null) parts.push(`¥${p.amount}`);
    if (p.merchant)       parts.push(String(p.merchant));
    if (p.category)       parts.push(String(p.category));
    if (p.currency && p.currency !== "CNY") parts.push(String(p.currency));
    return parts.join(" · ") || null;
  }
  if (type === "todo") {
    // Show only due_date — the checkbox visual conveys status, content is the title
    if (p.due_date) return `截止 ${p.due_date}`;
    return null;
  }
  if (type === "contact") {
    const parts: string[] = [];
    if (p.company) parts.push(String(p.company));
    if (p.title)   parts.push(String(p.title));
    if (p.phone)   parts.push(String(p.phone));
    return parts.join(" · ") || null;
  }
  if (type === "idea" || type === "note") {
    const tags = Array.isArray(p.tags) ? p.tags.join(", ") : null;
    return tags || null;
  }
  return null;
}

export default function AssetCard({ asset }: { asset: Asset }) {
  const type = (asset.payload.asset_type as string) ?? "misc";
  const meta = TYPE_META[type] ?? TYPE_META.misc;
  const title = getTitle(asset);
  const subtitle = getSubtitle(asset);
  const time = formatTime(asset.created_at);
  const isDone = type === "todo" && asset.payload.status === "done";

  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: "10px",
        padding: "10px 14px",
        background: "var(--surface)",
        border: "1px solid var(--border)",
        borderRadius: "var(--r)",
        boxShadow: "var(--sh-s)",
        cursor: "pointer",
        transition: "box-shadow .15s",
      }}
    >
      {/* Icon — todo gets a checkbox visual, others get the emoji */}
      {type === "todo" ? (
        <div
          style={{
            width: "34px",
            height: "34px",
            borderRadius: "8px",
            border: `2px solid ${isDone ? "var(--blue)" : "var(--border)"}`,
            background: isDone ? "var(--blue)" : "transparent",
            display: "grid",
            placeItems: "center",
            flexShrink: 0,
            transition: "all .15s",
          }}
        >
          {isDone && (
            <span style={{ color: "#fff", fontSize: "15px", fontWeight: 700, lineHeight: 1 }}>
              ✓
            </span>
          )}
        </div>
      ) : (
        <div
          style={{
            width: "34px",
            height: "34px",
            borderRadius: "10px",
            background: `color-mix(in srgb, ${meta.color} 12%, transparent)`,
            border: `1px solid color-mix(in srgb, ${meta.color} 22%, transparent)`,
            display: "grid",
            placeItems: "center",
            fontSize: "17px",
            flexShrink: 0,
          }}
        >
          {meta.icon}
        </div>
      )}

      {/* Text */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            fontSize: "12px",
            fontWeight: 600,
            color: "var(--text)",
            overflow: "hidden",
            whiteSpace: "nowrap",
            textOverflow: "ellipsis",
          }}
        >
          {title}
        </div>
        {subtitle && (
          <div
            style={{
              fontSize: "11px",
              color: "var(--text3)",
              marginTop: "2px",
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
            }}
          >
            {subtitle}
          </div>
        )}
      </div>

      {/* Time + type tag */}
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "flex-end",
          gap: "4px",
          flexShrink: 0,
        }}
      >
        <span style={{ fontSize: "10px", color: "var(--text3)" }}>{time}</span>
        <span
          style={{
            fontSize: "9px",
            fontWeight: 700,
            color: meta.color,
            background: `color-mix(in srgb, ${meta.color} 10%, transparent)`,
            border: `1px solid color-mix(in srgb, ${meta.color} 20%, transparent)`,
            borderRadius: "999px",
            padding: "1px 6px",
            letterSpacing: ".04em",
          }}
        >
          {meta.label}
        </span>
      </div>
    </div>
  );
}
