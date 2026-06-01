import { Outlet, useLocation } from "react-router-dom";

import { StatusBar } from "./StatusBar";
import { FloatingDock } from "./FloatingDock";

/**
 * AppShell — top-level layout wrapper.
 *
 * Two-row layout (mobile-first; desktop same shape, wider content):
 *   ┌──────────────────────────┐
 *   │ TopBar (sticky)           │ — logo + page title + 3 icons
 *   ├──────────────────────────┤
 *   │ <Outlet />                │ — current page, scrolls, has bottom
 *   │   (pages own their scroll)│   padding so dock doesn't overlap content
 *   └──────────────────────────┘
 *           [ FloatingDock ]    — floats over content, doesn't take layout space
 *
 * Route-aware dock (M3.5): on /chat the FloatingDock is hidden because the
 * page has its own input + back nav; we also drop the bottom padding so
 * ChatInput can truly stick to the screen bottom.
 *
 * Per spec amendment (2026-05-26): the original bottom TabBar + middle FAB is
 * replaced by a single FloatingDock capsule that holds: 今天 / 资产库 / + /
 * 闪念 / Agent. SessionSidebar (M2) slots into ChatPage itself, not the shell.
 */
export function AppShell() {
  const location = useLocation();
  // /chat owns its own bottom bar (ChatInput sticky + back nav). Hide dock
  // there and let main fill all the way to the safe-area bottom so the
  // input can sit flush.
  const onChat = location.pathname.startsWith("/chat");

  return (
    // VF: was h-dvh; now h-full so we inherit the PhoneFrame's fixed 852px
    // height (and on real mobile, 100dvh via PhoneFrame's clamp). Layout
    // contract for children unchanged.
    <div className="h-full flex flex-col bg-eu-bg text-eu-text overflow-hidden">
      <StatusBar />
      {/* pb-28 reserves room for the floating dock + safe area;
          0 on /chat where the dock is hidden and ChatInput owns the bottom. */}
      <main className={`flex-1 overflow-y-auto eu-noscroll min-h-0 ${onChat ? "pb-0" : "pb-28"}`}>
        <Outlet />
      </main>
      {!onChat && <FloatingDock />}
    </div>
  );
}
