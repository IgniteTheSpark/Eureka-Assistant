import { useEffect, useState } from "react";

/**
 * StatusBar — iOS-style status row, per the Mobile-Redesign spec (primitives.jsx
 * StatusBar). Replaces the old app TopBar: the redesign has no global "Eureka"
 * chrome — each screen owns its own header, and the top of the phone frame is
 * just the OS status row (time + signal/wifi/battery). We show the real clock
 * instead of the mock 9:41 so it reads as a live device.
 */
export function StatusBar() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(t);
  }, []);
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const tint = "var(--eu-text-hi)";

  return (
    <div
      className="shrink-0 font-mono"
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        padding: "calc(env(safe-area-inset-top) + 10px) 26px 4px",
        fontSize: 14,
        fontWeight: 700,
        color: tint,
      }}
    >
      <span>{hh}:{mm}</span>
      <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
        {/* signal */}
        <svg width="18" height="11" viewBox="0 0 18 11" fill="none">
          {[3, 5, 7, 9].map((h, i) => (
            <rect key={i} x={1 + i * 4} y={11 - h} width="3" height={h} rx="1" fill={tint} />
          ))}
        </svg>
        {/* wifi */}
        <svg width="16" height="11" viewBox="0 0 16 11" fill="none">
          <path d="M8 10.5a1.2 1.2 0 100-2.4 1.2 1.2 0 000 2.4z" fill={tint} />
          <path d="M3.2 5.2a7 7 0 019.6 0" stroke={tint} strokeWidth="1.6" strokeLinecap="round" />
          <path d="M.8 2.6a10.5 10.5 0 0114.4 0" stroke={tint} strokeWidth="1.6" strokeLinecap="round" />
        </svg>
        {/* battery */}
        <div style={{ width: 25, height: 12, border: `1.2px solid ${tint}`, borderRadius: 3, position: "relative", padding: 1, opacity: 0.9 }}>
          <div style={{ width: "82%", height: "100%", background: tint, borderRadius: 1.5 }} />
          <div style={{ position: "absolute", right: -3, top: 3, width: 1.5, height: 5, background: tint, borderRadius: 1 }} />
        </div>
      </div>
    </div>
  );
}
