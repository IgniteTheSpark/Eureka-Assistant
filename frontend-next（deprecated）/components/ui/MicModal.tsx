"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { api } from "@/lib/api";

interface MicModalProps {
  open: boolean;
  onClose: () => void;
  onSaved?: () => void;
}

type MicStatus = "idle" | "listening" | "paused" | "saving" | "ok" | "err" | "unsupported";
type MicMode = "flash" | "meeting";

// Type augmentation for Web Speech API (not included in default TS lib by default)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type SpeechRecognitionCtor = new () => any;
declare global {
  interface Window {
    SpeechRecognition: SpeechRecognitionCtor;
    webkitSpeechRecognition: SpeechRecognitionCtor;
  }
}

export default function MicModal({ open, onClose, onSaved }: MicModalProps) {
  const [status, setStatus] = useState<MicStatus>("idle");
  const [transcript, setTranscript] = useState("");
  const [interimText, setInterimText] = useState("");
  const [errMsg, setErrMsg] = useState("");
  const [mode, setMode] = useState<MicMode>("flash");
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const recognitionRef = useRef<any>(null);
  const finalRef = useRef("");

  const isSupported = typeof window !== "undefined" &&
    ("SpeechRecognition" in window || "webkitSpeechRecognition" in window);

  const stopRecognition = useCallback(() => {
    recognitionRef.current?.stop();
    recognitionRef.current = null;
    setInterimText("");
  }, []);

  // Clean up on close
  useEffect(() => {
    if (!open) {
      stopRecognition();
      setTranscript("");
      setInterimText("");
      setStatus("idle");
      setErrMsg("");
      setMode("flash");
      finalRef.current = "";
    } else if (!isSupported) {
      setStatus("unsupported");
    }
  }, [open, isSupported, stopRecognition]);

  function startListening() {
    const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
    const recognition = new SR();
    recognition.lang = "zh-CN";
    recognition.interimResults = true;
    recognition.continuous = true;
    recognition.maxAlternatives = 1;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    recognition.onresult = (e: any) => {
      let interim = "";
      let final = finalRef.current;
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const t = e.results[i][0].transcript;
        if (e.results[i].isFinal) {
          final += t;
        } else {
          interim += t;
        }
      }
      finalRef.current = final;
      setTranscript(final);
      setInterimText(interim);
    };

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    recognition.onerror = (e: any) => {
      if (e.error === "no-speech") return; // ignore timeout
      setStatus("err");
      setErrMsg(`识别错误: ${e.error}`);
      stopRecognition();
    };

    recognition.onend = () => {
      // Auto-paused (e.g. silence timeout) — show paused state
      if (status === "listening") {
        setStatus("paused");
        setInterimText("");
      }
    };

    recognitionRef.current = recognition;
    recognition.start();
    setStatus("listening");
  }

  function handleToggleListen() {
    if (status === "listening") {
      stopRecognition();
      setStatus("paused");
    } else {
      startListening();
    }
  }

  async function handleSave() {
    const raw = (transcript + interimText).trim();
    if (!raw || status === "saving") return;
    stopRecognition();
    setStatus("saving");
    const text = mode === "meeting" ? `【会议记录】${raw}` : raw;

    // 55s timeout — backend creates the flash card immediately before running the
    // pipeline, so even if the LLM takes longer the note is already saved.
    const timeoutPromise = new Promise<{ ok: true; session_id: string; timedOut: true }>(resolve =>
      setTimeout(() => resolve({ ok: true, session_id: "", timedOut: true }), 55_000)
    );

    const res = await Promise.race([api.flash(text, undefined, false, true), timeoutPromise]);
    if (res.ok) {
      setStatus("ok");
      setTimeout(() => {
        onClose();
        onSaved?.();
      }, 800);
    } else {
      setStatus("err");
      setErrMsg((res as { error?: string }).error ?? "保存失败");
    }
  }

  if (!open) return null;

  const displayText = transcript + interimText;
  const canSave = displayText.trim().length > 0 && status !== "saving" && status !== "ok";

  // Pulse animation for recording indicator
  const pulseStyle = status === "listening" ? {
    animation: "micPulse 1.2s ease-in-out infinite",
  } : {};

  return (
    <>
      <style>{`
        @keyframes micPulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.5; transform: scale(0.92); }
        }
        @keyframes waveBar {
          0%, 100% { height: 8px; }
          50% { height: 28px; }
        }
      `}</style>

      {/* Backdrop */}
      <div
        onClick={onClose}
        style={{
          position: "absolute", inset: 0,
          background: "rgba(10,14,30,.5)",
          zIndex: 40, backdropFilter: "blur(3px)",
        }}
      />

      {/* Sheet */}
      <div
        style={{
          position: "absolute", bottom: 0, left: 0, right: 0, zIndex: 50,
          background: "var(--surface)",
          borderRadius: "20px 20px 0 0",
          padding: "12px 16px 28px",
          boxShadow: "0 -4px 24px rgba(15,23,42,.18)",
          display: "flex", flexDirection: "column", gap: "14px",
        }}
      >
        {/* Drag handle */}
        <div style={{ display: "flex", justifyContent: "center", paddingBottom: "2px" }}>
          <div style={{ width: "36px", height: "4px", borderRadius: "999px", background: "var(--border-m)" }} />
        </div>

        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <span style={{ fontSize: "18px" }}>🎙</span>
          <span style={{ fontSize: "15px", fontWeight: 700, color: "var(--text)", letterSpacing: "-0.02em" }}>
            语音闪念
          </span>
          {status === "listening" && (
            <span style={{ fontSize: "11px", color: "var(--red)", fontWeight: 600, marginLeft: "4px" }}>
              ● 录音中
            </span>
          )}
          {status === "paused" && (
            <span style={{ fontSize: "11px", color: "var(--text3)", fontWeight: 600, marginLeft: "4px" }}>
              ‖ 已暂停
            </span>
          )}
        </div>

        {/* Mode selector */}
        {status !== "unsupported" && (
          <div style={{ display: "flex", gap: "6px" }}>
            {(["flash", "meeting"] as MicMode[]).map(m => {
              const label = m === "flash" ? "⚡ 闪念" : "📋 会议记录";
              const active = mode === m;
              return (
                <button
                  key={m}
                  onClick={() => setMode(m)}
                  style={{
                    flex: 1, padding: "7px 0", borderRadius: "999px",
                    fontSize: "12px", fontWeight: 700, cursor: "pointer",
                    transition: "all .12s",
                    background: active
                      ? (m === "flash" ? "var(--blue10)" : "color-mix(in srgb, var(--purple) 10%, transparent)")
                      : "var(--surface2)",
                    border: `1.5px solid ${active
                      ? (m === "flash" ? "var(--blue)" : "var(--purple)")
                      : "var(--border)"}`,
                    color: active
                      ? (m === "flash" ? "var(--blue)" : "var(--purple)")
                      : "var(--text3)",
                  }}
                >{label}</button>
              );
            })}
          </div>
        )}

        {/* Unsupported */}
        {status === "unsupported" && (
          <div style={{ textAlign: "center", padding: "16px 0", color: "var(--text2)", fontSize: "13px", lineHeight: 1.7 }}>
            <div style={{ fontSize: "32px", marginBottom: "8px" }}>⚠️</div>
            当前浏览器不支持语音识别<br />
            请使用 <strong>Chrome</strong> 或 <strong>Edge</strong> 浏览器
          </div>
        )}

        {/* Waveform + mic button */}
        {status !== "unsupported" && (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: "16px" }}>
            {/* Waveform bars */}
            <div style={{ display: "flex", alignItems: "center", gap: "4px", height: "40px" }}>
              {[0.4, 0.7, 1, 0.6, 0.9, 0.5, 0.8, 1, 0.6, 0.4].map((scale, i) => (
                <div
                  key={i}
                  style={{
                    width: "4px",
                    borderRadius: "999px",
                    background: status === "listening" ? "var(--blue)" : "var(--border-m)",
                    height: status === "listening" ? `${8 + scale * 24}px` : "8px",
                    transition: "height .3s ease, background .3s",
                    animation: status === "listening" ? `waveBar ${0.8 + i * 0.1}s ease-in-out ${i * 0.08}s infinite` : "none",
                  }}
                />
              ))}
            </div>

            {/* Big mic button */}
            <button
              onClick={handleToggleListen}
              style={{
                width: "72px", height: "72px", borderRadius: "50%",
                background: status === "listening"
                  ? "rgba(220,38,38,.12)"
                  : "var(--blue10)",
                border: `2px solid ${status === "listening" ? "var(--red)" : "var(--blue)"}`,
                display: "grid", placeItems: "center",
                fontSize: "30px", cursor: "pointer",
                transition: "all .2s",
                ...pulseStyle,
              }}
              title={status === "listening" ? "暂停" : "开始录音"}
            >
              {status === "listening" ? "⏸" : "🎙"}
            </button>

            <div style={{ fontSize: "11px", color: "var(--text3)", fontWeight: 600 }}>
              {status === "idle" && "点击开始录音"}
              {status === "listening" && "说话中… 点击暂停"}
              {status === "paused" && "点击继续录音"}
              {status === "saving" && "保存中…"}
              {status === "ok" && "✓ 已保存"}
              {status === "err" && "录音出错"}
            </div>
          </div>
        )}

        {/* Transcript display */}
        {displayText && (
          <div
            style={{
              background: "var(--surface2)",
              border: "1px solid var(--border)",
              borderRadius: "var(--r)",
              padding: "10px 12px",
              fontSize: "13px",
              color: "var(--text)",
              lineHeight: 1.65,
              minHeight: "48px",
              maxHeight: "120px",
              overflowY: "auto",
            }}
            className="no-scrollbar"
          >
            {transcript}
            {interimText && (
              <span style={{ color: "var(--text3)" }}>{interimText}</span>
            )}
          </div>
        )}

        {/* Error */}
        {status === "err" && (
          <div style={{ fontSize: "11px", color: "var(--red)" }}>❌ {errMsg}</div>
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
          >
            取消
          </button>
          <button
            onClick={handleSave}
            disabled={!canSave}
            style={{
              flex: 2, height: "40px", borderRadius: "999px",
              background: status === "ok" ? "var(--green)" : canSave ? "var(--grad)" : "var(--surface2)",
              border: "none",
              fontSize: "13px", fontWeight: 700,
              color: canSave || status === "ok" ? "#fff" : "var(--text3)",
              cursor: canSave ? "pointer" : "default",
              boxShadow: canSave ? "0 4px 14px rgba(59,91,245,.35)" : "none",
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
