import useSWR from "swr";

import { apiFetch, swrFetcher } from "@/lib/api";
import type {
  MessagesResponse, SessionDetailResponse, SessionsResponse,
} from "@/lib/types";

/**
 * useSessions — SWR-cached list of sessions, optionally filtered by type/date.
 * Drives SessionSidebar in ChatPage.
 */
export function useSessions(opts: { sessionType?: string; date?: string; limit?: number } = {}) {
  const params = new URLSearchParams();
  if (opts.sessionType) params.set("session_type", opts.sessionType);
  if (opts.date)        params.set("date", opts.date);
  if (opts.limit)       params.set("limit", String(opts.limit));
  const qs = params.toString();
  const key = qs ? `/api/sessions?${qs}` : "/api/sessions";

  const { data, error, isLoading, mutate } = useSWR<SessionsResponse>(key, swrFetcher);
  return {
    sessions: data?.sessions ?? [],
    isLoading,
    error,
    refresh: mutate,
  };
}

/**
 * useSessionMessages — message log for a single session, for ChatPage history replay.
 *
 * Returns null when sessionId is null/empty (don't fetch). This lets ChatPage
 * just pass the current sessionId in and not branch on existence.
 */
export function useSessionMessages(sessionId: string | null | undefined) {
  const key = sessionId ? `/api/sessions/${sessionId}/messages` : null;
  const { data, error, isLoading, mutate } = useSWR<MessagesResponse>(key, swrFetcher);
  return {
    messages: data?.messages ?? [],
    isLoading,
    error,
    refresh: mutate,
  };
}

/**
 * useSessionDetail — full session metadata including context_asset_ids.
 * Used by ContextChipRail to know which assets to render as chips.
 */
export function useSessionDetail(sessionId: string | null | undefined) {
  const key = sessionId ? `/api/sessions/${sessionId}` : null;
  const { data, error, isLoading, mutate } = useSWR<SessionDetailResponse>(key, swrFetcher);
  return {
    session: data?.session ?? null,
    isLoading,
    error,
    refresh: mutate,
  };
}

/**
 * Subject types supported by the unified POST /api/sessions endpoint.
 * Each maps to a FK column on sessions (contact_id / event_id / file_id /
 * subject_asset_id).
 */
export type SubjectType = "contact" | "event" | "file" | "asset";

/**
 * openSession — M3.5 unified session-open helper.
 *
 * Backed by the single POST /api/sessions endpoint. Three modes:
 *
 *   openSession({ subject: { type, id } })            ← home session per
 *                                                       subject (get-or-create)
 *   openSession({ contextAssetIds: [a1, a2] })         ← fresh chat with
 *                                                       initial context
 *   openSession({})                                    ← blank chat
 *
 * Subject mode is used by AssetDetailDrawer's「在 chat 里讨论」 — user can
 * revisit the same Kevin / event / todo discussion as one continuous thread.
 *
 * Replaces the M2.2 `createChatSessionWithContext` and the M2.3
 * `getOrCreateSubjectSession` helpers (both removed).
 */
export interface OpenSessionInput {
  subject?:          { type: SubjectType; id: string };
  contextAssetIds?:  string[];
  sessionType?:      "flash" | "chat" | "meeting" | "manual";
  title?:            string;
  /**
   * Lazy mode (#5, May audit). When `true` AND subject is given, the call
   * returns the existing session id or `null` WITHOUT creating one. Used by
   * the dock to decide: open the existing thread, or just navigate /chat
   * blank with a pending-subject hint so creation defers to first send.
   */
  peekOnly?:         boolean;
}

export interface OpenSessionResult {
  /** null only happens in peek mode when no session exists yet. */
  sessionId: string | null;
  created:   boolean;             // false → returned existing OR peek-not-found
  contextAssetIds: string[];
}

export async function openSession(input: OpenSessionInput): Promise<OpenSessionResult> {
  const body: Record<string, unknown> = {
    session_type: input.sessionType ?? "chat",
  };
  if (input.title)            body.title = input.title;
  if (input.contextAssetIds)  body.context_asset_ids = input.contextAssetIds;
  if (input.subject) {
    body.subject_type = input.subject.type;
    body.subject_id   = input.subject.id;
  }
  if (input.peekOnly) body.peek_only = true;
  const resp = await apiFetch<{
    ok: boolean; session_id: string | null; created?: boolean;
    context_asset_ids?: string[]; error?: string;
  }>("/api/sessions", { method: "POST", body });
  if (!resp.ok) {
    throw new Error(resp.error ?? "failed to open session");
  }
  // peek_only=true is allowed to return session_id=null; create mode is not.
  if (resp.session_id == null && !input.peekOnly) {
    throw new Error("backend returned no session_id");
  }
  return {
    sessionId: resp.session_id,
    created:   resp.created ?? false,
    contextAssetIds: resp.context_asset_ids ?? [],
  };
}

/**
 * patchSessionContext — M2.3 add/remove context_asset_ids on a live session.
 * Used by ContextChipRail's「+ 添加资产」 picker and the chip × remove button.
 */
export async function patchSessionContext(
  sessionId: string,
  changes: { add?: string[]; remove?: string[] },
): Promise<string[]> {
  const resp = await apiFetch<{ ok: boolean; context_asset_ids: string[]; error?: string }>(
    `/api/sessions/${sessionId}/context`,
    { method: "PATCH", body: changes },
  );
  if (!resp.ok) throw new Error(resp.error ?? "patch context failed");
  return resp.context_asset_ids ?? [];
}
