import { X } from "lucide-react";

import type { Notification } from "@/lib/types";
import { notifMeta, relativeTime } from "./meta";

/**
 * NotificationItem — one row, shared by the bell popover and the history page.
 * Unread rows carry a brand dot + faint tint; tapping marks read (+ follows
 * the deep-link via onOpen); the × dismisses.
 */
export function NotificationItem({
  notif,
  onOpen,
  onDismiss,
}: {
  notif: Notification;
  onOpen: (n: Notification) => void;
  onDismiss: (id: string) => void;
}) {
  const m = notifMeta(notif.type);
  return (
    <div
      onClick={() => onOpen(notif)}
      className="group flex items-start gap-2.5 px-3 py-2.5 cursor-pointer transition-colors"
      style={{ background: notif.read ? "transparent" : "rgba(111,158,255,0.05)" }}
    >
      <span
        className="shrink-0 flex items-center justify-center"
        style={{
          width: 28, height: 28, borderRadius: 8,
          background: m.bg, border: `1px solid ${m.edge}`, color: m.fg,
          fontSize: 14, fontWeight: 700,
        }}
      >
        {m.icon}
      </span>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          {!notif.read && (
            <span className="shrink-0" style={{ width: 6, height: 6, borderRadius: 999, background: "#6f9eff" }} />
          )}
          <span
            className="text-eu-sm font-medium truncate"
            style={{ color: notif.read ? "rgba(255,255,255,0.72)" : "#f4f7fb" }}
          >
            {notif.title}
          </span>
          <span className="ml-auto shrink-0 font-mono text-eu-xs" style={{ color: "rgba(255,255,255,0.35)" }}>
            {relativeTime(notif.created_at)}
          </span>
        </div>
        {notif.body && (
          <div
            className="text-eu-xs mt-0.5"
            style={{
              color: "rgba(255,255,255,0.50)",
              display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden",
            }}
          >
            {notif.body}
          </div>
        )}
      </div>
      <button
        type="button"
        aria-label="删除通知"
        onClick={(e) => { e.stopPropagation(); onDismiss(notif.id); }}
        className="shrink-0 p-1 rounded-eu-sm opacity-0 group-hover:opacity-100 transition-opacity"
        style={{ color: "rgba(255,255,255,0.40)" }}
      >
        <X size={14} strokeWidth={2} />
      </button>
    </div>
  );
}
