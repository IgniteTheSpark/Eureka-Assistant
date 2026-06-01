import { useNavigate } from "react-router-dom";

import { NotificationItem } from "@/components/notification/NotificationItem";
import { notifNavigate } from "@/components/notification/meta";
import { useNotifications } from "@/hooks/useNotifications";
import type { Notification } from "@/lib/types";

/**
 * NotificationPage — M6 full history. Lists all notifications (newest first)
 * with read/dismiss, plus a 全部已读 action. Tapping a row marks it read and
 * follows its deep-link.
 */
export function NotificationPage() {
  const navigate = useNavigate();
  const { notifications, unread, markRead, markAllRead, dismiss, isLoading } = useNotifications();

  function openNotif(n: Notification) {
    if (!n.read) markRead(n.id);
    notifNavigate(n, navigate);
  }

  return (
    <div
      className="flex flex-col h-full"
      style={{
        background:
          "radial-gradient(800px 500px at 20% -10%, rgba(111,158,255,0.10), transparent 60%), #06070d",
        color: "#d4dbe6",
        fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      }}
    >
      <header className="flex items-baseline justify-between shrink-0" style={{ padding: "8px 22px 14px" }}>
        <div>
          <h1 className="font-display" style={{ fontSize: 26, fontWeight: 700, color: "#f4f7fb", letterSpacing: "-0.02em" }}>
            通知
          </h1>
          <div className="font-mono" style={{ fontSize: 10.5, color: "rgba(255,255,255,0.45)", letterSpacing: "0.16em", marginTop: 4 }}>
            {unread} UNREAD · {notifications.length} TOTAL
          </div>
        </div>
        {unread > 0 && (
          <button
            type="button"
            onClick={() => markAllRead()}
            className="text-eu-sm text-eu-brand-hi hover:brightness-110"
          >
            全部已读
          </button>
        )}
      </header>

      <div
        className="flex-1 overflow-y-auto eu-noscroll"
        style={{ paddingBottom: "calc(env(safe-area-inset-bottom) + 104px)" }}
      >
        {isLoading && notifications.length === 0 ? (
          <div className="px-6 py-10 text-center text-eu-sm text-eu-text-lo font-mono">加载中…</div>
        ) : notifications.length === 0 ? (
          <div className="px-6 py-16 text-center">
            <div style={{ fontSize: 32, marginBottom: 8 }}>🔔</div>
            <div className="text-eu-sm text-eu-text-lo">还没有通知</div>
            <div className="text-eu-xs text-eu-text-muted font-mono mt-1">闪念整理 / 任务完成时会出现在这里</div>
          </div>
        ) : (
          <div className="mx-3 rounded-eu-md overflow-hidden border border-eu-border bg-eu-surface-raised/40 divide-y divide-eu-rule">
            {notifications.map((n) => (
              <NotificationItem key={n.id} notif={n} onOpen={openNotif} onDismiss={dismiss} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
