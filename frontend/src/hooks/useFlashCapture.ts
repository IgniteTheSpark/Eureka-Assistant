import { useCallback, useState } from "react";
import { useSWRConfig } from "swr";

import { apiFetch } from "@/lib/api";

/**
 * useFlashCapture — POST /api/flash, returns the result inline.
 *
 * Backend response shape (api/flash.py FlashResponse):
 *   {ok, session_id, input_turn_id, reply, summary, cards[], derived_assets[], elapsed_ms, error?}
 *
 * Unlike /api/chat, /api/flash is a sync JSON endpoint — no SSE. Each call
 * fans the input across multiple skill agents in parallel on the backend and
 * returns the consolidated result.
 */

export interface FlashCard {
  card_type: string;
  title?: string;
  subtitle?: string;
  icon?: string;
  accent_color?: string;
  asset_id?: string | null;
  event_id?: string | null;
  task_id?: string | null;
  status?: string;
  external_system?: string;
  external_url?: string;
  meta_fields?: Array<{ field: string; value: string; format?: string }>;
}

export interface FlashResponse {
  ok: boolean;
  session_id: string;
  input_turn_id: string;
  reply: string;
  summary: string;
  cards: FlashCard[];
  derived_assets: Array<{ asset_id: string; card: FlashCard }>;
  has_pending?: boolean;
  elapsed_ms: number;
  error?: string;
}

export function useFlashCapture() {
  const { mutate } = useSWRConfig();
  const [submitting, setSubmitting] = useState(false);
  const [lastResult, setLastResult] = useState<FlashResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const capture = useCallback(async (text: string, opts: { sessionId?: string | null } = {}) => {
    if (!text.trim() || submitting) return null;
    setSubmitting(true);
    setError(null);
    try {
      const resp = await apiFetch<FlashResponse>("/api/flash", {
        method: "POST",
        body: {
          text,
          source: "voice", // simulated voice — typing into the sheet
          session_id: opts.sessionId ?? "",
        },
        timeoutMs: 90_000, // flash pipeline can take 30s+ with multi-intent
      });
      setLastResult(resp);
      if (!resp.ok && resp.error) setError(resp.error);
      // Invalidate all relevant caches so library / chat / etc. refresh
      await mutate((key) => typeof key === "string" && (
        key.startsWith("/api/assets") ||
        key.startsWith("/api/events") ||
        key.startsWith("/api/sessions") ||
        key.startsWith("/api/timeline")
      ));
      return resp;
    } catch (e) {
      const msg = (e as Error).message ?? "flash failed";
      setError(msg);
      return null;
    } finally {
      setSubmitting(false);
    }
  }, [submitting, mutate]);

  const reset = useCallback(() => {
    setLastResult(null);
    setError(null);
  }, []);

  return { capture, submitting, lastResult, error, reset };
}
