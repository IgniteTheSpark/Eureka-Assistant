import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";

import { RingConnection } from "../components/RingConnection";
import {
  ringClient as defaultRingClient,
  type RingClient,
} from "../lib/ring-client";
import type { RingEvent } from "../lib/types";
import { useDemo } from "../state/demo-store";

type VibeRingClient = Pick<
  RingClient,
  "scan" | "getConnection" | "connect" | "disconnect"
>;

const APP_PROFILES = {
  "com.openai.codex": {
    name: "Codex",
    state: "Codex active",
    description: "Use voice, Enter, and scroll gestures in Codex.",
  },
  "com.alibaba.DingTalkMac": {
    name: "DingTalk",
    state: "DingTalk active",
    description: "Use voice and mapped gestures in DingTalk.",
  },
} as const;

type SupportedApp = keyof typeof APP_PROFILES;

const GESTURE_LABELS: Record<string, string> = {
  double: "Double tap",
  triple: "Triple tap",
  up: "Swipe up",
  down: "Swipe down",
};

function isSupportedApp(value: string | null): value is SupportedApp {
  return value !== null && value in APP_PROFILES;
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
    event.data.mode === "vibe" &&
    eventValue(event.data, "sessionId", "session_id") === sessionId &&
    event.data.generation === generation
  );
}

function gestureLabel(gesture: string) {
  const known = GESTURE_LABELS[gesture.toLowerCase()];
  if (known) return known;
  const words = gesture.replaceAll("_", " ").replaceAll("-", " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function VibePage({
  ringClient = defaultRingClient,
}: {
  ringClient?: VibeRingClient;
}) {
  const demo = useDemo();
  const [recording, setRecording] = useState(false);
  const seenEvents = useRef<WeakSet<RingEvent> | null>(null);
  if (!seenEvents.current) seenEvents.current = new WeakSet(demo.events);

  useEffect(() => {
    void demo.setMode("vibe").catch(() => undefined);
  }, [demo.setMode]);

  useEffect(() => {
    for (const event of demo.events) {
      if (seenEvents.current?.has(event)) continue;
      seenEvents.current?.add(event);
      if (!eventMatches(event, demo.sessionId, demo.generation)) continue;

      if (event.event === "recording.started") {
        setRecording(true);
      } else if (
        event.event === "recording.stopped" ||
        event.event === "asr.started"
      ) {
        setRecording(false);
      }
    }
  }, [demo.events, demo.generation, demo.sessionId]);

  const activeApp = isSupportedApp(demo.activeApp) ? demo.activeApp : null;
  const mapping = Object.entries(demo.mapping ?? {});

  return (
    <main className={`vibe-page${recording ? " vibe-is-recording" : ""}`}>
      <nav className="demo-nav" aria-label="Demo modes">
        <Link to="/">Home</Link>
        <Link to="/flash">Flash</Link>
        <Link aria-current="page" to="/vibe">Vibe</Link>
      </nav>

      <header className="vibe-header">
        <div>
          <p className="eyebrow">EUREKA RING · VIBE</p>
          <h1>Vibe Mode</h1>
        </div>
        {recording ? (
          <div className="vibe-recording" aria-live="polite">
            <span aria-hidden="true" />
            Recording
          </div>
        ) : null}
      </header>

      <RingConnection ringClient={ringClient} />

      <section className="vibe-workspace" aria-live="polite">
        <div className="vibe-app-status">
          <p className="eyebrow">CURRENT APP</p>
          {activeApp ? (
            <p className="vibe-active-state">{APP_PROFILES[activeApp].state}</p>
          ) : (
            <p className="vibe-app-prompt">
              Open Codex or DingTalk to activate Ring controls.
            </p>
          )}
        </div>

        <div className="vibe-profiles">
          {Object.entries(APP_PROFILES).map(([bundleId, profile]) => {
            const active = bundleId === activeApp;
            return (
              <article
                className={`vibe-profile${active ? " is-active" : ""}`}
                key={bundleId}
              >
                <span className="vibe-profile-dot" aria-hidden="true" />
                <div>
                  <h2>{profile.name}</h2>
                  <p>{profile.description}</p>
                </div>
              </article>
            );
          })}
        </div>

        {activeApp ? (
          <div className="vibe-mapping">
            <p className="eyebrow">ACTIVE MAPPING</p>
            {mapping.length > 0 ? (
              <dl>
                {mapping.map(([gesture, action]) => (
                  <div key={gesture}>
                    <dt>{gestureLabel(gesture)}</dt>
                    <dd>{action}</dd>
                  </div>
                ))}
              </dl>
            ) : (
              <p className="vibe-mapping-empty">No gestures mapped.</p>
            )}
          </div>
        ) : null}
      </section>
    </main>
  );
}
