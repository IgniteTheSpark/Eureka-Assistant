import { clamp01, type RingJourneyPose } from "./journey-state";

export type LandingChapterId =
  | "hero"
  | "modes"
  | "mode-bridge"
  | "flash-intro"
  | "flash-scene"
  | "vibe-intro"
  | "vibe-scene"
  | "vibe-exit"
  | "system-start"
  | "system-end"
  | "speak"
  | "touch"
  | "feel"
  | "community";

export interface LandingRingStop {
  color: string;
  envMapIntensity: number;
  hop: number;
  id: LandingChapterId;
  metalness: number;
  opacity: number;
  position: RingJourneyPose["position"];
  progress: number;
  pulse: number;
  rotation: RingJourneyPose["rotation"];
  roughness: number;
  scale: number;
  spin: number;
}

export interface LandingRingFrame extends LandingRingStop {
  chapter: LandingChapterId;
  opacity: number;
  segmentProgress: number;
}

export interface LandingScrollAnchor {
  id: LandingChapterId;
  pageProgress: number;
}

export type SenseEffectChapter = "" | "speak" | "touch" | "feel";

export const LANDING_RING_STOPS: readonly LandingRingStop[] = [
  {
    id: "hero",
    progress: 0,
    position: [1.22, 0.02, 0],
    rotation: [-0.64, -0.1, -0.1],
    scale: 0.88,
    color: "#202327",
    roughness: 0.24,
    metalness: 0.82,
    envMapIntensity: 1.65,
    pulse: 0,
    spin: 0.08,
    hop: 0,
    opacity: 1,
  },
  {
    id: "modes",
    progress: 0.12,
    position: [0, -0.2, 0],
    rotation: [-0.5, -0.28, -0.02],
    scale: 0.32,
    color: "#31353a",
    roughness: 0.26,
    metalness: 0.8,
    envMapIntensity: 1.7,
    pulse: 0.12,
    spin: 0.12,
    hop: 0,
    opacity: 1,
  },
  {
    id: "mode-bridge",
    progress: 0.17,
    position: [0, 0, 0],
    rotation: [-0.5, -0.12, -0.02],
    scale: 0.16,
    color: "#665452",
    roughness: 0.26,
    metalness: 0.8,
    envMapIntensity: 1.72,
    pulse: 0.08,
    spin: 0.1,
    hop: 0,
    opacity: 1,
  },
  {
    id: "flash-intro",
    progress: 0.22,
    position: [1.52, 0.68, 0],
    rotation: [-0.42, 0.2, -0.08],
    scale: 0.64,
    color: "#ef6a45",
    roughness: 0.27,
    metalness: 0.76,
    envMapIntensity: 1.9,
    pulse: 0.62,
    spin: 0.24,
    hop: 0.35,
    opacity: 1,
  },
  {
    id: "flash-scene",
    progress: 0.34,
    position: [-1.02, 0.18, 0],
    rotation: [-0.62, 1.15, -0.18],
    scale: 0.015,
    color: "#d74729",
    roughness: 0.25,
    metalness: 0.8,
    envMapIntensity: 1.85,
    pulse: 0.18,
    spin: 0.18,
    hop: 0.12,
    opacity: 0,
  },
  {
    id: "vibe-intro",
    progress: 0.43,
    position: [-1.52, 0.68, 0],
    rotation: [-0.55, -0.5, 0.08],
    scale: 0.64,
    color: "#5367ff",
    roughness: 0.22,
    metalness: 0.84,
    envMapIntensity: 2.05,
    pulse: 0.52,
    spin: 0.28,
    hop: 0.28,
    opacity: 1,
  },
  {
    id: "vibe-scene",
    progress: 0.55,
    position: [1.02, 0.14, 0],
    rotation: [-0.64, -1.4, 0.16],
    scale: 0.015,
    color: "#2f45db",
    roughness: 0.22,
    metalness: 0.84,
    envMapIntensity: 1.9,
    pulse: 0.16,
    spin: 0.18,
    hop: 0.1,
    opacity: 0,
  },
  {
    id: "vibe-exit",
    progress: 0.6,
    position: [1.22, 1.04, 0],
    rotation: [-0.56, -0.72, 0.14],
    scale: 0.22,
    color: "#6e51e8",
    roughness: 0.22,
    metalness: 0.84,
    envMapIntensity: 1.9,
    pulse: 0.24,
    spin: 0.12,
    hop: 0.08,
    opacity: 1,
  },
  {
    id: "speak",
    progress: 0.68,
    position: [1.22, 0.58, 0],
    rotation: [-0.48, 0.3, 0.12],
    scale: 0.34,
    color: "#b65aff",
    roughness: 0.25,
    metalness: 0.8,
    envMapIntensity: 1.95,
    pulse: 0.4,
    spin: 0,
    hop: 0.12,
    opacity: 1,
  },
  {
    id: "touch",
    progress: 0.76,
    position: [1.22, 0.02, 0],
    rotation: [-0.48, 0.3 + Math.PI, 0.12],
    scale: 0.34,
    color: "#8c6dff",
    roughness: 0.23,
    metalness: 0.82,
    envMapIntensity: 2,
    pulse: 0.56,
    spin: 0,
    hop: 0.1,
    opacity: 1,
  },
  {
    id: "feel",
    progress: 0.84,
    position: [0.58, -0.58, 0],
    rotation: [-0.48, 0.3 + Math.PI * 2, 0.12],
    scale: 0.34,
    color: "#df5bd4",
    roughness: 0.23,
    metalness: 0.82,
    envMapIntensity: 2,
    pulse: 0.72,
    spin: 0,
    hop: 0.1,
    opacity: 1,
  },
  {
    id: "system-start",
    progress: 0.9,
    position: [0.11, 0.94, 0],
    rotation: [-0.18, 0.3 + Math.PI * 2.5, 0],
    scale: 0.22,
    color: "#39d7c1",
    roughness: 0.2,
    metalness: 0.88,
    envMapIntensity: 2.18,
    pulse: 1,
    spin: 0.1,
    hop: 0.08,
    opacity: 1,
  },
  {
    id: "system-end",
    progress: 0.995,
    position: [0.11, -0.94, 0],
    rotation: [-0.16, 0.3 + Math.PI * 3, 0],
    scale: 0.2,
    color: "#42e1c9",
    roughness: 0.2,
    metalness: 0.88,
    envMapIntensity: 2.18,
    pulse: 0.72,
    spin: 0.08,
    hop: 0,
    opacity: 1,
  },
  {
    id: "community",
    progress: 1,
    position: [0.56, 0.04, 0],
    rotation: [-0.55, 0.2, -0.06],
    scale: 0.36,
    color: "#d8e0e8",
    roughness: 0.18,
    metalness: 0.92,
    envMapIntensity: 2.2,
    pulse: 0.16,
    spin: 0.25,
    hop: 0.65,
    opacity: 1,
  },
] as const;

export function resolveSenseEffectChapter(
  progress: number,
): SenseEffectChapter {
  if (progress >= 0.84 && progress < 0.9) return "feel";
  if (progress >= 0.76 && progress < 0.84) return "touch";
  if (progress >= 0.68 && progress < 0.76) return "speak";
  return "";
}

export function mapLandingScrollProgress(
  rawPageProgress: number,
  anchors: readonly LandingScrollAnchor[],
) {
  const pageProgress = clamp01(rawPageProgress);
  if (anchors.length === 0) return pageProgress;
  const ordered = [...anchors].sort(
    (left, right) => left.pageProgress - right.pageProgress,
  );
  const stopProgress = (id: LandingChapterId) =>
    LANDING_RING_STOPS.find((stop) => stop.id === id)?.progress ?? pageProgress;

  if (pageProgress <= ordered[0].pageProgress) {
    return stopProgress(ordered[0].id);
  }

  for (let index = 0; index < ordered.length - 1; index += 1) {
    const from = ordered[index];
    const to = ordered[index + 1];
    if (pageProgress > to.pageProgress) continue;
    const duration = Math.max(0.0001, to.pageProgress - from.pageProgress);
    const localProgress = clamp01(
      (pageProgress - from.pageProgress) / duration,
    );
    return mix(
      stopProgress(from.id),
      stopProgress(to.id),
      localProgress,
    );
  }

  return stopProgress(ordered[ordered.length - 1].id);
}

function mix(from: number, to: number, progress: number) {
  return from + (to - from) * progress;
}

function smoothstep(progress: number) {
  const value = clamp01(progress);
  return value * value * (3 - 2 * value);
}

function mixTuple(
  from: RingJourneyPose["position"],
  to: RingJourneyPose["position"],
  progress: number,
): RingJourneyPose["position"] {
  return [
    mix(from[0], to[0], progress),
    mix(from[1], to[1], progress),
    mix(from[2], to[2], progress),
  ];
}

function mixHex(from: string, to: string, progress: number) {
  const fromValue = Number.parseInt(from.slice(1), 16);
  const toValue = Number.parseInt(to.slice(1), 16);
  const channels = [16, 8, 0].map((shift) =>
    Math.round(
      mix((fromValue >> shift) & 0xff, (toValue >> shift) & 0xff, progress),
    ),
  );
  return `#${channels.map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
}

function findSegment(progress: number) {
  for (let index = 0; index < LANDING_RING_STOPS.length - 1; index += 1) {
    const from = LANDING_RING_STOPS[index];
    const to = LANDING_RING_STOPS[index + 1];
    if (progress <= to.progress) return { from, to };
  }
  const last = LANDING_RING_STOPS[LANDING_RING_STOPS.length - 1];
  return { from: last, to: last };
}

export function resolveLandingRingFrame(
  rawProgress: number,
  compact = false,
  reducedMotion = false,
): LandingRingFrame {
  const progress = clamp01(rawProgress);
  const { from, to } = findSegment(progress);
  const duration = Math.max(0.0001, to.progress - from.progress);
  const rawSegmentProgress = clamp01((progress - from.progress) / duration);
  const segmentProgress = smoothstep(rawSegmentProgress);
  const chapter = rawSegmentProgress < 0.5 ? from.id : to.id;
  const interpolated: LandingRingFrame = {
    id: chapter,
    chapter,
    progress,
    segmentProgress,
    position: mixTuple(from.position, to.position, segmentProgress),
    rotation: mixTuple(from.rotation, to.rotation, segmentProgress),
    scale: mix(from.scale, to.scale, segmentProgress),
    color: mixHex(from.color, to.color, segmentProgress),
    roughness: mix(from.roughness, to.roughness, segmentProgress),
    metalness: mix(from.metalness, to.metalness, segmentProgress),
    envMapIntensity: mix(
      from.envMapIntensity,
      to.envMapIntensity,
      segmentProgress,
    ),
    pulse: reducedMotion ? 0 : mix(from.pulse, to.pulse, segmentProgress),
    spin: reducedMotion ? 0 : mix(from.spin, to.spin, segmentProgress),
    hop: reducedMotion ? 0 : mix(from.hop, to.hop, segmentProgress),
    opacity: mix(from.opacity, to.opacity, segmentProgress),
  };

  if (!compact) return interpolated;

  const compactPosition: Record<
    LandingChapterId,
    RingJourneyPose["position"]
  > = {
    hero: [0, -0.7, 0],
    modes: [0, 0.28, 0],
    "mode-bridge": [0, 0.62, 0],
    "flash-intro": [0, 1.5, 0],
    "flash-scene": [0, 1.42, 0],
    "vibe-intro": [0, 1.5, 0],
    "vibe-scene": [0, 1.42, 0],
    "vibe-exit": [0.28, 1.38, 0],
    "system-start": [0, 1.38, 0],
    "system-end": [0, -1.38, 0],
    speak: [0, 1.75, 0],
    touch: [0, 1.75, 0],
    feel: [0, 1.75, 0],
    community: [0.16, 0.48, 0],
  };

  return {
    ...interpolated,
    position: compactPosition[chapter],
    rotation: [-0.5, -0.12, -0.04],
    scale: Math.min(0.48, interpolated.scale),
    hop: 0,
    spin: reducedMotion ? 0 : interpolated.spin * 0.25,
  };
}
