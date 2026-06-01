import useSWR, { useSWRConfig } from "swr";

import { apiFetch, swrFetcher } from "@/lib/api";
import type { Event, EventsResponse } from "@/lib/types";

/**
 * useEvents — SWR-cached list of all events, newest start_at first.
 * Drives CalendarPage (Schedule view + MonthGrid dots).
 *
 * No date-range filter MVP: backend caps the list, frontend bucket-sorts
 * by month. If the count grows past ~200 we'll add ?from / ?to params,
 * but that's premature now (M3 deferred-list).
 */
export function useEvents() {
  const { data, error, isLoading, mutate } = useSWR<EventsResponse>(
    "/api/events", swrFetcher,
  );
  return {
    events: data?.events ?? [],
    isLoading,
    error,
    refresh: mutate,
  };
}

/* ── mutation helpers ──────────────────────────────────────────────────── */

export interface EventInput {
  title:            string;
  start_at:         string;        // ISO8601 with TZ — local-tz format works
  end_at?:          string;
  all_day?:         boolean;
  location?:        string;
  description?:     string;
  recurrence_rule?: string;
}

/** POST /api/events — returns the created event_id. */
export async function createEvent(body: EventInput): Promise<string> {
  const resp = await apiFetch<{ ok: boolean; event_id?: string; error?: string }>(
    "/api/events",
    {
      method: "POST",
      body: {
        ...body,
        all_day: body.all_day ? 1 : 0,
      },
    },
  );
  if (!resp.ok || !resp.event_id) throw new Error(resp.error ?? "create event failed");
  return resp.event_id;
}

/** PUT /api/events/:id — partial update; only changed fields. */
export async function updateEvent(eventId: string, patch: Partial<EventInput>): Promise<void> {
  const body: Record<string, unknown> = { ...patch };
  if ("all_day" in patch) body.all_day = patch.all_day ? 1 : 0;
  const resp = await apiFetch<{ ok: boolean; error?: string }>(
    `/api/events/${eventId}`,
    { method: "PUT", body },
  );
  if (!resp.ok) throw new Error(resp.error ?? "update event failed");
}

/** DELETE /api/events/:id */
export async function deleteEvent(eventId: string): Promise<void> {
  const resp = await apiFetch<{ ok: boolean; error?: string }>(
    `/api/events/${eventId}`,
    { method: "DELETE" },
  );
  if (!resp.ok) throw new Error(resp.error ?? "delete event failed");
}

/**
 * useEventMutations — convenience wrapper that wraps create/update/delete
 * with automatic SWR cache invalidation. Use this from EventEditor /
 * DayDetailSheet so the calendar refreshes after a mutation.
 */
export function useEventMutations() {
  const { mutate: globalMutate } = useSWRConfig();
  async function invalidate() {
    await Promise.all([
      globalMutate("/api/events"),
      globalMutate("/api/timeline"),
    ]);
  }
  return {
    async create(body: EventInput) {
      const id = await createEvent(body);
      await invalidate();
      return id;
    },
    async update(eventId: string, patch: Partial<EventInput>) {
      await updateEvent(eventId, patch);
      await invalidate();
    },
    async remove(eventId: string) {
      await deleteEvent(eventId);
      await invalidate();
    },
  };
}

/** Find the event with a given event_id from a pre-fetched list. */
export function findEvent(events: Event[], eventId: string | null): Event | null {
  if (!eventId) return null;
  return events.find((e) => e.event_id === eventId) ?? null;
}
