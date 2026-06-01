"use client";

import { useNav } from "@/context/NavContext";

interface PlaceholderPageProps {
  title: string;
  icon: string;
  description: string;
}

export default function PlaceholderPage({ title, icon, description }: PlaceholderPageProps) {
  const { goBack } = useNav();

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        flex: 1,
        minHeight: 0,
        background: "var(--bg)",
      }}
    >
      {/* Top bar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "10px",
          padding: "12px 14px 10px",
          flexShrink: 0,
          background: "var(--surface)",
          borderBottom: "1px solid var(--border)",
        }}
      >
        <button
          onClick={goBack}
          style={{
            width: "32px",
            height: "32px",
            borderRadius: "50%",
            background: "var(--surface2)",
            border: "1px solid var(--border)",
            display: "grid",
            placeItems: "center",
            fontSize: "18px",
            color: "var(--blue)",
            flexShrink: 0,
            cursor: "pointer",
          }}
        >
          ‹
        </button>
        <div
          style={{
            fontSize: "16px",
            fontWeight: 800,
            color: "var(--text)",
            letterSpacing: "-0.02em",
          }}
        >
          {title}
        </div>
      </div>

      {/* Content */}
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          padding: "32px 24px",
          gap: "12px",
          textAlign: "center",
        }}
      >
        <div style={{ fontSize: "52px" }}>{icon}</div>
        <div style={{ fontSize: "16px", fontWeight: 700, color: "var(--text)" }}>{title}</div>
        <div style={{ fontSize: "13px", color: "var(--text2)", lineHeight: 1.7, maxWidth: "240px" }}>
          {description}
        </div>
        <div
          style={{
            marginTop: "8px",
            fontSize: "11px",
            fontWeight: 600,
            color: "var(--text3)",
            background: "var(--surface2)",
            border: "1px solid var(--border)",
            borderRadius: "999px",
            padding: "5px 14px",
          }}
        >
          即将上线
        </div>
      </div>
    </div>
  );
}
