import { useEffect, useRef } from "react";
import useSWR from "swr";

import { API_BASE, apiFetch, swrFetcher } from "@/lib/api";
import { openSse } from "@/lib/sse";
import type { Notification, NotificationsResponse } from "@/lib/types";

/**
 * useNotifications — M6. SWR-backed list + unread count + read/dismiss actions.
 *
 * Realtime push is handled separately by `useNotificationStream` (mounted once
 * in App via NotificationsBridge) so we only ever open one EventSource. The
 * bell + page just consume this SWR cache; the bridge revalidates it whenever
 * a new notification arrives over SSE.
 */

const KEY = "/api/notifications";

export function useNotifications() {
  const { data, mutate, isLoading } = useSWR<NotificationsResponse>(KEY, swrFetcher, {
    revalidateOnFocus: true,
  });

  const notifications = data?.notifications ?? [];
  const unread = data?.unread ?? 0;

  async function markRead(id: string) {
    mutate(
      (cur) =>
        cur && {
          ...cur,
          notifications: cur.notifications.map((n) => (n.id === id ? { ...n, read: true } : n)),
          unread: Math.max(0, cur.unread - (cur.notifications.some((n) => n.id === id && !n.read) ? 1 : 0)),
        },
      { revalidate: false },
    );
    try { await apiFetch(`/api/notifications/${id}/read`, { method: "POST" }); } finally { mutate(); }
  }

  async function markAllRead() {
    mutate(
      (cur) => cur && { ...cur, notifications: cur.notifications.map((n) => ({ ...n, read: true })), unread: 0 },
      { revalidate: false },
    );
    try { await apiFetch(`/api/notifications/read-all`, { method: "POST" }); } finally { mutate(); }
  }

  async function dismiss(id: string) {
    mutate(
      (cur) =>
        cur && {
          ...cur,
          notifications: cur.notifications.filter((n) => n.id !== id),
          unread: Math.max(0, cur.unread - (cur.notifications.some((n) => n.id === id && !n.read) ? 1 : 0)),
        },
      { revalidate: false },
    );
    try { await apiFetch(`/api/notifications/${id}`, { method: "DELETE" }); } finally { mutate(); }
  }

  return { notifications, unread, isLoading, markRead, markAllRead, dismiss, refresh: mutate };
}

/**
 * useNotificationStream — open ONE SSE connection to /api/notifications/stream
 * and dispatch the pushed app events. Mount exactly once (App's
 * NotificationsBridge). Auto-reconnects (openSse handles backoff).
 *
 * The single stream multiplexes event types:
 *   - `notification` → onNew (persisted notification rows)
 *   - `listening`    → onListening (ephemeral hardware-mic state, "on"/"off")
 */
export function useNotificationStream(
  onNew: (n: Notification) => void,
  onListening?: (state: "on" | "off") => void,
  onCapture?: () => void,
) {
  const cb = useRef(onNew);
  cb.current = onNew;
  const cbListening = useRef(onListening);
  cbListening.current = onListening;
  const cbCapture = useRef(onCapture);
  cbCapture.current = onCapture;

  useEffect(() => {
    const sub = openSse(
      `${API_BASE}/api/notifications/stream`,
      {},
      {
        events: {
          notification: (data) => {
            try {
              cb.current(JSON.parse(data) as Notification);
            } catch {
              /* malformed frame — ignore */
            }
          },
          listening: (data) => {
            try {
              const p = JSON.parse(data) as { state?: string };
              cbListening.current?.(p.state === "on" ? "on" : "off");
            } catch {
              /* malformed frame — ignore */
            }
          },
          // Silent realtime nudge (no toast): a flash capture wrote its input
          // message; revalidate so the open session shows the input bubble
          // immediately, ahead of the analysis. See flash.py publish_event.
          capture: () => {
            cbCapture.current?.();
          },
        },
      },
    );
    return () => sub.close();
  }, []);
}
