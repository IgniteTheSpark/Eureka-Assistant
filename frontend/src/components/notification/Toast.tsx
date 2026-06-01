import { useEffect } from "react";
import { X } from "lucide-react";
import { useNavigate } from "react-router-dom";

import type { Notification } from "@/lib/types";
import { notifLinkTarget, notifMeta, notifNavigate } from "./meta";

/**
 * Toast — a single transient notification card. Auto-dismisses (tap to follow
 * its deep-link, or × to dismiss). Rendered by ToastProvider's viewport
 * (top-center, inside the phone frame).
 *
 * Async-task results (task_done / task_failed) linger longer: they land 10-20s
 * after the user fired the request, by which point the user has usually moved
 * on, so a 4.5s flash is easy to miss. 7.5s gives the "your 钉钉 task finished"
 * moment a real chance to register.
 */
const DISMISS_MS: Record<string, number> = {
  task_done:   7500,
  task_failed: 7500,
};
const DEFAULT_DISMISS_MS = 4500;

export function Toast({ notif, onDone }: { notif: Notification; onDone: () => void }) {
  const navigate = useNavigate();
  const m = notifMeta(notif.type);

  useEffect(() => {
    const t = setTimeout(onDone, DISMISS_MS[notif.type] ?? DEFAULT_DISMISS_MS);
    return () => clearTimeout(t);
  }, [onDone, notif.type]);

  const target = notifLinkTarget(notif);

  return (
    <div
      role="status"
      onClick={() => {
        notifNavigate(notif, navigate);
        onDone();
      }}
      className="pointer-events-auto eu-sheet-down"
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 10,
        padding: "11px 12px",
        borderRadius: 14,
        background: "rgba(20,22,30,0.86)",
        backdropFilter: "blur(12px) saturate(1.4)",
        border: "1px solid rgba(255,255,255,0.10)",
        boxShadow: "0 8px 28px rgba(0,0,0,0.40)",
        cursor: target ? "pointer" : "default",
      }}
    >
      <span
        style={{
          flex: "0 0 28px",
          width: 28, height: 28, borderRadius: 8,
          display: "flex", alignItems: "center", justifyContent: "center",
          background: m.bg, border: `1px solid ${m.edge}`, color: m.fg,
          fontSize: 14, fontWeight: 700,
        }}
      >
        {m.icon}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: "#f4f7fb", lineHeight: 1.3 }}>
          {notif.title}
        </div>
        {notif.body && (
          <div
            style={{
              fontSize: 12, color: "rgba(255,255,255,0.62)", marginTop: 2, lineHeight: 1.35,
              display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden",
            }}
          >
            {notif.body}
          </div>
        )}
      </div>
      <button
        type="button"
        aria-label="关闭"
        onClick={(e) => { e.stopPropagation(); onDone(); }}
        style={{
          flex: "0 0 auto", padding: 2, borderRadius: 6,
          color: "rgba(255,255,255,0.45)", background: "transparent", border: "none", cursor: "pointer",
        }}
      >
        <X size={15} strokeWidth={2} />
      </button>
    </div>
  );
}
