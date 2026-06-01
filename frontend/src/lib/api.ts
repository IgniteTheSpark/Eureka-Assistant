/**
 * lib/api — thin fetch wrapper for the Eureka backend.
 *
 * Production deploy will fold backend + frontend behind the same origin, so
 * `BASE` defaults to "" and requests go to `/api/...`. In dev (Vite), the
 * proxy in vite.config.ts forwards /api → http://localhost:8000.
 *
 * Override at build time via `VITE_API_BASE` (e.g. for hitting a staging
 * backend from a deployed preview).
 */

export const API_BASE = import.meta.env.VITE_API_BASE ?? "";

export class ApiError extends Error {
  status: number;
  body: unknown;
  constructor(message: string, status: number, body: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

interface FetchOpts extends Omit<RequestInit, "body"> {
  body?: unknown; // we JSON.stringify if not a FormData/Blob
  timeoutMs?: number;
}

export async function apiFetch<T = unknown>(path: string, opts: FetchOpts = {}): Promise<T> {
  const { body, timeoutMs = 30_000, headers, ...rest } = opts;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  const isFormish = body instanceof FormData || body instanceof Blob;
  const finalHeaders: Record<string, string> = {
    Accept: "application/json",
    ...(isFormish ? {} : { "Content-Type": "application/json" }),
    ...(headers as Record<string, string> | undefined),
  };

  try {
    const res = await fetch(`${API_BASE}${path}`, {
      ...rest,
      signal: controller.signal,
      headers: finalHeaders,
      body: body === undefined ? undefined : isFormish ? body : JSON.stringify(body),
    });

    const text = await res.text();
    let parsed: unknown = text;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      /* leave as text */
    }

    if (!res.ok) {
      throw new ApiError(`${res.status} ${res.statusText} — ${path}`, res.status, parsed);
    }
    return parsed as T;
  } finally {
    clearTimeout(timer);
  }
}

/** SWR-friendly fetcher: same as apiFetch but bound to GET by default. */
export const swrFetcher = <T = unknown>(path: string) => apiFetch<T>(path);
