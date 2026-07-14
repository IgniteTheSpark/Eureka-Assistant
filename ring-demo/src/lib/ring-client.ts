import { requestJson } from "./backend-client";
import type {
  DemoMode,
  DemoSnapshot,
  RingConnectionSnapshot,
  RingDevice,
  RingEvent,
  RingMapping,
} from "./types";

const EVENT_NAMES = [
  "snapshot",
  "connection.changed",
  "mode.changed",
  "recording.started",
  "recording.stopped",
  "asr.started",
  "transcript.ready",
  "active_app.changed",
  "mapping.changed",
] as const;

const EMPTY_CONNECTION: RingConnectionSnapshot = {
  status: "disconnected",
  connected: false,
  device: null,
  devices: [],
  lastError: null,
};

function trimTrailingSlash(value: string) {
  return value.replace(/\/+$/, "");
}

function postJson<T>(url: string, body: Record<string, unknown>) {
  return requestJson<T>(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function hasOwn(record: Record<string, unknown>, key: string) {
  return Object.prototype.hasOwnProperty.call(record, key);
}

function asMode(value: unknown): DemoMode {
  return value === "flash" || value === "vibe" ? value : "idle";
}

export function normalizeConnection(value: unknown): RingConnectionSnapshot {
  const record = asRecord(value);
  return {
    status: typeof record.status === "string" ? record.status : "disconnected",
    connected: record.connected === true,
    device: (record.device as RingDevice | null | undefined) ?? null,
    devices: Array.isArray(record.devices) ? (record.devices as RingDevice[]) : [],
    lastError:
      typeof record.lastError === "string"
        ? record.lastError
        : typeof record.last_error === "string"
          ? record.last_error
          : null,
  };
}

export function normalizeDemoSnapshot(value: unknown): DemoSnapshot {
  const record = asRecord(value);
  const connection = record.connection
    ? normalizeConnection(record.connection)
    : EMPTY_CONNECTION;
  const hasActiveApp =
    hasOwn(record, "activeApp") || hasOwn(record, "active_app");
  const activeApp = record.activeApp ?? record.active_app;
  const hasMapping = hasOwn(record, "mapping");
  const mapping = record.mapping;
  const hasRecording = hasOwn(record, "recording");
  const hasAsrProcessing =
    hasOwn(record, "asrProcessing") || hasOwn(record, "asr_processing");
  const asrProcessing = record.asrProcessing ?? record.asr_processing;
  return {
    sessionId:
      typeof (record.sessionId ?? record.session_id) === "string"
        ? ((record.sessionId ?? record.session_id) as string)
        : null,
    mode: asMode(record.mode),
    generation: typeof record.generation === "number" ? record.generation : 0,
    leaseExpiresAt:
      typeof (record.leaseExpiresAt ?? record.lease_expires_at) === "number"
        ? ((record.leaseExpiresAt ?? record.lease_expires_at) as number)
        : null,
    connection,
    ...(hasActiveApp
      ? { activeApp: typeof activeApp === "string" ? activeApp : null }
      : {}),
    ...(hasMapping
      ? {
          mapping:
            typeof mapping === "object" && mapping !== null
              ? (mapping as RingMapping)
              : null,
        }
      : {}),
    ...(hasRecording ? { recording: record.recording === true } : {}),
    ...(hasAsrProcessing ? { asrProcessing: asrProcessing === true } : {}),
  };
}

export class RingClient {
  private readonly baseUrl: string;

  constructor(baseUrl = "http://127.0.0.1:17863") {
    this.baseUrl = trimTrailingSlash(baseUrl);
  }

  getConnection() {
    return requestJson<unknown>(`${this.baseUrl}/connection`).then(
      normalizeConnection,
    );
  }

  scan() {
    return postJson<Record<string, unknown>>(
      `${this.baseUrl}/connection/scan`,
      {},
    );
  }

  connect(device: RingDevice) {
    return postJson<Record<string, unknown>>(
      `${this.baseUrl}/connection/connect`,
      { address: device.address, name: device.name },
    );
  }

  disconnect() {
    return postJson<Record<string, unknown>>(
      `${this.baseUrl}/connection/disconnect`,
      {},
    );
  }

  async getStatus() {
    const body = await requestJson<unknown>(`${this.baseUrl}/demo/status`);
    return normalizeDemoSnapshot(body);
  }

  async acquire(sessionId: string) {
    const body = await postJson<unknown>(`${this.baseUrl}/demo/session`, {
      sessionId,
    });
    return normalizeDemoSnapshot(body);
  }

  async setMode(sessionId: string, mode: DemoMode) {
    const body = await postJson<unknown>(`${this.baseUrl}/demo/mode`, {
      sessionId,
      mode,
    });
    return normalizeDemoSnapshot(body);
  }

  heartbeat(sessionId: string) {
    return postJson<Record<string, unknown>>(`${this.baseUrl}/demo/heartbeat`, {
      sessionId,
    });
  }

  release(sessionId: string) {
    return postJson<Record<string, unknown>>(`${this.baseUrl}/demo/release`, {
      sessionId,
    });
  }

  releaseOnUnload(sessionId: string) {
    const url = `${this.baseUrl}/demo/release`;
    const body = JSON.stringify({ sessionId });
    try {
      if (navigator.sendBeacon?.(url, body)) return;
    } catch {
      // Fall through to a keepalive request when Beacon is unavailable.
    }
    void fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      keepalive: true,
    }).catch(() => undefined);
  }

  subscribe(
    onEvent: (event: RingEvent) => void,
    onReconnect?: () => void,
  ) {
    const source = new EventSource(`${this.baseUrl}/demo/events`);
    source.onopen = () => onReconnect?.();
    for (const eventName of EVENT_NAMES) {
      source.addEventListener(eventName, (event) => {
        if (!(event instanceof MessageEvent)) return;
        try {
          const parsed = JSON.parse(event.data) as unknown;
          onEvent({ event: eventName, data: asRecord(parsed) });
        } catch {
          // A malformed localhost event should not take down the live demo.
        }
      });
    }
    return () => source.close();
  }
}

export const ringClient = new RingClient();
