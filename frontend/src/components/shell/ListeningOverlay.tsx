import { useListening } from "@/context/ListeningContext";

/**
 * ListeningOverlay — global "正在聆听" indicator shown while the hardware
 * mic (W1/W2 card flash-memo button) is held down and capturing.
 *
 * Driven by ListeningContext, which the SSE bridge flips on the `listening`
 * event. Full-screen, dimmed, non-interactive (pointer-events-none) so it
 * never blocks the UI — it's a status veil, not a modal.
 *
 * Visual: a breathing gradient orb with animated voice-equalizer bars — reads
 * as "an agent is listening to you", not a static mic icon (eu-breathe +
 * eu-eq keyframes in globals.css).
 */

// 7 bars with hand-tuned base heights → an organic "voice" silhouette (taller
// in the middle). Staggered delays make them ripple like a live waveform.
const BARS = [14, 22, 30, 36, 30, 22, 14];

export function ListeningOverlay() {
  const { isListening } = useListening();
  if (!isListening) return null;

  return (
    <div
      className="fixed inset-0 z-[80] flex flex-col items-center justify-center pointer-events-none eu-fade-in"
      style={{ background: "rgba(6,7,13,0.68)", backdropFilter: "blur(5px)" }}
      aria-live="polite"
      role="status"
    >
      <div className="relative flex items-center justify-center" style={{ width: 168, height: 168 }}>
        {/* Breathing ambient glow */}
        <span
          className="absolute rounded-full"
          style={{
            width: 168, height: 168,
            background: "radial-gradient(circle, rgba(111,158,255,0.45) 0%, rgba(183,157,255,0.12) 55%, transparent 72%)",
            animation: "eu-breathe 2.6s ease-in-out infinite",
          }}
        />
        {/* Core orb */}
        <div
          className="relative flex items-center justify-center rounded-full"
          style={{
            width: 104, height: 104,
            background: "linear-gradient(140deg, #6f9eff 0%, #b79dff 100%)",
            boxShadow: "0 0 44px rgba(111,158,255,0.55), inset 0 0 20px rgba(255,255,255,0.18)",
          }}
        >
          {/* Voice equalizer */}
          <div className="flex items-center" style={{ gap: 5, height: 44 }}>
            {BARS.map((h, i) => (
              <span
                key={i}
                style={{
                  width: 5,
                  height: h,
                  borderRadius: 999,
                  background: "rgba(255,255,255,0.95)",
                  transformOrigin: "center",
                  animation: "eu-eq 0.95s ease-in-out infinite",
                  animationDelay: `${i * 0.11}s`,
                }}
              />
            ))}
          </div>
        </div>
      </div>

      <div
        className="font-display mt-8"
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
