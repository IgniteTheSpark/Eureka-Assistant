import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

import {
  normalizeConnection,
  normalizeDemoSnapshot,
  ringClient as defaultRingClient,
  type RingClient,
} from "../lib/ring-client";
import type {
  DemoMode,
  DemoSnapshot,
  RingConnectionSnapshot,
  RingEvent,
  RingMapping,
  RingStatus,
} from "../lib/types";

const SESSION_KEY = "eureka.ringDemo.sessionId";

const EMPTY_CONNECTION: RingConnectionSnapshot = {
  status: "disconnected",
  connected: false,
  device: null,
  devices: [],
  lastError: null,
};

export type DemoRingClient = Pick<
  RingClient,
  | "acquire"
  | "getStatus"
  | "getConnection"
  | "heartbeat"
  | "release"
  | "releaseOnUnload"
  | "setMode"
  | "subscribe"
>;

export interface DemoContextValue {
  sessionId: string;
  ringStatus: RingStatus;
  connection: RingConnectionSnapshot;
  mode: DemoMode;
  activeApp: string | null;
  mapping: RingMapping;
  events: RingEvent[];
  error: string | null;
  setMode: (mode: DemoMode) => Promise<void>;
  refreshConnection: () => Promise<RingConnectionSnapshot>;
  updateConnection: (connection: RingConnectionSnapshot) => void;
}

const DemoContext = createContext<DemoContextValue | null>(null);

function getTabSessionId() {
  const existing = sessionStorage.getItem(SESSION_KEY);
  if (existing) return existing;
  const sessionId = crypto.randomUUID();
  sessionStorage.setItem(SESSION_KEY, sessionId);
  return sessionId;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Ring Desktop is unavailable";
}

function eventMode(data: Record<string, unknown>): DemoMode | null {
  return data.mode === "idle" || data.mode === "flash" || data.mode === "vibe"
    ? data.mode
    : null;
}

function eventActiveApp(data: Record<string, unknown>) {
  const value = data.activeApp ?? data.active_app ?? data.bundle ?? data.app;
  return typeof value === "string" ? value : null;
}

function eventMapping(data: Record<string, unknown>): RingMapping {
  const value = data.mapping ?? data;
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  return Object.fromEntries(
    Object.entries(value).filter((entry): entry is [string, string] =>
      typeof entry[1] === "string",
    ),
  );
}

export function DemoProvider({
  children,
  ringClient = defaultRingClient,
}: {
  children: ReactNode;
  ringClient?: DemoRingClient;
}) {
  const sessionId = useMemo(getTabSessionId, []);
  const [ringStatus, setRingStatus] = useState<RingStatus>("loading");
  const [connection, setConnection] =
    useState<RingConnectionSnapshot>(EMPTY_CONNECTION);
  const [mode, setModeState] = useState<DemoMode>("idle");
  const [activeApp, setActiveApp] = useState<string | null>(null);
  const [mapping, setMapping] = useState<RingMapping>(null);
  const [events, setEvents] = useState<RingEvent[]>([]);
  const [error, setError] = useState<string | null>(null);

  const applySnapshot = useCallback((snapshot: DemoSnapshot) => {
    setModeState(snapshot.mode);
    setActiveApp(snapshot.activeApp);
    setMapping(snapshot.mapping);
    if (
      snapshot.connection.connected ||
      snapshot.connection.device ||
      snapshot.connection.devices.length > 0 ||
      snapshot.connection.status !== "disconnected"
    ) {
      setConnection(snapshot.connection);
    }
  }, []);

  const refreshConnection = useCallback(async () => {
    const next = await ringClient.getConnection();
    setConnection(next);
    return next;
  }, [ringClient]);

  const refreshStatus = useCallback(async () => {
    const next = await ringClient.getStatus();
    applySnapshot(next);
    return next;
  }, [applySnapshot, ringClient]);

  useEffect(() => {
    let active = true;
    const handleEvent = (event: RingEvent) => {
      if (!active) return;
      setEvents((current) => [...current.slice(-99), event]);
      if (event.event === "snapshot") {
        applySnapshot(normalizeDemoSnapshot(event.data));
      } else if (event.event === "connection.changed") {
        setConnection(normalizeConnection(event.data));
      } else if (event.event === "mode.changed") {
        const nextMode = eventMode(event.data);
        if (nextMode) setModeState(nextMode);
      } else if (event.event === "active_app.changed") {
        setActiveApp(eventActiveApp(event.data));
      } else if (event.event === "mapping.changed") {
        setMapping(eventMapping(event.data));
      }
    };
    const unsubscribe = ringClient.subscribe(handleEvent, () => {
      if (!active) return;
      void refreshStatus().catch((refreshError: unknown) => {
        if (active) setError(errorMessage(refreshError));
      });
    });

    void Promise.all([ringClient.acquire(sessionId), ringClient.getConnection()])
      .then(([snapshot, nextConnection]) => {
        if (!active) return;
        applySnapshot(snapshot);
        setConnection(nextConnection);
        setRingStatus("ready");
        setError(null);
      })
      .catch((setupError: unknown) => {
        if (!active) return;
        setRingStatus("error");
        setError(errorMessage(setupError));
      });

    const heartbeat = window.setInterval(() => {
      void ringClient.heartbeat(sessionId).catch((heartbeatError: unknown) => {
        if (!active) return;
        setRingStatus("error");
        setError(errorMessage(heartbeatError));
      });
    }, 3_000);
    const release = () => ringClient.releaseOnUnload(sessionId);
    window.addEventListener("beforeunload", release);

    return () => {
      active = false;
      window.clearInterval(heartbeat);
      window.removeEventListener("beforeunload", release);
      unsubscribe();
    };
  }, [applySnapshot, refreshStatus, ringClient, sessionId]);

  const setMode = useCallback(
    async (nextMode: DemoMode) => {
      try {
        const snapshot = await ringClient.setMode(sessionId, nextMode);
        applySnapshot(snapshot);
        setError(null);
      } catch (modeError) {
        setError(errorMessage(modeError));
        throw modeError;
      }
    },
    [applySnapshot, ringClient, sessionId],
  );

  const value = useMemo<DemoContextValue>(
    () => ({
      sessionId,
      ringStatus,
      connection,
      mode,
      activeApp,
      mapping,
      events,
      error,
      setMode,
      refreshConnection,
      updateConnection: setConnection,
    }),
    [
      activeApp,
      connection,
      error,
      events,
      mapping,
      mode,
      refreshConnection,
      ringStatus,
      sessionId,
      setMode,
    ],
  );

  return (
    <DemoContext.Provider value={value}>
      {ringStatus === "loading" ? (
        <main className="auth-check">Connecting to Ring Desktop…</main>
      ) : (
        children
      )}
    </DemoContext.Provider>
  );
}

export function useDemo() {
  const value = useContext(DemoContext);
  if (!value) throw new Error("useDemo must be used inside DemoProvider");
  return value;
}

export function useOptionalDemo() {
  return useContext(DemoContext);
}
