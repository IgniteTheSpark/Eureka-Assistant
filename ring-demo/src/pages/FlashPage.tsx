import { useCallback, useEffect, useReducer, useRef } from "react";
import { Link } from "react-router-dom";

import { RingConnection } from "../components/RingConnection";
import { FlashAssetFolder } from "../features/flash/FlashAssetFolder";
import {
  createFlashAssetBatch,
  type FlashAssetBatch,
} from "../features/flash/flash-assets";
import {
  FlashJourneyDock,
  type FlashJourneyPhase,
} from "../features/flash/FlashJourneyDock";
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

type FlashState = {
  phase: FlashJourneyPhase;
  transcript: string;
  batches: FlashAssetBatch[];
  createdCount: number;
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
  | { type: "transcript-ready"; transcript: string }
  | { type: "analyzing" }
  | { type: "created"; batch: FlashAssetBatch; count: number }
  | { type: "settled" }
  | { type: "failed"; message: string }
  | { type: "reset"; connected: boolean };

function reducer(state: FlashState, action: FlashAction): FlashState {
  switch (action.type) {
    case "connection":
      if (!action.connected) return { ...state, phase: "disconnected" };
      return state.phase === "disconnected" ? { ...state, phase: "ready" } : state;
    case "recording-started":
      return {
        ...state,
        phase: "listening",
        transcript: "",
        createdCount: 0,
        error: null,
      };
    case "recording-stopped":
      return { ...state, phase: "transcribing", error: null };
    case "activity-snapshot":
      if (action.recording) {
        return {
          ...state,
          phase: "listening",
          transcript: "",
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
    case "transcript-ready":
      return {
        ...state,
        phase: "transcribing",
        transcript: action.transcript,
        createdCount: 0,
        error: null,
      };
    case "analyzing":
      return {
        ...state,
        phase: "analyzing",
        error: null,
      };
    case "created":
      return {
        ...state,
        phase: "created",
        batches: [action.batch, ...state.batches],
        createdCount: action.count,
        error: null,
      };
    case "settled":
      return { ...state, phase: "settled", error: null };
    case "failed":
      return { ...state, phase: "failed", error: action.message };
    case "reset":
      return {
        phase: action.connected ? "ready" : "disconnected",
        transcript: "",
        batches: [],
        createdCount: 0,
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

const PHASE_LABELS: Record<FlashJourneyPhase, string> = {
  disconnected: "Ring disconnected",
  ready: "Ready",
  listening: "Recording",
  transcribing: "Transcribing",
  analyzing: "Analyzing",
  created: "Generated",
  settled: "Captured",
  failed: "Ready to retry",
};

const ACKNOWLEDGEMENT_MS = 700;
const ANALYZING_MIN_MS = 250;

function delay(milliseconds: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));
}

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
    batches: [],
    createdCount: 0,
    error: null,
  });
  const seenEvents = useRef<WeakSet<RingEvent> | null>(null);
  if (!seenEvents.current) seenEvents.current = new WeakSet(demo.events);
  const acceptedTranscripts = useRef(new Set<string>());
  const recordingCycle = useRef(0);
  const requestSerial = useRef(0);
  const batchSequence = useRef(0);
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
    batchSequence.current = 0;
    acceptedTranscripts.current.clear();
    dispatch({ type: "reset", connected: demo.connection.connected });
  }, [demo.experienceResetKey]);

  const submitTranscript = useCallback(
    async (transcript: string) => {
      const request = ++requestSerial.current;
      dispatch({ type: "transcript-ready", transcript });
      demo.beginFlashProcessing();
      let outcome: Promise<
        | { result: FlashResponse; error?: never }
        | { result?: never; error: unknown }
      >;
      try {
        outcome = backendClient
          .flash(transcript)
          .then((result) => ({ result }), (error: unknown) => ({ error }));
      } catch (error) {
        outcome = Promise.resolve({ error });
      }

      try {
        await delay(ACKNOWLEDGEMENT_MS);
        if (!active.current || request !== requestSerial.current) return;
        dispatch({ type: "analyzing" });
        const analyzingStartedAt = Date.now();
        const settled = await outcome;
        if ("error" in settled) throw settled.error;
        const result = settled.result;
        if (!result.ok) throw new Error("UReka could not process this recording");
        const remainingAnalyzingTime = Math.max(
          0,
          ANALYZING_MIN_MS - (Date.now() - analyzingStartedAt),
        );
        if (remainingAnalyzingTime) await delay(remainingAnalyzingTime);
        if (active.current && request === requestSerial.current) {
          const nextBatchNumber = batchSequence.current + 1;
          const batch = createFlashAssetBatch(
            transcript,
            result,
            `flash-${nextBatchNumber}`,
            Date.now(),
          );
          if (batch.cards.length) {
            batchSequence.current = nextBatchNumber;
            dispatch({
              type: "created",
              batch,
              count: batch.cards.length,
            });
          } else {
            dispatch({ type: "settled" });
          }
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
          {PHASE_LABELS[state.phase]}
        </div>
      </header>

      <section className="flash-workspace">
        <aside className="flash-ring-panel">
          <p className="flash-panel-label">RING / CONNECTED</p>
          <img
            alt="Eureka Ring"
            className="flash-ring-product"
            src="/ring/ring-connect.png"
          />
          <RingConnection ringClient={ringClient} />
          <div className="flash-guidance">
            <span aria-hidden="true">02</span>
            <div>
              <strong>Double tap to capture a thought.</strong>
              <p>Speak naturally. Double tap again when you are done.</p>
            </div>
          </div>
        </aside>

        <FlashAssetFolder batches={state.batches} />
      </section>

      <FlashJourneyDock
        createdCount={state.createdCount}
        phase={state.phase}
        transcript={state.transcript}
        error={state.error}
        onDismiss={() => dispatch({ type: "settled" })}
        onRetry={() => void submitTranscript(state.transcript)}
      />
    </main>
  );
}
