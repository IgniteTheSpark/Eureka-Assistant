import { MODE_SCENES } from "../mode-scenes/mode-scene-state";
import type { LivingRingMode } from "./motion-state";

export interface RingJourneyFrame {
  effectChapter?: "" | "speak" | "touch" | "feel";
  progress: number;
  rotation: number;
}

export interface RingJourneyPose {
  progress: number;
  position: [number, number, number];
  rotation: [number, number, number];
  scale: number;
  silverMix: number;
  modeMix: number;
  opacity: number;
}

export interface RingPosterStyle {
  opacity: number;
  rotationDegrees: number;
  scale: number;
  translateX: number;
  translateY: number;
}

const HERO_POSITION: RingJourneyPose["position"] = [1.22, 0.02, 0];
const CONNECT_POSITION: RingJourneyPose["position"] = [-1.42, -0.45, 0];
const MODE_POSITION: RingJourneyPose["position"] = [0, -0.42, 0];

export function clamp01(value: number) {
  return Math.min(1, Math.max(0, value));
}

function mix(from: number, to: number, progress: number) {
  return from + (to - from) * progress;
}

function smoothstep(from: number, to: number, value: number) {
  const progress = clamp01((value - from) / (to - from));
  return progress * progress * (3 - 2 * progress);
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

export function resolveRingJourney(
  rawProgress: number,
  compactViewport = false,
  focusedMode: LivingRingMode = null,
  reducedMotion = false,
  rawHandoffProgress = focusedMode ? 1 : 0,
): RingJourneyPose {
  const progress = clamp01(rawProgress);
  const toConnect = smoothstep(0.14, 0.55, progress);
  const modeMix = smoothstep(0.76, 0.94, progress);
  const connectPosition = mixTuple(HERO_POSITION, CONNECT_POSITION, toConnect);
  const position = mixTuple(connectPosition, MODE_POSITION, modeMix);
  const connectScale = mix(0.88, 0.43, toConnect);

  const pose: RingJourneyPose = {
    progress,
    position,
    rotation: [
      mix(-0.64, -0.5, toConnect),
      mix(-0.1, -0.28, toConnect),
      mix(-0.1, -0.02, modeMix),
    ],
    scale: mix(connectScale, 0.28, modeMix),
    silverMix:
      smoothstep(0.34, 0.58, progress) *
      (1 - smoothstep(0.68, 0.88, progress)),
    modeMix,
    opacity: 1,
  };

  if (compactViewport) {
    return {
      ...pose,
      position: [0.28, -0.48, 0],
      rotation: [-0.62, -0.12, -0.06],
      scale: 0.68,
      silverMix: 0,
      modeMix: 0,
      opacity: 1,
    };
  }

  if (!focusedMode || reducedMotion || modeMix < 1) return pose;

  const handoffProgress = clamp01(rawHandoffProgress);
  const target = MODE_SCENES[focusedMode].handoff.desktop;

  return {
    ...pose,
    position: mixTuple(pose.position, target.position, handoffProgress),
    rotation: mixTuple(pose.rotation, target.rotation, handoffProgress),
    scale: mix(pose.scale, target.scale, handoffProgress),
    opacity: 1 - smoothstep(0.85, 1, handoffProgress),
  };
}

export function resolveRingPosterStyle(
  pose: Pick<RingJourneyPose, "opacity" | "position" | "rotation" | "scale">,
  viewportWidth: number,
  viewportHeight: number,
): RingPosterStyle {
  const viewportUnit = Math.min(viewportWidth, viewportHeight) * 0.38;

  return {
    opacity: pose.opacity,
    rotationDegrees: (pose.rotation[2] * 180) / Math.PI,
    scale: pose.scale / 0.88,
    translateX: pose.position[0] * viewportUnit,
    translateY: -pose.position[1] * viewportUnit,
  };
}
