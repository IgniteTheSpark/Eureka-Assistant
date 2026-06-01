"use client";

export default function StatusBar() {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        padding: "14px 26px 0",
        fontSize: "11px",
        fontWeight: 700,
        color: "var(--text2)",
        flexShrink: 0,
      }}
    >
      <span>9:41</span>
      <span style={{ display: "flex", alignItems: "center", gap: "5px" }}>
        <span>●●●</span>
        <span>WiFi</span>
        <span>▲</span>
      </span>
    </div>
  );
}
