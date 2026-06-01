"use client";

export type StreamTab =
  | "all" | "flash" | "todo" | "expense" | "contact" | "idea" | "transcript";

const TABS: { id: StreamTab; label: string }[] = [
  { id: "all",        label: "全部" },
  { id: "flash",      label: "⚡ 闪念" },
  { id: "todo",       label: "✅ 待办" },
  { id: "expense",    label: "💰 记账" },
  { id: "contact",    label: "👤 联系人" },
  { id: "idea",       label: "💡 想法" },
  { id: "transcript", label: "📅 日程" },
];

interface TabBarProps {
  activeTab: StreamTab;
  onTabChange: (t: StreamTab) => void;
}

export default function TabBar({ activeTab, onTabChange }: TabBarProps) {
  return (
    <div
      className="no-scrollbar"
      style={{
        display: "flex",
        background: "var(--surface)",
        borderBottom: "2px solid var(--border)",
        padding: "0 12px",
        overflowX: "auto",
        flexShrink: 0,
      }}
    >
      {TABS.map((tab) => (
        <button
          key={tab.id}
          onClick={() => onTabChange(tab.id)}
          style={{
            fontSize: "12px",
            fontWeight: 600,
            color: activeTab === tab.id ? "var(--blue)" : "var(--text3)",
            padding: "9px 12px",
            whiteSpace: "nowrap",
            cursor: "pointer",
            transition: "all .15s",
            flexShrink: 0,
            background: "transparent",
            border: "none",
            borderBottom: `2px solid ${activeTab === tab.id ? "var(--blue)" : "transparent"}`,
            marginBottom: "-2px",
          }}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}
