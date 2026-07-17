export type LivingRingMode = "flash" | "vibe" | null;

export interface LivingRingInput {
  travelProgress: number;
  connectionStatus: string;
  focusedMode: LivingRingMode;
  reducedMotion: boolean;
}

export interface LivingRingPose {
  travelProgress: number;
  position: [number, number, number];
  rotation: [number, number, number];
  scale: number;
  idleAmplitude: number;
  accent: LivingRingMode;
}

function clamp(value: number) {
  return Math.min(1, Math.max(0, value));
}

function mix(from: number, to: number, progress: number) {
  return from + (to - from) * progress;
}

export function resolveLivingRingPose({
  connectionStatus,
  focusedMode,
  reducedMotion,
  travelProgress,
}: LivingRingInput): LivingRingPose {
  const travel = clamp(travelProgress);
  const connectionLean =
    connectionStatus === "connecting" || connectionStatus === "connected"
      ? -0.08
      : 0;
  const modeLean = focusedMode === "flash" ? -0.11 : focusedMode === "vibe" ? 0.11 : 0;

  return {
    travelProgress: travel,
    position: [mix(1.25, -1.62, travel), mix(0.1, -0.08, travel), 0],
    rotation: [
      mix(-0.22, -0.04, travel),
      mix(-0.52, -0.32, travel) + modeLean,
      mix(-0.12, 0, travel) + connectionLean,
    ],
    scale: mix(1.08, 0.44, travel),
    idleAmplitude: reducedMotion ? 0 : focusedMode ? 0.006 : 0.018,
    accent: focusedMode,
  };
}
