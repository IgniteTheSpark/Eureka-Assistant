import { Mic } from "lucide-react";

import { useListening } from "@/context/ListeningContext";

/**
 * ListeningOverlay — global "正在聆听" indicator shown while the hardware
 * mic (W1/W2 card flash-memo button) is held down and capturing.
 *
 * Driven by ListeningContext, which the SSE bridge flips on the `listening`
 * event. Full-screen, dimmed, non-interactive (pointer-events-none) so it
 * never blocks the UI — it's a status veil, not a modal. Pulsing mic via
 * stacked `animate-ping` rings.
 */
export function ListeningOverlay() {
  const { isListening } = useListening();
  if (!isListening) return null;

  return (
    <div
      className="fixed inset-0 z-[80] flex flex-col items-center justify-center pointer-events-none eu-fade-in"
      style={{ background: "rgba(6,7,13,0.62)", backdropFilter: "blur(3px)" }}
      aria-live="polite"
      role="status"
    >
      {/* Pulsing mic */}
      <div className="relative flex items-center justify-center" style={{ width: 120, height: 120 }}>
        <span
          className="absolute rounded-full animate-ping"
          style={{ width: 96, height: 96, background: "rgba(111,158,255,0.25)", animationDuration: "1.4s" }}
        />
        <span
          className="absolute rounded-full animate-ping"
          style={{ width: 72, height: 72, background: "rgba(111,158,255,0.30)", animationDuration: "1.4s", animationDelay: "0.3s" }}
        />
        <div
          className="relative flex items-center justify-center rounded-full"
          style={{
            width: 64, height: 64,
            background: "linear-gradient(135deg, #6f9eff 0%, #b79dff 100%)",
            boxShadow: "0 0 28px rgba(111,158,255,0.55)",
            color: "#fff",
          }}
        >
          <Mic size={26} strokeWidth={2} />
        </div>
      </div>

      <div
        className="font-display mt-7"
        style={{ fontSize: 19, fontWeight: 600, letterSpacing: "0.02em", color: "#f4f7fb" }}
      >
        正在聆听…
      </div>
      <div className="mt-1.5" style={{ fontSize: 13, color: "rgba(255,255,255,0.55)" }}>
        松开按钮结束录音
      </div>
    </div>
  );
}
