import useSWR from "swr";

import { swrFetcher } from "@/lib/api";
import type { TimelineResponse, TimelineItem } from "@/lib/types";

/**
 * useTimeline — combined event + asset timeline used by CalendarPage's
 * Schedule view and MonthGrid dots.
 *
 * Backend already sorts items by effective_at desc; we expose them as-is
 * plus a `byDay` map keyed by local-date string (YYYY-MM-DD) for grid
 * rendering.
 */
export function useTimeline() {
  const { data, error, isLoading, mutate } = useSWR<TimelineResponse>(
    "/api/timeline", swrFetcher,
  );
  const items = data?.items ?? [];
  const byDay = bucketByLocalDay(items);
  return { items, byDay, isLoading, error, refresh: mutate };
}

/**
 * Bucket items by their effective_at day in the user's LOCAL timezone.
 * Returns Map<"YYYY-MM-DD", TimelineItem[]> — handy for both ScheduleView
 * (list days top-down) and MonthGrid (count dots per cell).
 *
 * Items inside each day are ordered ascending by effective_at so a single
 * day reads chronologically (morning → evening).
 */
export function bucketByLocalDay(items: TimelineItem[]): Map<string, TimelineItem[]> {
  const out = new Map<string, TimelineItem[]>();
  for (const it of items) {
    const key = toLocalDayKey(it.effective_at);
    const arr = out.get(key) ?? [];
    arr.push(it);
    out.set(key, arr);
  }
  for (const arr of out.values()) {
    arr.sort((a, b) => a.effective_at.localeCompare(b.effective_at));
  }
  return out;
}

/** Format a UTC/TZ ISO string as YYYY-MM-DD in the user's local TZ. */
export function toLocalDayKey(iso: string): string {
  const d = new Date(iso);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}
