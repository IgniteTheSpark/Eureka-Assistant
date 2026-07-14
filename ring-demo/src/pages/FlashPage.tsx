import { useCallback, useEffect, useMemo, useReducer, useRef } from "react";
import { Link } from "react-router-dom";

import { AssetCard } from "../components/AssetCard";
import { RingConnection } from "../components/RingConnection";
import {
  backendClient as defaultBackendClient,
  type BackendClient,
} from "../lib/backend-client";
import {
  ringClient as defaultRingClient,
  type RingClient,
} from "../lib/ring-client";
import type { FlashResponse, RingEvent } from "../lib/types";
import { useDemo } from "../state/demo-store";

type FlashBackendClient = Pick<BackendClient, "flash">;
type FlashRingClient = Pick<
  RingClient,
  "scan" | "getConnection" | "connect" | "disconnect"
>;

type FlashPhase =
  | "disconnected"
  | "ready"
  | "listening"
  | "transcribing"
  | "processing"
  | "revealed";

type FlashState = {
  phase: FlashPhase;
  transcript: string;
  result: FlashResponse | null;
  error: string | null;
};

type FlashAction =
  | { type: "connection"; connected: boolean }
  | { type: "recording-started" }
  | { type: "recording-stopped" }
  | {
      type: "activity-snapshot";
      recording: boolean;
      asrProcessing: boolean;
      connected: boolean;
    }
  | { type: "processing"; transcript: string }
  | { type: "revealed"; result: FlashResponse }
  | { type: "failed"; message: string }
  | { type: "reset"; connected: boolean };

function reducer(state: FlashState, action: FlashAction): FlashState {
  switch (action.type) {
    case "connection":
      if (!action.connected) return { ...state, phase: "disconnected" };
      return state.phase === "disconnected" ? { ...state, phase: "ready" } : state;
    case "recording-started":
      return { phase: "listening", transcript: "", result: null, error: null };
    case "recording-stopped":
      return { ...state, phase: "transcribing", error: null };
    case "activity-snapshot":
      if (action.recording) {
        return {
          phase: "listening",
          transcript: "",
          result: null,
          error: null,
        };
      }
      if (action.asrProcessing) {
        return { ...state, phase: "transcribing", error: null };
      }
      if (state.phase === "listening" || state.phase === "transcribing") {
        return {
          ...state,
          phase: action.connected ? "ready" : "disconnected",
          error: null,
        };
      }
      return state;
    case "processing":
      return {
        phase: "processing",
        transcript: action.transcript,
        result: null,
        error: null,
      };
    case "revealed":
      return { ...state, phase: "revealed", result: action.result, error: null };
    case "failed":
      return { ...state, phase: "revealed", result: null, error: action.message };
    case "reset":
      return {
        phase: action.connected ? "ready" : "disconnected",
        transcript: "",
        result: null,
        error: null,
      };
  }
}

function eventValue(data: Record<string, unknown>, camel: string, snake: string) {
  return data[camel] ?? data[snake];
}

function eventMatches(
  event: RingEvent,
  sessionId: string,
  generation: number,
) {
  return (
    event.data.mode === "flash" &&
    eventValue(event.data, "sessionId", "session_id") === sessionId &&
    event.data.generation === generation
  );
}

function responseCards(result: FlashResponse | null) {
  if (!result) {
    return {
      cards: [] as Array<Record<string, unknown>>,
      fallback: false,
    };
  }
  if (result.cards?.length) return { cards: result.cards, fallback: false };
  if (result.derived_assets?.length) {
    return {
      cards: result.derived_assets.map((asset) => {
        const card = asset.card;
        return typeof card === "object" && card !== null && !Array.isArray(card)
          ? (card as Record<string, unknown>)
          : asset;
      }),
      fallback: false,
    };
  }
  const fallbackText = result.summary?.trim() || result.reply?.trim();
  return fallbackText
    ? { cards: [{ card_type: "note", content: fallbackText }], fallback: true }
    : { cards: [], fallback: false };
}

const PHASE_LABELS: Record<FlashPhase, string> = {
  disconnected: "Ring disconnected",
  ready: "Ready",
  listening: "Recording",
  transcribing: "Transcribing",
  processing: "Creating in UReka",
  revealed: "Captured",
};

export function FlashPage({
  backendClient = defaultBackendClient,
  ringClient = defaultRingClient,
}: {
  backendClient?: FlashBackendClient;
  ringClient?: FlashRingClient;
}) {
  const demo = useDemo();
  const [state, dispatch] = useReducer(reducer, {
    phase: demo.connection.connected ? "ready" : "disconnected",
    transcript: "",
    result: null,
    error: null,
  });
  const seenEvents = useRef<WeakSet<RingEvent> | null>(null);
  if (!seenEvents.current) seenEvents.current = new WeakSet(demo.events);
  const acceptedTranscripts = useRef(new Set<string>());
  const recordingCycle = useRef(0);
  const requestSerial = useRef(0);
  const active = useRef(true);

  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      requestSerial.current += 1;
    };
  }, []);

  useEffect(() => {
    void demo.setMode("flash").catch(() => undefined);
  }, [demo.setMode]);

  useEffect(() => {
    dispatch({ type: "connection", connected: demo.connection.connected });
  }, [demo.connection.connected]);

  useEffect(() => {
    if (demo.activityRevision === 0 || demo.mode !== "flash") return;
    if (demo.recording) {
      requestSerial.current += 1;
      recordingCycle.current += 1;
    }
    dispatch({
      type: "activity-snapshot",
      recording: demo.recording,
      asrProcessing: demo.asrProcessing,
      connected: demo.connection.connected,
    });
  }, [
    demo.activityRevision,
    demo.asrProcessing,
    demo.connection.connected,
    demo.mode,
    demo.recording,
  ]);

  useEffect(() => {
    requestSerial.current += 1;
    recordingCycle.current = 0;
    acceptedTranscripts.current.clear();
    dispatch({ type: "reset", connected: demo.connection.connected });
  }, [demo.experienceResetKey]);

  const submitTranscript = useCallback(
    async (transcript: string) => {
      const request = ++requestSerial.current;
      dispatch({ type: "processing", transcript });
      demo.beginFlashProcessing();
      try {
        const result = await backendClient.flash(transcript);
        if (!result.ok) throw new Error("UReka could not process this recording");
        if (active.current && request === requestSerial.current) {
          dispatch({ type: "revealed", result });
        }
      } catch (error) {
        if (!active.current || request !== requestSerial.current) return;
        dispatch({
          type: "failed",
          message: error instanceof Error ? error.message : "Flash request failed",
        });
      } finally {
        demo.endFlashProcessing();
      }
    },
    [backendClient, demo.beginFlashProcessing, demo.endFlashProcessing],
  );

  useEffect(() => {
    for (const event of demo.events) {
      if (seenEvents.current?.has(event)) continue;
      seenEvents.current?.add(event);
      if (!eventMatches(event, demo.sessionId, demo.generation)) continue;

      if (event.event === "recording.started") {
        requestSerial.current += 1;
        recordingCycle.current += 1;
        dispatch({ type: "recording-started" });
      } else if (
        event.event === "recording.stopped" ||
        event.event === "asr.started"
      ) {
        dispatch({ type: "recording-stopped" });
      } else if (event.event === "transcript.ready") {
        const transcript =
          typeof event.data.text === "string" ? event.data.text.trim() : "";
        if (!transcript) continue;
        const dedupeKey = `${recordingCycle.current}:${demo.sessionId}:${demo.generation}:${transcript}`;
        if (acceptedTranscripts.current.has(dedupeKey)) continue;
        acceptedTranscripts.current.add(dedupeKey);
        void submitTranscript(transcript);
      }
    }
  }, [demo.events, demo.generation, demo.sessionId, submitTranscript]);

  const displayed = useMemo(() => responseCards(state.result), [state.result]);
  const summary = state.result?.summary?.trim();
  const reply = state.result?.reply?.trim();

  return (
    <main className={`flash-page flash-phase-${state.phase}`}>
      <nav className="demo-nav" aria-label="Demo modes">
        <Link to="/">Home</Link>
        <Link aria-current="page" to="/flash">Flash</Link>
        <Link to="/vibe">Vibe</Link>
      </nav>

      <header className="flash-header">
        <div>
          <p className="eyebrow">EUREKA RING · FLASH</p>
          <h1 aria-label="Flash Mode">Say it. Keep it.</h1>
        </div>
        <div className="flash-status" aria-live="polite">
          <span className="flash-status-dot" aria-hidden="true" />
          {state.error ? "Ready to retry" : PHASE_LABELS[state.phase]}
        </div>
      </header>

      <RingConnection ringClient={ringClient} />

      <section className="flash-canvas" aria-live="polite">
        <div className="flash-signal" aria-hidden="true">
          <span />
          <span />
          <span />
          <span />
        </div>

        {state.transcript ? (
          <blockquote className="flash-transcript">{state.transcript}</blockquote>
        ) : (
          <p className="flash-hint">Your next thought can start here.</p>
        )}

        {state.error ? (
          <div className="flash-request-error" role="alert">
            <p>{state.error}</p>
            <button
              className="flash-retry"
              onClick={() => void submitTranscript(state.transcript)}
              type="button"
            >
              Retry Flash
            </button>
          </div>
        ) : null}

        {state.result ? (
          <div className="flash-result">
            {!displayed.fallback && summary ? (
              <p className="flash-summary">{summary}</p>
            ) : null}
            {reply && reply !== summary && (!displayed.fallback || summary) ? (
              <p className="flash-reply">{reply}</p>
            ) : null}
            <div className="asset-card-list">
              {displayed.cards.map((card, index) => (
                <AssetCard
                  card={card}
                  index={index}
                  key={`${String(card.asset_id ?? card.event_id ?? card.title ?? card.content ?? "card")}-${index}`}
                />
              ))}
            </div>
          </div>
        ) : null}
      </section>
    </main>
  );
}
