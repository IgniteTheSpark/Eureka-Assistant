import useSWR from "swr";

import { swrFetcher } from "@/lib/api";
import type { AssetsResponse } from "@/lib/types";

interface UseAssetsOptions {
  skillName?: string;       // filter by user_skill_name (e.g. "todo")
  sessionId?: string;       // filter by session UUID
  contains?: string;        // keyword search in payload
  limit?: number;
}

/**
 * useAssets — SWR-cached fetch from /api/assets.
 *
 * No params: fetch all (capped at 500 by backend).
 * skillName: filter to one type. Used by CategoryDetail.
 * sessionId: filter to one session. Used later by chat / session-bound views.
 */
export function useAssets(opts: UseAssetsOptions = {}) {
  const params = new URLSearchParams();
  if (opts.skillName) params.set("user_skill_name", opts.skillName);
  if (opts.sessionId) params.set("session_id", opts.sessionId);
  if (opts.contains)  params.set("contains", opts.contains);
  if (opts.limit)     params.set("limit", String(opts.limit));

  const qs = params.toString();
  const key = qs ? `/api/assets?${qs}` : "/api/assets";

  const { data, error, isLoading, mutate } = useSWR<AssetsResponse>(key, swrFetcher);

  return {
    assets: data?.assets ?? [],
    isLoading,
    error,
    refresh: mutate,
  };
}
