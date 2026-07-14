import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
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

type RetryRequest =
  | { kind: "session" }
  | { kind: "mode"; mode: DemoMode };

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
  generation: number;
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

function eventGeneration(data: Record<string, unknown>) {
  return typeof data.generation === "number" ? data.generation : null;
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
  const mountedRef = useRef(false);
  const generationRef = useRef(0);
  const modeIntentRef = useRef(0);
  const modeQueueRef = useRef<Promise<void>>(Promise.resolve());
  const [ringStatus, setRingStatus] = useState<RingStatus>("loading");
  const [connection, setConnection] =
    useState<RingConnectionSnapshot>(EMPTY_CONNECTION);
  const [mode, setModeState] = useState<DemoMode>("idle");
  const [generation, setGeneration] = useState(0);
  const [activeApp, setActiveApp] = useState<string | null>(null);
  const [mapping, setMapping] = useState<RingMapping>(null);
  const [events, setEvents] = useState<RingEvent[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [retryRequest, setRetryRequest] = useState<RetryRequest | null>(null);

  const clearError = useCallback(() => {
    setError(null);
    setRetryRequest(null);
  }, []);

  const showError = useCallback((nextError: unknown, retry: RetryRequest) => {
    setError(errorMessage(nextError));
    setRetryRequest(retry);
  }, []);

  const applySnapshot = useCallback((snapshot: DemoSnapshot) => {
    if (snapshot.generation < generationRef.current) return false;
    generationRef.current = snapshot.generation;
    setGeneration(snapshot.generation);
    setModeState(snapshot.mode);
    if ("activeApp" in snapshot) setActiveApp(snapshot.activeApp ?? null);
    if ("mapping" in snapshot) setMapping(snapshot.mapping ?? null);
    if (
      snapshot.connection.connected ||
      snapshot.connection.device ||
      snapshot.connection.devices.length > 0 ||
      snapshot.connection.status !== "disconnected"
    ) {
      setConnection(snapshot.connection);
    }
    return true;
  }, []);

  const applyModeEvent = useCallback(
    (data: Record<string, unknown>) => {
      const nextMode = eventMode(data);
      const nextGeneration = eventGeneration(data);
      if (
        !nextMode ||
        nextGeneration === null ||
        nextGeneration < generationRef.current
      ) {
        return;
      }
      generationRef.current = nextGeneration;
      setGeneration(nextGeneration);
      setModeState(nextMode);
    },
    [],
  );

  const refreshConnection = useCallback(async () => {
    const next = await ringClient.getConnection();
    if (mountedRef.current) setConnection(next);
    return next;
  }, [ringClient]);

  const refreshStatus = useCallback(async () => {
    const next = await ringClient.getStatus();
    if (mountedRef.current) applySnapshot(next);
    return next;
  }, [applySnapshot, ringClient]);

  const initialize = useCallback(async () => {
    setRingStatus("loading");
    clearError();
    try {
      const [snapshot, nextConnection] = await Promise.all([
        ringClient.acquire(sessionId),
        ringClient.getConnection(),
      ]);
      if (!mountedRef.current) return;
      applySnapshot(snapshot);
      setConnection(nextConnection);
      setRingStatus("ready");
      clearError();
    } catch (setupError) {
      if (!mountedRef.current) return;
      setRingStatus("error");
      showError(setupError, { kind: "session" });
    }
  }, [applySnapshot, clearError, ringClient, sessionId, showError]);

  useEffect(() => {
    mountedRef.current = true;
    const handleEvent = (event: RingEvent) => {
      if (!mountedRef.current) return;
      setEvents((current) => [...current.slice(-99), event]);
      if (event.event === "snapshot") {
        applySnapshot(normalizeDemoSnapshot(event.data));
      } else if (event.event === "connection.changed") {
        setConnection(normalizeConnection(event.data));
      } else if (event.event === "mode.changed") {
        applyModeEvent(event.data);
      } else if (event.event === "active_app.changed") {
        setActiveApp(eventActiveApp(event.data));
      } else if (event.event === "mapping.changed") {
        setMapping(eventMapping(event.data));
      }
    };
    const unsubscribe = ringClient.subscribe(handleEvent, () => {
      if (!mountedRef.current) return;
      void refreshStatus().catch((refreshError: unknown) => {
        if (mountedRef.current) showError(refreshError, { kind: "session" });
      });
    });

    void initialize();
    const heartbeat = window.setInterval(() => {
      void ringClient.heartbeat(sessionId).catch((heartbeatError: unknown) => {
        if (!mountedRef.current) return;
        setRingStatus("error");
        showError(heartbeatError, { kind: "session" });
      });
    }, 3_000);
    const release = () => ringClient.releaseOnUnload(sessionId);
    window.addEventListener("beforeunload", release);

    return () => {
      mountedRef.current = false;
      window.clearInterval(heartbeat);
      window.removeEventListener("beforeunload", release);
      unsubscribe();
    };
  }, [
    applyModeEvent,
    applySnapshot,
    initialize,
    refreshStatus,
    ringClient,
    sessionId,
    showError,
  ]);

  const setMode = useCallback(
    (nextMode: DemoMode) => {
      const intent = ++modeIntentRef.current;
      const operation = modeQueueRef.current
        .catch(() => undefined)
        .then(async () => {
          try {
            const snapshot = await ringClient.setMode(sessionId, nextMode);
            if (!mountedRef.current || intent !== modeIntentRef.current) return;
            applySnapshot(snapshot);
            clearError();
          } catch (modeError) {
            if (mountedRef.current && intent === modeIntentRef.current) {
              showError(modeError, { kind: "mode", mode: nextMode });
            }
            throw modeError;
          }
        });
      modeQueueRef.current = operation.catch(() => undefined);
      return operation;
    },
    [applySnapshot, clearError, ringClient, sessionId, showError],
  );

  const retryError = useCallback(async () => {
    const request = retryRequest;
    if (!request) return;
    clearError();
    if (request.kind === "session") {
      await initialize();
      return;
    }
    try {
      await setMode(request.mode);
    } catch {
      // setMode restores the actionable error for another retry.
    }
  }, [clearError, initialize, retryRequest, setMode]);

  const value = useMemo<DemoContextValue>(
    () => ({
      sessionId,
      ringStatus,
      connection,
      mode,
      generation,
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
      generation,
      mapping,
      mode,
      refreshConnection,
      ringStatus,
      sessionId,
      setMode,
    ],
  );

  const errorSurface = error ? (
    <section className="demo-error" role="alert">
      <p>{error}</p>
      <button onClick={() => void retryError()} type="button">
        Retry Ring session
      </button>
    </section>
  ) : null;

  return (
    <DemoContext.Provider value={value}>
      {ringStatus === "loading" ? (
        <main className="auth-check">Connecting to Ring Desktop…</main>
      ) : ringStatus === "error" ? (
        <main className="auth-check auth-error">{errorSurface}</main>
      ) : (
        <>
          {errorSurface}
          {children}
        </>
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
