import { useCallback, useEffect, useRef, useState } from "react";
import { useSWRConfig } from "swr";

import { API_BASE } from "@/lib/api";
import { parsePostSseStream } from "@/lib/sse";

/**
 * useChat — orchestrates a single chat session's UI state.
 *
 * Backend contract (api/chat.py):
 *   POST /api/chat { user_text, session_id?, event_id? }
 *   → SSE stream with frames:
 *       event: meta         data: {session_id, input_turn_id}
 *       event: token        data: {text}
 *       event: tool_call    data: {name, args}
 *       event: tool_result  data: {name, response}
 *       event: error        data: {message}
 *       event: done         data: {elapsed_ms, message_id}
 *
 * UI message shape (decoupled from DB Message shape — built for rendering):
 *   - role: 'user' | 'agent'
 *   - user has `text`
 *   - agent has `parts[]` so token/tool_call/tool_result/error can interleave
 *     in the order they arrived
 */

export type ChatPart =
  | { type: "text";        text: string }
  | { type: "tool_call";   name: string; args: Record<string, unknown> }
  | { type: "tool_result"; name: string; response: Record<string, unknown> }
  | { type: "cards";       cards: Array<Record<string, unknown>> }
  | { type: "error";       message: string };

export interface ChatMessage {
  role: "user" | "agent";
  /** Stable UI id for keying — index-based isn't enough because we mutate */
  id: string;
  /** User messages only */
  text?: string;
  /** Agent messages only */
  parts?: ChatPart[];
  /** True while streaming */
  streaming?: boolean;
}

interface UseChatOptions {
  /** session_id to continue. null/empty = backend opens a new session */
  sessionId?: string | null;
  /** event_id to anchor session to (chat-from-event flow) */
  eventId?: string | null;
  /** Initial messages to seed (e.g. from history replay) */
  initialMessages?: ChatMessage[];
}

interface UseChatReturn {
  messages: ChatMessage[];
  /** Currently-active session id (set after first `meta` event) */
  sessionId: string | null;
  /** True while a request is in flight (server still streaming) */
  streaming: boolean;
  /**
   * Send a user message. Optional `sessionIdOverride` is used for lazy
   * session creation (#5, May audit): ChatPage creates the session JIT
   * just before send and passes the new id here — internal state hasn't
   * caught up yet, so we can't rely on `sessionId` alone.
   */
  send: (text: string, sessionIdOverride?: string) => Promise<void>;
  /** Reset to empty — caller is responsible for clearing session_id too */
  reset: (messages?: ChatMessage[]) => void;
  /** Last error from the stream, if any */
  error: string | null;
  /** Manually set the session id (for lazy create — see send override). */
  setSessionId: (id: string | null) => void;
}

export function useChat(opts: UseChatOptions = {}): UseChatReturn {
  const { mutate } = useSWRConfig();
  const [messages, setMessages] = useState<ChatMessage[]>(opts.initialMessages ?? []);
  const [sessionId, setSessionId] = useState<string | null>(opts.sessionId ?? null);
  const [streaming, setStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Keep sessionId in sync if caller switches sessions
  useEffect(() => {
    if (opts.sessionId !== undefined) setSessionId(opts.sessionId);
  }, [opts.sessionId]);

  // Track the current agent message id so streaming events can patch the same
  // message rather than appending a new one per event.
  const agentIdRef = useRef<string | null>(null);

  /** Patch the streaming agent message in place via id */
  const patchAgent = useCallback((mutator: (m: ChatMessage) => ChatMessage) => {
    const id = agentIdRef.current;
    if (!id) return;
    setMessages((prev) => prev.map((m) => (m.id === id ? mutator(m) : m)));
  }, []);

  const send = useCallback(async (text: string, sessionIdOverride?: string) => {
    if (!text.trim() || streaming) return;
    setError(null);

    // 1) Append user message + a fresh agent message (streaming=true)
    const userId  = `u-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
    const agentId = `a-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
    agentIdRef.current = agentId;
    setMessages((prev) => [
      ...prev,
      { id: userId,  role: "user",  text },
      { id: agentId, role: "agent", parts: [], streaming: true },
    ]);
    setStreaming(true);

    // Lazy session create (#5): the override wins because internal state
    // wouldn't have caught up to a session we just created synchronously
    // in the caller's same handler.
    const effectiveSid = sessionIdOverride ?? sessionId ?? "";
    if (sessionIdOverride) setSessionId(sessionIdOverride);

    try {
      const resp = await fetch(`${API_BASE}/api/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({
          user_text: text,
          session_id: effectiveSid,
          event_id: opts.eventId ?? "",
        }),
      });
      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status} — ${await resp.text().catch(() => resp.statusText)}`);
      }

      for await (const frame of parsePostSseStream(resp)) {
        let parsed: unknown;
        try { parsed = JSON.parse(frame.data); } catch { parsed = frame.data; }
        applyFrame(frame.type, parsed);
      }
    } catch (e) {
      const msg = (e as Error).message ?? "chat stream failed";
      setError(msg);
      patchAgent((m) => ({
        ...m,
        parts: [...(m.parts ?? []), { type: "error", message: msg }],
      }));
    } finally {
      setStreaming(false);
      // Clear streaming flag on the agent message
      patchAgent((m) => ({ ...m, streaming: false }));
      // Invalidate related SWR caches so sidebar / asset lists refresh
      await mutate((key) => typeof key === "string" && (
        key.startsWith("/api/sessions") ||
        key.startsWith("/api/assets")
      ));
    }
  }, [streaming, sessionId, opts.eventId, mutate, patchAgent]);

  /** Apply a parsed SSE frame to current state */
  function applyFrame(type: string, data: unknown) {
    switch (type) {
      case "meta": {
        const d = data as { session_id?: string };
        if (d?.session_id) setSessionId(d.session_id);
        return;
      }
      case "token": {
        const d = data as { text?: string };
        if (!d?.text) return;
        patchAgent((m) => mergeText(m, d.text!));
        return;
      }
      case "tool_call": {
        const d = data as { name?: string; args?: Record<string, unknown> };
        patchAgent((m) => ({
          ...m,
          parts: [...(m.parts ?? []), {
            type: "tool_call",
            name: d.name ?? "?",
            args: d.args ?? {},
          }],
        }));
        return;
      }
      case "tool_result": {
        const d = data as { name?: string; response?: Record<string, unknown> };
        patchAgent((m) => ({
          ...m,
          parts: [...(m.parts ?? []), {
            type: "tool_result",
            name: d.name ?? "?",
            response: d.response ?? {},
          }],
        }));
        return;
      }
      case "error": {
        const d = data as { message?: string };
        const msg = d?.message ?? "stream error";
        setError(msg);
        patchAgent((m) => ({
          ...m,
          parts: [...(m.parts ?? []), { type: "error", message: msg }],
        }));
        return;
      }
      case "done":
        return; // finally block handles cleanup
      default:
        return; // unknown frame types ignored
    }
  }

  const reset = useCallback((msgs?: ChatMessage[]) => {
    agentIdRef.current = null;
    setMessages(msgs ?? []);
    setError(null);
  }, []);

  return { messages, sessionId, streaming, send, reset, error, setSessionId };
}

/* ── Helpers ────────────────────────────────────────────────────────────── */

/** Merge an incoming text chunk into the last `text` part, or append a new one. */
function mergeText(m: ChatMessage, chunk: string): ChatMessage {
  const parts = m.parts ?? [];
  const last = parts[parts.length - 1];
  if (last?.type === "text") {
    // Replace last with new text appended
    return {
      ...m,
      parts: [...parts.slice(0, -1), { type: "text", text: last.text + chunk }],
    };
  }
  return { ...m, parts: [...parts, { type: "text", text: chunk }] };
}
