import { createContext, useCallback, useContext, useState } from "react";

import { Toast } from "@/components/notification/Toast";
import type { Notification } from "@/lib/types";

/**
 * ToastContext — M6 transient notification queue.
 *
 * Up to 3 toasts stacked top-center (newest on top), each auto-dismissing.
 * `push` is called by NotificationsBridge whenever a notification arrives over
 * SSE. The viewport renders inside the PhoneFrame (which is a containing block
 * for fixed positioning), so toasts stay within the simulated device.
 */

interface ToastCtx {
  push: (n: Notification) => void;
}

const Ctx = createContext<ToastCtx | null>(null);

export function useToast(): ToastCtx {
  const c = useContext(Ctx);
  if (!c) throw new Error("useToast must be used within <ToastProvider>");
  return c;
}

interface ToastItem {
  key: string;
  notif: Notification;
}

const MAX_VISIBLE = 3;

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const push = useCallback((notif: Notification) => {
    setToasts((cur) => {
      const item: ToastItem = { key: `${notif.id}-${Date.now()}`, notif };
      return [...cur, item].slice(-MAX_VISIBLE); // FIFO, keep newest 3
    });
  }, []);

  const remove = useCallback((key: string) => {
    setToasts((cur) => cur.filter((t) => t.key !== key));
  }, []);

  return (
    <Ctx.Provider value={{ push }}>
      {children}
      <div
        className="fixed left-1/2 -translate-x-1/2 z-[80] flex flex-col gap-2 pointer-events-none"
        style={{
          top: "calc(env(safe-area-inset-top) + 52px)",
          width: "calc(100% - 28px)",
          maxWidth: 380,
        }}
      >
        {toasts.map((t) => (
          <Toast key={t.key} notif={t.notif} onDone={() => remove(t.key)} />
        ))}
      </div>
    </Ctx.Provider>
  );
}
