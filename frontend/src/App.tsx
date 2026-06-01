import { Navigate, Route, Routes } from "react-router-dom";
import { useSWRConfig } from "swr";

import { AppShell } from "@/components/shell/AppShell";
import { PhoneFrame } from "@/components/shell/PhoneFrame";
import { ListeningOverlay } from "@/components/shell/ListeningOverlay";
import { ChatPage } from "@/pages/ChatPage";
import { CalendarPage } from "@/pages/CalendarPage";
import { LibraryPage } from "@/pages/LibraryPage";
import { NotificationPage } from "@/pages/NotificationPage";
import { ModalProvider } from "@/context/ModalContext";
import { ListeningProvider, useListening } from "@/context/ListeningContext";
import { PresentationModeProvider } from "@/context/PresentationModeContext";
import { ToastProvider, useToast } from "@/context/ToastContext";
import { useNotifications, useNotificationStream } from "@/hooks/useNotifications";

/** SWR keys that show assets/events — revalidated whenever something is
 *  captured so flash voice input reflects instantly (no manual refresh). */
function revalidatesOnCapture(key: unknown): boolean {
  return typeof key === "string" && (
    key.startsWith("/api/assets") ||
    key.startsWith("/api/timeline") ||
    key.startsWith("/api/events") ||
    key.startsWith("/api/sessions")
  );
}

/**
 * NotificationsBridge — mounted once. Opens the single SSE connection and:
 *   - on each notification: toast + revalidate the notification cache AND the
 *     asset/timeline/event/session caches (so a flash-captured asset appears
 *     live — Feature: auto-refresh after 闪念录入, no manual reload).
 *   - on `listening` events: flip the global ListeningOverlay.
 * Renders nothing.
 */
function NotificationsBridge() {
  const { push } = useToast();
  const { refresh } = useNotifications();
  const { mutate } = useSWRConfig();
  const { setListening } = useListening();
  useNotificationStream(
    (n) => {
      push(n);
      refresh();
      // Flash/agent captures create assets/events — pull the surfaces fresh.
      mutate(revalidatesOnCapture);
    },
    (state) => setListening(state === "on"),
    // `capture`: a flash just wrote its input message — silently revalidate so
    // the open session shows the input bubble before the analysis lands.
    () => mutate(revalidatesOnCapture),
  );
  return null;
}

export default function App() {
  return (
    <PresentationModeProvider>
      <ModalProvider>
        <ListeningProvider>
        {/* VF: entire app constrained to an iPhone 17 viewport (393×852).
            On desktop the frame is centered with a dark backdrop + bezel;
            on actual phones it fills the screen. */}
        <PhoneFrame>
          {/* ToastProvider lives inside PhoneFrame so its fixed toast viewport
              is constrained to the simulated device, not the browser window. */}
          <ToastProvider>
            <NotificationsBridge />
            <ListeningOverlay />
            <Routes>
              <Route element={<AppShell />}>
                <Route index element={<Navigate to="/chat" replace />} />
                <Route path="/chat" element={<ChatPage />} />
                <Route path="/calendar" element={<CalendarPage />} />
                <Route path="/library/*" element={<LibraryPage />} />
                <Route path="/notifications" element={<NotificationPage />} />
                {/* Catch-all → chat for now; will become 404 page later */}
                <Route path="*" element={<Navigate to="/chat" replace />} />
              </Route>
            </Routes>
          </ToastProvider>
        </PhoneFrame>
        </ListeningProvider>
      </ModalProvider>
    </PresentationModeProvider>
  );
}
