/**
 * lib/sse — two SSE consumption paths.
 *
 * 1. `openSse(url, ...)`           — for GET endpoints that follow native
 *                                     EventSource. Used by useNotifications (M6).
 * 2. `parsePostSseStream(response)` — for POST→stream endpoints that emit SSE
 *                                     but require a body. Native EventSource
 *                                     can't POST, so we fetch + parse the
 *                                     ReadableStream manually.
 *                                     Used by useChat (M2).
 *
 *
 * Used by:
 *  - useChat (M2): subscribes to a POST-then-stream pattern, but for native
 *    EventSource we hit `/api/chat/stream?session_id=…` GET endpoints.
 *  - useNotifications (M6): subscribes to /api/notifications/stream
 *
 * Backend currently emits SSE for /api/chat as a POST → stream (not standard
 * EventSource POST support); for that case useChat parses fetch streaming
 * directly. This helper is for true GET-EventSource streams.
 */

export interface SseHandlers {
  /** Called for every event regardless of `event:` name. */
  onMessage?: (event: { type: string; data: string; id?: string }) => void;
  /** Called when the underlying connection opens. */
  onOpen?: () => void;
  /** Called on hard errors; reconnect logic decides whether to retry. */
  onError?: (err: Error) => void;
  /** Called when subscription is closed (manually or after retry budget). */
  onClose?: () => void;
}

export interface SseOptions {
  /** Map of `event:` name → handler. Falls back to `onMessage`. */
  events?: Record<string, (data: string, id?: string) => void>;
  /** Reconnect strategy. */
  reconnect?: {
    enabled?: boolean;
    initialDelayMs?: number;
    maxDelayMs?: number;
    maxAttempts?: number;
  };
}

export interface SseSubscription {
  close: () => void;
}

const DEFAULT_RECONNECT = {
  enabled: true,
  initialDelayMs: 1_000,
  maxDelayMs: 15_000,
  maxAttempts: Infinity,
};

/**
 * Open an SSE subscription. Auto-reconnects on transient errors with
 * exponential backoff. Returns an object with .close() to tear down.
 *
 * NB: EventSource is GET-only. For POST→stream (current /api/chat), do not use
 * this; fetch + ReadableStream is the right tool (see useChat).
 */
export function openSse(url: string, handlers: SseHandlers, opts: SseOptions = {}): SseSubscription {
  const reconnect = { ...DEFAULT_RECONNECT, ...(opts.reconnect ?? {}) };
  let attempt = 0;
  let closed = false;
  let es: EventSource | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;

  function connect() {
    if (closed) return;
    es = new EventSource(url);

    es.onopen = () => {
      attempt = 0; // reset on successful connect
      handlers.onOpen?.();
    };

    es.onmessage = (ev) => {
      handlers.onMessage?.({ type: "message", data: ev.data, id: ev.lastEventId });
    };

    es.onerror = (ev) => {
      const err = new Error("SSE connection error");
      handlers.onError?.(err);
      es?.close();
      es = null;
      // Browser EventSource auto-retries, but we want explicit control to
      // surface errors and cap attempts.
      if (closed) return;
      if (!reconnect.enabled || attempt >= reconnect.maxAttempts) {
        handlers.onClose?.();
        return;
      }
      const delay = Math.min(
        reconnect.initialDelayMs * 2 ** attempt,
        reconnect.maxDelayMs,
      );
      attempt += 1;
      retryTimer = setTimeout(connect, delay);
      void ev; // silence unused
    };

    // Named events from `events:` map
    for (const [name, fn] of Object.entries(opts.events ?? {})) {
      es.addEventListener(name, (ev) => {
        const me = ev as MessageEvent;
        fn(me.data, me.lastEventId);
      });
    }
  }

  connect();

  return {
    close() {
      closed = true;
      if (retryTimer) clearTimeout(retryTimer);
      es?.close();
      handlers.onClose?.();
    },
  };
}

/* ── POST→stream consumer ───────────────────────────────────────────────── */

export interface SseFrame {
  /** Value of `event:` line (defaults to "message" if not specified). */
  type: string;
  /** Raw `data:` payload (concatenated if multi-line; not JSON-parsed). */
  data: string;
  /** Value of `id:` line if present. */
  id?: string;
}

/**
 * Parse a fetch Response whose body is an SSE stream — works for POST endpoints
 * (backend `/api/chat` emits SSE over a POST). Yields events as they arrive.
 *
 * Usage:
 *   const resp = await fetch('/api/chat', { method: 'POST', ... });
 *   for await (const frame of parsePostSseStream(resp)) {
 *     if (frame.type === 'token') { ... }
 *   }
 *
 * Handles:
 *   - multi-line `data:` (concatenated with \n)
 *   - `event:` per-frame override
 *   - `id:` field
 *   - comment lines (start with `:`) — silently skipped
 *   - chunked decoding with partial-event buffering across reads
 */
export async function* parsePostSseStream(response: Response): AsyncGenerator<SseFrame> {
  if (!response.body) {
    throw new Error("response.body is null — can't stream");
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder("utf-8");
  let buffer = "";

  try {
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // SSE frames are separated by a blank line (\n\n). Split on \n\n and
      // keep the last (possibly incomplete) chunk in the buffer.
      const parts = buffer.split(/\n\n/);
      buffer = parts.pop() ?? "";

      for (const raw of parts) {
        const frame = parseFrame(raw);
        if (frame) yield frame;
      }
    }
    // Flush trailing partial (rare but happens if server closed cleanly)
    if (buffer.trim()) {
      const frame = parseFrame(buffer);
      if (frame) yield frame;
    }
  } finally {
    reader.releaseLock();
  }
}

function parseFrame(raw: string): SseFrame | null {
  const lines = raw.split(/\n/);
  let type = "message";
  let id: string | undefined;
  const dataLines: string[] = [];

  for (const line of lines) {
    if (!line || line.startsWith(":")) continue; // blank or comment
    const colonIdx = line.indexOf(":");
    if (colonIdx === -1) continue;
    const field = line.slice(0, colonIdx);
    // Per SSE spec, optional single space after colon is stripped
    let value = line.slice(colonIdx + 1);
    if (value.startsWith(" ")) value = value.slice(1);

    if (field === "event") type = value;
    else if (field === "id") id = value;
    else if (field === "data") dataLines.push(value);
    // unknown fields silently ignored per spec
  }

  if (dataLines.length === 0) return null;
  return { type, data: dataLines.join("\n"), id };
}
