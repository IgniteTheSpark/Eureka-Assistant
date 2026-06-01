import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, History } from "lucide-react";
import { useLocation, useNavigate } from "react-router-dom";

import { ChatInput } from "@/components/chat/ChatInput";
import { MessageList } from "@/components/chat/MessageList";
import { SessionSidebar } from "@/components/chat/SessionSidebar";
import { SessionTopicBar } from "@/components/chat/SessionTopicBar";
import { useChat, type ChatMessage, type ChatPart } from "@/hooks/useChat";
import { openSession, useSessionDetail, useSessionMessages, type SubjectType } from "@/hooks/useSessions";
import type { Message as DbMessage } from "@/lib/types";

const ACTIVE_SESSION_KEY = "eureka:active_chat_session";

/** Router state shape that other pages pass when navigating to /chat. */
interface ChatRouteState {
  from?:      string;   // pathname to return to via back button
  fromLabel?: string;   // short label for the back button, e.g. "Kevin"
  /**
   * Lazy session-create hint (#5, May audit). The dock's Agent button passes
   * this when no session for the subject exists yet — ChatPage shows the
   * subject in the topic bar but defers POST /api/sessions until first send.
   */
  pendingSubject?: { type: SubjectType; id: string };
  pendingLabel?:   string;
}

/**
 * ChatPage — M2 implementation.
 *
 * Layout:
 *   ┌────────────┬────────────────────────┐
 *   │SessionSide │  ┌──────────────────┐  │
 *   │  (desktop) │  │  MessageList     │  │
 *   │            │  │   (scrolls)      │  │
 *   │            │  └──────────────────┘  │
 *   │            │  ┌──────────────────┐  │
 *   │            │  │  ChatInput       │  │
 *   │            │  └──────────────────┘  │
 *   └────────────┴────────────────────────┘
 *
 * Mobile: sidebar collapses into a drawer; toggled by the History icon on
 * the page's own toolbar (top of right column).
 *
 * State machine:
 *   - activeSessionId persists in localStorage so reload picks up where left
 *   - useSessionMessages fetches that session's history → seed into useChat
 *   - Sending merges live SSE stream into the same messages array
 *   - Switching session → reset messages, useSessionMessages re-fetches
 */
export function ChatPage() {
  const navigate = useNavigate();
  const location = useLocation();
  // Read router state ONCE at mount — pendingSubject is a one-shot hint, not
  // a reactive prop. If we re-read it on every render, switching sessions
  // inside /chat would resurrect a stale pending subject.
  const initialRouterState = useMemo(
    () => (location.state ?? {}) as ChatRouteState,
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  const [activeSessionId, setActiveSessionId] = useState<string | null>(() => {
    // If the dock handed us a pendingSubject, we deliberately start blank —
    // the existing localStorage session would shadow the new binding intent.
    if (initialRouterState.pendingSubject) return null;
    if (typeof window === "undefined") return null;
    return window.localStorage.getItem(ACTIVE_SESSION_KEY) || null;
  });
  const [pendingSubject, setPendingSubject] = useState<ChatRouteState["pendingSubject"] | null>(
    initialRouterState.pendingSubject ?? null,
  );
  const [pendingLabel, setPendingLabel] = useState<string | null>(
    initialRouterState.pendingLabel ?? null,
  );
  const [sidebarOpen, setSidebarOpen] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (activeSessionId) window.localStorage.setItem(ACTIVE_SESSION_KEY, activeSessionId);
    else window.localStorage.removeItem(ACTIVE_SESSION_KEY);
  }, [activeSessionId]);

  // Load history + session detail (for context_asset_ids) for the active session
  const { messages: dbMessages, isLoading: historyLoading } = useSessionMessages(activeSessionId);
  const { session: sessionDetail } = useSessionDetail(activeSessionId);

  // Convert DB messages → ChatMessage format (consistent with live stream)
  const initialMessages = useMemo<ChatMessage[]>(() => dbMessages.map(dbToChatMessage), [dbMessages]);

  // Chat orchestrator — pass session id + seed messages
  const chat = useChat({
    sessionId: activeSessionId,
    initialMessages,
  });

  // Flash captures run server-side (no chat stream), so the agent result lands
  // seconds after the input. While a flash session's last message is an
  // unpaired user message, show a "正在整理…" indicator so the gap has feedback.
  const lastMsg = chat.messages[chat.messages.length - 1];
  const flashAnalyzing =
    sessionDetail?.session_type === "flash" && !chat.streaming && lastMsg?.role === "user";

  // Seed the chat from DB history ONLY when we genuinely have nothing live.
  //
  // The naive `chat.reset(initialMessages)` on every initialMessages change
  // had a race (issue #3, May audit): when the user sent the FIRST message
  // of a new session, SSE `meta` minted a session_id → activeSessionId
  // updated → SWR re-fetched (empty) → initialMessages identity changed →
  // reset() wiped the optimistic user bubble. Now the live messages stayed
  // hidden until the agent finished streaming, when SWR refetched the
  // persisted pair and showed both.
  //
  // Re-seed rules:
  //   - first mount / after switching session (chat empty) → seed
  //   - LIVE EXTERNAL GROWTH: the server gained messages this view doesn't
  //     have — e.g. a hardware card flash wrote to the SAME session while
  //     it's open. The flash-done notification revalidates this session's
  //     /messages SWR key, so initialMessages grows; re-seed so the new turn
  //     appears with no manual refresh.
  //   - NEVER mid-stream: would wipe the optimistic / streaming bubble
  //     (issue #3, May audit). Skip entirely while streaming; the post-stream
  //     SWR revalidation re-runs this effect when it's safe.
  //
  // Length comparison is safe against loops: after a re-seed chat.messages
  // equals initialMessages, so the `>` guard goes false. Optimistic sends
  // (chat grows first, server catches up to equal length) never trigger it.
  useEffect(() => {
    if (chat.streaming) return;
    const empty = chat.messages.length === 0;
    const serverHasMore = initialMessages.length > chat.messages.length;
    if ((empty && initialMessages.length > 0) || serverHasMore) {
      chat.reset(initialMessages);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialMessages]);

  // When backend tells us the session_id (first turn of a new session),
  // remember it so subsequent turns continue + history loads next reload.
  useEffect(() => {
    if (chat.sessionId && chat.sessionId !== activeSessionId) {
      setActiveSessionId(chat.sessionId);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chat.sessionId]);

  const handleSelectSession = useCallback((id: string | null) => {
    setActiveSessionId(id);
    setPendingSubject(null); // sidebar switch dismisses any deferred binding
    setPendingLabel(null);
    chat.reset([]); // optimistic; useEffect above will re-seed when history loads
  }, [chat]);

  /**
   * Lazy-create wrapper around chat.send (#5, May audit). When a
   * pendingSubject is active and we have no session yet, we get-or-create
   * the subject session first, then send with that id. Stops empty subject
   * sessions from littering history on a stray Agent tap.
   */
  const handleSend = useCallback(async (text: string) => {
    if (pendingSubject && !chat.sessionId && !activeSessionId) {
      try {
        const { sessionId } = await openSession({ subject: pendingSubject });
        if (sessionId) {
          setActiveSessionId(sessionId);
          setPendingSubject(null);
          setPendingLabel(null);
          await chat.send(text, sessionId);
          return;
        }
      } catch {
        // Fall through to plain send; backend will create a non-bound session.
      }
    }
    await chat.send(text);
  }, [pendingSubject, chat, activeSessionId]);

  const handlePrecipitate = useCallback((_text: string) => {
    // M2 placeholder — M5 / future will open the SkillCreateForm with the
    // text pre-filled into the relevant skill (probably notes by default).
    alert("「沉淀为资产」M5 接 design-agent 后会展开;\n目前先用 dock 的 + 按钮手动创建。");
  }, []);

  // ── Back-button "上级" resolution (M3.5) ───────────────────────────────
  // Priority:
  //   1. router state.from passed by the page that navigated us here
  //      (e.g. AssetDetailDrawer's 在 chat 里讨论 button)
  //   2. fallback to /library so back never strands the user
  // The label rendered next to the arrow comes from state.fromLabel when
  // provided, else a path-derived default.
  const routerState = (location.state ?? {}) as ChatRouteState;
  const backTarget = routerState.from ?? "/library";
  const backLabel  = routerState.fromLabel
    ?? defaultLabelForPath(routerState.from)
    ?? "资产库";

  function handleBack() {
    navigate(backTarget);
  }

  return (
    // h-full = fit within AppShell's <main>. M3.5: dock hidden on /chat
    // so we get the full height for sidebar + chat column.
    <div className="flex h-full">
      <SessionSidebar
        activeId={activeSessionId}
        onSelect={handleSelectSession}
        open={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
      />

      <div className="flex-1 flex flex-col min-w-0">
        {/* ── Top nav (M4-polish): minimal — back + centered title only.
            Removed home button (back's fallback already lands at /library)
            and 「+ 新对话」 (sidebar's 「+ 新建对话」 already covers it).
            Mobile keeps the history toggle since sidebar isn't visible.  */}
        <div className="flex items-center gap-eu-sm px-eu-md py-eu-sm border-b border-eu-rule bg-eu-bg/70 backdrop-blur shrink-0">
          <button
            type="button"
            onClick={handleBack}
            className="inline-flex items-center gap-1 text-eu-sm text-eu-text-mid hover:text-eu-text-hi rounded-eu-md px-1.5 py-1 hover:bg-eu-surface-hover active:scale-95"
            aria-label={`返回 ${backLabel}`}
          >
            <ArrowLeft size={14} strokeWidth={2} />
            <span className="max-w-[14ch] truncate">{backLabel}</span>
          </button>

          <div className="flex-1 min-w-0 text-center text-eu-sm text-eu-text-hi font-medium truncate">
            {sessionDetail?.title
              ?? (pendingSubject ? `${pendingLabel ?? "新对话"}` : null)
              ?? (activeSessionId ? `对话 ${activeSessionId.slice(0, 6)}` : "新对话")}
          </div>

          {/* History opener — always shown now that PhoneFrame collapsed
              the previously-desktop persistent sidebar into a drawer. */}
          <button
            type="button"
            onClick={() => setSidebarOpen(true)}
            className="inline-flex items-center gap-1 text-eu-sm text-eu-text-mid hover:text-eu-text-hi rounded-eu-md px-1.5 py-1 hover:bg-eu-surface-hover active:scale-95"
            aria-label="对话历史"
            title="对话历史"
          >
            <History size={14} strokeWidth={1.75} />
          </button>
        </div>

        {historyLoading && activeSessionId && (
          <div className="text-eu-xs text-eu-text-lo px-eu-md py-eu-sm font-mono shrink-0">加载历史…</div>
        )}

        {/* RV1: SessionTopicBar = merged subject + context one-liner.
            Replaces SubjectBanner (top row) + ContextChipRail (next row).
            Also rendered for a *pending* subject (#5 lazy create) so the
            user sees "you're about to talk about Kevin" before they send. */}
        {(activeSessionId || pendingSubject) && (
          <div className="shrink-0">
            <SessionTopicBar
              contactId={sessionDetail?.contact_id ?? (pendingSubject?.type === "contact" ? pendingSubject.id : null)}
              eventId={sessionDetail?.event_id ?? (pendingSubject?.type === "event" ? pendingSubject.id : null)}
              fileId={sessionDetail?.file_id ?? (pendingSubject?.type === "file" ? pendingSubject.id : null)}
              subjectAssetId={sessionDetail?.subject_asset_id ?? (pendingSubject?.type === "asset" ? pendingSubject.id : null)}
              contextAssetIds={sessionDetail?.context_asset_ids ?? []}
              sessionId={activeSessionId}
            />
          </div>
        )}

        {/* Messages — MessageList owns its own scroll (flex-1 overflow-y-auto
            internally), so siblings with shrink-0 stay pinned. */}
        <MessageList
          messages={chat.messages}
          onPrecipitate={handlePrecipitate}
          analyzing={flashAnalyzing}
        />

        {/* Sticky bottom — AppShell's pb-0 on /chat lets this sit flush. */}
        <div className="shrink-0">
          <ChatInput
            onSend={handleSend}
            streaming={chat.streaming}
          />
        </div>
      </div>
    </div>
  );
}

/**
 * Derive a sensible "back to X" label from the pathname the user came from.
 * Used when AssetDetailDrawer / other navigators only pass `from` and not
 * an explicit `fromLabel`.
 */
function defaultLabelForPath(path?: string): string | null {
  if (!path) return null;
  if (path.startsWith("/library"))      return "资产库";
  if (path.startsWith("/calendar"))     return "日历";
  if (path.startsWith("/notifications")) return "通知";
  if (path === "/" || path === "")      return "首页";
  return "上一页";
}

/**
 * Convert a DB Message row into the ChatMessage shape useChat uses.
 *
 * DB Message has flat fields (text, tool_call, tool_result, cards) and a
 * single `role`. We split them into ordered parts so the bubble renderer
 * can show them in the same sequence as live-streamed events.
 *
 * Order chosen to feel natural: tool_call → tool_result → text → cards.
 */
function dbToChatMessage(m: DbMessage): ChatMessage {
  if (m.role === "user") {
    return { id: m.id, role: "user", text: m.text ?? "" };
  }
  const parts: ChatPart[] = [];
  if (m.tool_call) {
    parts.push({
      type: "tool_call",
      name: m.tool_call.name,
      args: (m.tool_call.args as Record<string, unknown>) ?? {},
    });
  }
  if (m.tool_result) {
    parts.push({
      type: "tool_result",
      name: m.tool_result.name,
      response: (m.tool_result.response as Record<string, unknown>) ?? {},
    });
  }
  if (m.text) {
    parts.push({ type: "text", text: m.text });
  }
  if (Array.isArray(m.cards) && m.cards.length > 0) {
    parts.push({ type: "cards", cards: m.cards as Array<Record<string, unknown>> });
  }
  return { id: m.id, role: "agent", parts };
}
