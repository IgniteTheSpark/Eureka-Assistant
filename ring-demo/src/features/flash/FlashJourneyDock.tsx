import { Dither } from "../../components/Dither";

export type FlashJourneyPhase =
  | "disconnected"
  | "ready"
  | "listening"
  | "transcribing"
  | "analyzing"
  | "created"
  | "settled"
  | "failed";

interface FlashJourneyDockProps {
  phase: FlashJourneyPhase;
  transcript: string;
  createdCount: number;
  error: string | null;
  onDismiss(): void;
  onRetry(): void;
}

type ActivePhase = Extract<
  FlashJourneyPhase,
  "listening" | "transcribing" | "analyzing" | "created"
>;

const PHASES: Record<
  ActivePhase,
  {
    title: string;
    support: string;
    step: string;
    palette: [number, number, number];
    waveSpeed: number;
  }
> = {
  listening: {
    title: "Capturing",
    support: "Listening through Eureka Ring",
    step: "01 / 04",
    palette: [0.32, 0.57, 1],
    waveSpeed: 0.05,
  },
  transcribing: {
    title: "Transcribing",
    support: "Speech becoming text",
    step: "02 / 04",
    palette: [0.67, 0.47, 0.9],
    waveSpeed: 0.015,
  },
  analyzing: {
    title: "Analyzing",
    support: "Finding useful assets",
    step: "03 / 04",
    palette: [0.18, 0.76, 0.73],
    waveSpeed: 0.035,
  },
  created: {
    title: "Generated",
    support: "",
    step: "04 / 04",
    palette: [0.28, 0.73, 0.48],
    waveSpeed: 0.012,
  },
};

function cardCountCopy(count: number) {
  return `${count} ${count === 1 ? "card" : "cards"} added`;
}

export function FlashJourneyDock({
  phase,
  transcript,
  createdCount,
  error,
  onDismiss,
  onRetry,
}: FlashJourneyDockProps) {
  const activePhase = phase in PHASES ? (phase as ActivePhase) : null;
  if (!activePhase && phase !== "failed") return null;

  const config = activePhase ? PHASES[activePhase] : null;
  const reduceMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;
  const transcriptCopy = transcript || "Transcript will appear here";

  return (
    <aside
      className={`flash-journey-dock is-${phase}`}
      aria-live="polite"
      aria-label="Flash capture progress"
      data-testid={phase === "listening" ? "flash-capture-effect" : undefined}
    >
      {config ? (
        <div className="flash-journey-dither" aria-hidden="true">
          <Dither
            colorNum={4}
            disableAnimation={reduceMotion}
            enableMouseInteraction={!reduceMotion}
            mouseRadius={0.3}
            waveAmplitude={0.3}
            waveColor={config.palette}
            waveFrequency={3}
            waveSpeed={config.waveSpeed}
          />
        </div>
      ) : null}

      <p
        className={`flash-journey-transcript ${transcript ? "" : "is-placeholder"}`.trim()}
        title={transcript || undefined}
      >
        {transcriptCopy}
      </p>

      <div className="flash-journey-center">
        {config ? (
          <>
            <h2 className="flash-journey-title">{config.title}</h2>
            <span>
              {phase === "created" ? cardCountCopy(createdCount) : config.support}
            </span>
          </>
        ) : (
          <>
            <h2 className="flash-journey-title">Ready to retry</h2>
            <span role="alert">{error}</span>
          </>
        )}
      </div>

      <div className="flash-journey-footer">
        {phase === "created" ? (
          <button className="flash-journey-close" onClick={onDismiss} type="button">
            Close
          </button>
        ) : (
          <span />
        )}
        {phase === "failed" ? (
          <button onClick={onRetry} type="button">
            Retry Flash
          </button>
        ) : (
          <span>{config?.step}</span>
        )}
      </div>
    </aside>
  );
}
