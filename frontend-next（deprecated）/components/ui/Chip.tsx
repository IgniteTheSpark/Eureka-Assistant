"use client";

type ChipVariant = "todo" | "idea" | "expense" | "contact" | "transcript" | "note" | "warn";

const STYLES: Record<ChipVariant, React.CSSProperties> = {
  todo: { background: "var(--blue6)", color: "var(--blue)", borderColor: "var(--blue16)" },
  idea: { background: "var(--purple-t)", color: "var(--purple)", borderColor: "rgba(124,58,237,.2)" },
  expense: { background: "var(--amber-t)", color: "var(--amber)", borderColor: "rgba(217,119,6,.2)" },
  contact: { background: "var(--green-t)", color: "var(--green)", borderColor: "rgba(22,163,74,.2)" },
  transcript: { background: "rgba(148,163,184,.10)", color: "var(--text2)", borderColor: "var(--border-m)" },
  note: { background: "rgba(59,130,246,.07)", color: "#2563eb", borderColor: "rgba(37,99,235,.14)" },
  warn: { background: "var(--amber-t)", color: "var(--amber)", borderColor: "rgba(217,119,6,.22)" },
};

interface ChipProps {
  variant?: ChipVariant;
  icon?: string;
  label: string;
  onClick?: () => void;
}

export default function Chip({ variant = "note", icon, label, onClick }: ChipProps) {
  return (
    <span
      onClick={onClick}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "4px",
        fontSize: "10px",
        fontWeight: 600,
        padding: "4px 9px",
        borderRadius: "999px",
        border: "1px solid",
        cursor: onClick ? "pointer" : "default",
        transition: "all .15s",
        ...STYLES[variant],
      }}
    >
      {icon && <span>{icon}</span>}
      {label}
    </span>
  );
}
