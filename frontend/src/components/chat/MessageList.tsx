import { useEffect, useRef } from "react";
import { Loader2 } from "lucide-react";

import { MessageBubble } from "./MessageBubble";
import type { ChatMessage } from "@/hooks/useChat";

/**
 * MessageList — scrolls the conversation. Auto-sticks to the bottom while
 * the user is at (or near) the bottom; if they've scrolled up, leaves them
 * be so new tokens don't yank the viewport.
 */

interface MessageListProps {
  messages: ChatMessage[];
  onPrecipitate?: (text: string) => void;
  /** Optional header shown above the first message (e.g. session title) */
  header?: React.ReactNode;
  /** Flash capture is being processed (input shown, agent result pending) —
   *  render a "正在整理…" indicator so the multi-second gap has feedback. */
  analyzing?: boolean;
}

export function MessageList({ messages, onPrecipitate, header, analyzing }: MessageListProps) {
  const scrollRef  = useRef<HTMLDivElement>(null);
  const stickyRef  = useRef(true);

  // Track whether the user is pinned to the bottom (within 80px tolerance)
  function handleScroll() {
    const el = scrollRef.current;
    if (!el) return;
    const gap = el.scrollHeight - el.scrollTop - el.clientHeight;
    stickyRef.current = gap < 80;
  }

  // After messages change (or the analyzing indicator toggles), scroll to
  // bottom if we're sticky.
  useEffect(() => {
    if (!stickyRef.current) return;
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
  }, [messages, analyzing]);

  if (messages.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center p-eu-xl text-center">
        <div className="text-eu-text-mid text-eu-sm max-w-xs">
          {header ?? (
            <>
              <div className="text-eu-base text-eu-text-hi mb-1">和 Agent 聊点什么</div>
              <div>问任何问题 / 让 AI 帮你做事 / 改之前的资产</div>
            </>
          )}
        </div>
      </div>
    );
  }

  return (
    <div
      ref={scrollRef}
      onScroll={handleScroll}
      className="flex-1 overflow-y-auto eu-noscroll px-eu-md py-eu-md flex flex-col gap-eu-md"
    >
      {header}
      {messages.map((m) => (
        <MessageBubble key={m.id} message={m} onPrecipitate={onPrecipitate} />
      ))}
      {analyzing && (
        <div className="flex justify-start">
          <div className="flex items-center gap-1.5 text-eu-sm text-eu-text-lo italic">
            <Loader2 size={12} strokeWidth={1.75} className="animate-spin" />
            正在整理…
          </div>
        </div>
      )}
    </div>
  );
}
