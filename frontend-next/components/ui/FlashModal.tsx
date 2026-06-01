"use client";

import { useState, useRef, useEffect, type KeyboardEvent } from "react";
import { api } from "@/lib/api";

interface FlashModalProps {
  open: boolean;
  onClose: () => void;
  onSaved?: () => void;
}

type Status = "idle" | "saving" | "ok" | "err";

export default function FlashModal({ open, onClose, onSaved }: FlashModalProps) {
  const [text, setText] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  const [errMsg, setErrMsg] = useState("");
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (open) {
      setText("");
      setStatus("idle");
      setErrMsg("");
      setTimeout(() => inputRef.current?.focus(), 80);
    }
  }, [open]);

  async function handleSave() {
    if (status === "saving" || status === "ok") return;
    const trimmed = text.trim();
    if (!trimmed) return;
    setStatus("saving");
    setErrMsg("");

    // Race: API call vs 55s timeout.
    // The backend creates the raw flash card immediately before running the agent,
    // so even if the LLM takes a long time the note is already saved. We close
    // the modal after the timeout so the user isn't stuck waiting.
    const timeoutPromise = new Promise<{ ok: true; session_id: string; timedOut: true }>(resolve =>
      setTimeout(() => resolve({ ok: true, session_id: "", timedOut: true }), 55_000)
    );

    const res = await Promise.race([api.flash(trimmed), timeoutPromise]);
    if (res.ok) {
      setStatus("ok");
      setTimeout(() => {
        onClose();
        onSaved?.();
        setStatus("idle");
      }, 900);
    } else {
      setStatus("err");
      setErrMsg((res as { error?: string }).error ?? "保存失败");
    }
  }

  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); handleSave(); }
    if (e.key === "Escape") onClose();
  }

  const canSave = !!text.trim();

  if (!open) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        onClick={onClose}
        style={{
          position: "absolute", inset: 0,
          background: "rgba(10,14,30,.45)",
          zIndex: 40, backdropFilter: "blur(2px)",
        }}
      />

      {/* Sheet */}
      <div style={{
        position: "absolute", bottom: 0, left: 0, right: 0, zIndex: 50,
        background: "var(--surface)", borderRadius: "20px 20px 0 0",
        padding: "12px 14px 28px",
        boxShadow: "0 -4px 24px rgba(15,23,42,.18)",
        display: "flex", flexDirection: "column", gap: "10px",
      }}>
        {/* Drag handle */}
        <div style={{ display: "flex", justifyContent: "center", paddingBottom: "2px" }}>
          <div style={{ width: "36px", height: "4px", borderRadius: "999px", background: "var(--border-m)" }} />
        </div>

        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <span style={{ fontSize: "18px" }}>⚡</span>
          <span style={{ fontSize: "15px", fontWeight: 700, color: "var(--text)", letterSpacing: "-0.02em" }}>
            闪念记录
          </span>
          <span style={{ fontSize: "10px", color: "var(--text3)", marginLeft: "auto" }}>⌘↵ 保存</span>
        </div>

        {/* Text input */}
        <textarea
          ref={inputRef}
          value={text}
          onChange={(e) => { setText(e.target.value); if (status === "err") setStatus("idle"); }}
          onKeyDown={handleKeyDown}
          placeholder="记录任何想法、待办、支出、联系人… Agent 会自动分类"
          rows={4}
          disabled={status === "saving" || status === "ok"}
          style={{
            width: "100%", fontSize: "13px", color: "var(--text)",
            background: "var(--surface2)",
            border: `1px solid ${status === "err" ? "rgba(220,38,38,.4)" : "var(--border)"}`,
            borderRadius: "var(--r)", padding: "10px 12px",
            outline: "none", resize: "none", lineHeight: 1.65,
            caretColor: "var(--blue)", fontFamily: "inherit",
            boxSizing: "border-box",
            opacity: status === "saving" || status === "ok" ? 0.7 : 1,
          }}
        />

        {status === "err" && (
          <div style={{ fontSize: "11px", color: "var(--red)", padding: "0 2px" }}>❌ {errMsg}</div>
        )}

        {/* Actions */}
        <div style={{ display: "flex", gap: "8px" }}>
          <button
            onClick={onClose}
            style={{
              flex: 1, height: "40px", borderRadius: "999px",
              background: "var(--surface2)", border: "1px solid var(--border)",
              fontSize: "13px", fontWeight: 600, color: "var(--text2)", cursor: "pointer",
            }}
          >取消</button>
          <button
            onClick={handleSave}
            disabled={!canSave || status === "saving" || status === "ok"}
            style={{
              flex: 2, height: "40px", borderRadius: "999px",
              background: status === "ok" ? "var(--green)" : !canSave || status === "saving" ? "var(--surface2)" : "var(--grad)",
              border: "none", fontSize: "13px", fontWeight: 700,
              color: !canSave && status !== "ok" ? "var(--text3)" : "#fff",
              cursor: !canSave || status === "saving" || status === "ok" ? "default" : "pointer",
              boxShadow: canSave && status === "idle" ? "0 4px 14px rgba(59,91,245,.35)" : "none",
              transition: "all .15s",
            }}
          >
            {status === "saving" ? "保存中…" : status === "ok" ? "✓ 已保存" : "保存闪念"}
          </button>
        </div>
      </div>
    </>
  );
}
