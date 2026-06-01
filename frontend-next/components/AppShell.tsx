"use client";

import { useCallback, useRef, useState } from "react";
import { NavProvider, useNav } from "@/context/NavContext";
import StatusBar from "@/components/shell/StatusBar";
import FABBar from "@/components/shell/FABBar";
import StreamPage from "@/components/pages/StreamPage";
import AgentChatPage from "@/components/pages/AgentChatPage";
import FlashSessionPage from "@/components/pages/FlashSessionPage";
import FlashOverallPage from "@/components/pages/FlashOverallPage";
import DayViewPage from "@/components/pages/DayViewPage";
import WorkspacePage from "@/components/pages/WorkspacePage";
import AssetDetailPage from "@/components/pages/AssetDetailPage";
import type { PageId, StreamView } from "@/lib/types";

type RefreshFn = () => void;

/**
 * PageRenderer — handles the push-navigation page stack.
 *
 * "p-stream" is the home slot. When streamView === "workspace" the home slot
 * renders WorkspacePage inline (no push, so FAB stays visible and back button
 * just switches view back to timeline rather than popping the stack).
 */
function PageRenderer({
  streamRefreshRef,
  streamView,
  onViewChange,
}: {
  streamRefreshRef: React.MutableRefObject<RefreshFn | null>;
  streamView: StreamView;
  onViewChange: (v: StreamView) => void;
}) {
  const { currentPage } = useNav();

  const registerRefresh = useCallback((fn: RefreshFn) => {
    streamRefreshRef.current = fn;
  }, [streamRefreshRef]);

  // Home slot: timeline or workspace depending on streamView
  const homeContent = streamView === "workspace"
    ? <WorkspacePage onClose={() => onViewChange("timeline")} />
    : <StreamPage onRegisterRefresh={registerRefresh} viewMode={streamView} />;

  const pages: Record<PageId, React.ReactNode> = {
    "p-stream":        homeContent,
    "p-agent-chat":    <AgentChatPage />,
    "p-day-view":      <DayViewPage />,
    "p-flash-sess":    <FlashSessionPage />,
    "p-flash-overall": <FlashOverallPage />,
    // p-workspace kept as a deep-link target (e.g. from FlashSessionPage "总资产")
    "p-workspace":     <WorkspacePage />,
    "p-asset-detail":  <AssetDetailPage />,
  };

  return (
    <>
      {(Object.keys(pages) as PageId[]).map((pageId) => (
        <div
          key={pageId}
          style={{
            position: "absolute", inset: 0,
            display: "flex", flexDirection: "column",
            background: "var(--bg)",
            transition: "transform .26s cubic-bezier(.4,0,.2,1), opacity .26s ease",
            willChange: "transform",
            transform: pageId === currentPage ? "translateX(0)" : "translateX(100%)",
            opacity: pageId === currentPage ? 1 : 0,
            pointerEvents: pageId === currentPage ? "auto" : "none",
            zIndex: pageId === currentPage ? 2 : 1,
          }}
        >
          {pages[pageId]}
        </div>
      ))}
    </>
  );
}

function PhoneShell() {
  const { currentPage } = useNav();
  const showFAB = currentPage === "p-stream";
  const streamRefreshRef = useRef<RefreshFn | null>(null);
  const [streamView, setStreamView] = useState<StreamView>("timeline");

  const handleFlashSaved = useCallback(() => {
    // Refresh timeline when a flash note is saved, and switch back to timeline
    // so the user sees their new entry immediately.
    setStreamView("timeline");
    streamRefreshRef.current?.();
  }, []);

  return (
    <div style={{
      width: "393px", height: "852px", borderRadius: "50px",
      background: "var(--bg)", position: "relative",
      display: "flex", flexDirection: "column",
      overflow: "hidden", flexShrink: 0,
      boxShadow: "0 0 0 9px rgba(10,14,30,.9), 0 0 0 10px rgba(59,91,245,.1), 0 12px 40px rgba(15,23,42,.14), 0 2px 8px rgba(15,23,42,.06), inset 0 1px 0 rgba(255,255,255,.7)",
    }}>
      <StatusBar />

      <div style={{
        position: "relative", flex: 1, minHeight: 0,
        overflow: "clip", display: "flex", flexDirection: "column",
      }}>
        <PageRenderer
          streamRefreshRef={streamRefreshRef}
          streamView={streamView}
          onViewChange={setStreamView}
        />
      </div>

      {showFAB && (
        <FABBar
          onFlashSaved={handleFlashSaved}
          streamView={streamView}
          onViewChange={setStreamView}
        />
      )}
    </div>
  );
}

export default function AppShell() {
  return (
    <NavProvider>
      <PhoneShell />
    </NavProvider>
  );
}
