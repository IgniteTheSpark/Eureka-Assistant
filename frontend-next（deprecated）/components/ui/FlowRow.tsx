"use client";

interface FlowRowProps {
  time?: string;
  icon?: string;
  title: string;
  subtitle?: string;
  badge?: { label: string; variant: "pending" | "done" };
  onClick?: () => void;
}

export default function FlowRow({ time, icon, title, subtitle, badge, onClick }: FlowRowProps) {
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex",
        alignItems: "center",
        gap: "8px",
        padding: "7px 4px",
        borderRadius: "var(--rs)",
        cursor: "pointer",
        transition: "background .12s",
        minHeight: "38px",
      }}
    >
      {time && (
        <span
          style={{
            fontSize: "11px",
            fontWeight: 600,
            color: "var(--text3)",
            width: "36px",
            flexShrink: 0,
            textAlign: "right",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {time}
        </span>
      )}
      {icon && (
        <span style={{ fontSize: "14px", width: "20px", textAlign: "center", flexShrink: 0 }}>
          {icon}
        </span>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            fontSize: "13px",
            fontWeight: 500,
            color: "var(--text)",
            whiteSpace: "nowrap",
            overflow: "hidden",
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
              marginTop: "1px",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {subtitle}
          </div>
        )}
      </div>
      {badge && (
        <span
          style={{
            fontSize: "9px",
            fontWeight: 700,
            borderRadius: "999px",
            padding: "2px 7px",
            flexShrink: 0,
            background:
              badge.variant === "pending"
                ? "var(--amber-t)"
                : "rgba(16,185,129,.12)",
            color:
              badge.variant === "pending" ? "var(--amber)" : "#059669",
          }}
        >
          {badge.label}
        </span>
      )}
      <span style={{ color: "var(--text3)", fontSize: "14px", fontWeight: 300 }}>›</span>
    </div>
  );
}
