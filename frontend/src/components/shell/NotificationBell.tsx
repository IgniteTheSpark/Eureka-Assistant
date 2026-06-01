import { useState } from "react";
import { Bell } from "lucide-react";
import { useNavigate } from "react-router-dom";

import { NotificationItem } from "@/components/notification/NotificationItem";
import { notifNavigate } from "@/components/notification/meta";
import { useNotifications } from "@/hooks/useNotifications";
import type { Notification } from "@/lib/types";

/**
 * NotificationBell — TopBar icon → popover with the recent 5 + a link to the
 * full history page. M6: wired to useNotifications (SWR list + unread count;
 * realtime arrives via the App-level SSE bridge which revalidates this cache).
 */
export function NotificationBell() {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  const { notifications, unread, markRead, markAllRead, dismiss } = useNotifications();

  function openNotif(n: Notification) {
    if (!n.read) markRead(n.id);
    setOpen(false);
    notifNavigate(n, navigate);
  }

  return (
    <div className="relative">
      <button
        type="button"
        aria-label="通知"
        onClick={() => setOpen((v) => !v)}
        className="relative p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover transition-colors duration-eu-fast"
      >
        <Bell size={18} strokeWidth={1.75} />
        {unread > 0 && (
          <span
            className="absolute -top-0.5 -right-0.5 min-w-[15px] h-[15px] px-1 rounded-full bg-eu-accent-red-solid text-white font-mono flex items-center justify-center"
            style={{ fontSize: 9, lineHeight: 1 }}
          >
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div
            className="absolute right-0 top-full mt-2 z-50 w-80 max-w-[88vw] rounded-eu-md overflow-hidden bg-eu-surface-raised border border-eu-border shadow-eu-md"
          >
            <div className="flex items-center justify-between px-3 py-2 border-b border-eu-rule">
              <span className="text-eu-sm font-medium text-eu-text-hi">通知</span>
              {unread > 0 && (
                <button
                  type="button"
                  onClick={() => markAllRead()}
                  className="text-eu-xs text-eu-brand-hi hover:brightness-110"
                >
                  全部已读
                </button>
              )}
            </div>

            <div className="max-h-80 overflow-y-auto eu-noscroll divide-y divide-eu-rule">
              {notifications.length === 0 ? (
                <div className="px-3 py-6 text-center text-eu-sm text-eu-text-lo">暂无通知</div>
              ) : (
                notifications.slice(0, 5).map((n) => (
                  <NotificationItem key={n.id} notif={n} onOpen={openNotif} onDismiss={dismiss} />
                ))
              )}
            </div>

            <button
              type="button"
              onClick={() => { setOpen(false); navigate("/notifications"); }}
              className="block w-full text-left px-3 py-2 border-t border-eu-rule text-eu-sm text-eu-brand-hi hover:bg-eu-surface-hover"
            >
              查看全部 →
            </button>
          </div>
        </>
      )}
    </div>
  );
}
