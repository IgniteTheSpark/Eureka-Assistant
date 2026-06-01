"use client";

import { useState } from "react";
import { useNav } from "@/context/NavContext";
import FlashModal from "@/components/ui/FlashModal";
import MicModal from "@/components/ui/MicModal";
import type { StreamView } from "@/lib/types";

interface FABBarProps {
  onFlashSaved?: () => void;
  streamView: StreamView;
  onViewChange: (v: StreamView) => void;
}

export default function FABBar({ onFlashSaved, streamView, onViewChange }: FABBarProps) {
  const { navTo } = useNav();
  const [flashOpen, setFlashOpen] = useState(false);
  const [micOpen, setMicOpen] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(null), 2500);
  }

  const btnBase: React.CSSProperties = {
    width: "40px", height: "40px", borderRadius: "50%",
    display: "grid", placeItems: "center",
    fontSize: "18px", cursor: "pointer", transition: "all .15s",
    border: "1px solid var(--border)",
    background: "var(--surface2)", color: "var(--text2)", flexShrink: 0,
  };

  const viewBtnStyle = (active: boolean): React.CSSProperties => ({
    width: "34px", height: "34px", borderRadius: "8px",
    display: "grid", placeItems: "center",
    fontSize: "15px", cursor: "pointer", transition: "all .15s",
    border: active ? "1.5px solid var(--blue)" : "1px solid var(--border)",
    background: active ? "var(--blue10)" : "var(--surface2)",
    color: active ? "var(--blue)" : "var(--text3)", flexShrink: 0,
  });

  return (
    <>
      <FlashModal
        open={flashOpen}
        onClose={() => setFlashOpen(false)}
        onSaved={() => { showToast("✅ 闪念已保存"); onFlashSaved?.(); }}
      />
      <MicModal
        open={micOpen}
        onClose={() => setMicOpen(false)}
        onSaved={() => { showToast("✅ 语音闪念已保存"); onFlashSaved?.(); }}
      />

      {toast && (
        <div style={{
          position: "absolute", bottom: "80px", left: "50%",
          transform: "translateX(-50%)",
          background: "rgba(15,23,42,.88)", color: "#fff",
          fontSize: "12px", fontWeight: 600,
          padding: "7px 16px", borderRadius: "999px",
          whiteSpace: "nowrap", zIndex: 50, pointerEvents: "none",
        }}>{toast}</div>
      )}

      <div style={{
        position: "absolute", bottom: "18px", left: "50%",
        transform: "translateX(-50%)", zIndex: 30,
        display: "flex", alignItems: "center", gap: "5px",
        background: "var(--surface)", borderRadius: "999px",
        padding: "6px 10px",
        boxShadow: "0 8px 32px rgba(15,23,42,.18),0 2px 8px rgba(15,23,42,.08),0 0 0 1px var(--border)",
        whiteSpace: "nowrap",
      }}>
        {/* View toggle: timeline ↔ workspace */}
        <button
          style={viewBtnStyle(streamView === "timeline")}
          title="时间流"
          onClick={() => onViewChange("timeline")}
        >📅</button>

        <button
          style={viewBtnStyle(streamView === "workspace")}
          title="Workspace"
          onClick={() => onViewChange("workspace")}
        >🗂</button>

        {/* Separator */}
        <div style={{ width: "1px", height: "22px", background: "var(--border)", flexShrink: 0, margin: "0 2px" }} />

        {/* Flash note */}
        <button
          style={{
            ...btnBase,
            fontSize: "20px",
            background: "rgba(245,158,11,.08)",
            borderColor: "rgba(217,119,6,.25)",
            color: "var(--amber)",
          }}
          title="文字闪念"
          onClick={() => setFlashOpen(true)}
        >＋</button>

        {/* Mic */}
        <button style={btnBase} title="语音录入" onClick={() => setMicOpen(true)}>🎙</button>

        {/* Separator */}
        <div style={{ width: "1px", height: "22px", background: "var(--border)", flexShrink: 0, margin: "0 2px" }} />

        {/* Agent pill */}
        <button
          onClick={() => navTo("p-agent-chat")}
          style={{
            height: "40px", borderRadius: "999px",
            display: "flex", alignItems: "center", gap: "6px",
            padding: "0 16px", fontSize: "13px", fontWeight: 700,
            cursor: "pointer", transition: "all .15s",
            background: "var(--grad)", color: "#fff", border: "none",
            flexShrink: 0, boxShadow: "0 4px 16px rgba(59,91,245,.38)",
          }}
        >
          <span>✦</span><span>Agent</span>
        </button>
      </div>
    </>
  );
}
