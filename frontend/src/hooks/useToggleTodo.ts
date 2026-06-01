import { useCallback } from "react";
import { useSWRConfig } from "swr";

import { apiFetch } from "@/lib/api";

/**
 * useToggleTodo — OP3 shared helper for the SkillCard `onToggleCheck`
 * callback when the card is a todo. PUTs /api/assets/:id with the new
 * status, then invalidates the /api/assets|/timeline SWR caches so all
 * surfaces (Library, DayDetail, Schedule, Chat) re-render the new state.
 *
 * Backend's PUT /api/assets/:id merges payload — we only send the
 * delta `{ status }` and the rest is preserved.
 */
export function useToggleTodo() {
  const { mutate } = useSWRConfig();
  return useCallback(async (assetId: string, nextDone: boolean) => {
    try {
      await apiFetch<{ ok: boolean; error?: string }>(
        `/api/assets/${assetId}`,
        {
          method: "PUT",
          // Backend expects `payload_patch` (merged into existing payload),
          // not `payload`. Mismatch on this would 422.
          body: { payload_patch: { status: nextDone ? "done" : "pending" } },
        },
      );
      await mutate((key) => typeof key === "string" && (
        key.startsWith("/api/assets") ||
        key.startsWith("/api/timeline")
      ));
    } catch (e) {
      // eslint-disable-next-line no-alert
      alert("勾选失败:" + ((e as Error).message ?? "未知错误"));
    }
  }, [mutate]);
}
