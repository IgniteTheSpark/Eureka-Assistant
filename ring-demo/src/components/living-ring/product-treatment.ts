import type { LivingRingMode } from "./motion-state";

export interface RingMaterialTreatment {
  color: string;
  envMapIntensity: number;
  metalness: number;
  roughness: number;
}

function clamp01(value: number) {
  return Math.min(1, Math.max(0, value));
}

function mix(from: number, to: number, progress: number) {
  return from + (to - from) * progress;
}

function mixHex(from: string, to: string, rawProgress: number) {
  const progress = clamp01(rawProgress);
  const fromValue = Number.parseInt(from.slice(1), 16);
  const toValue = Number.parseInt(to.slice(1), 16);
  const channels = [16, 8, 0].map((shift) =>
    Math.round(
      mix((fromValue >> shift) & 0xff, (toValue >> shift) & 0xff, progress),
    ),
  );
  return `#${channels.map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
}

export function resolveJourneyMaterial(rawSilverMix: number): RingMaterialTreatment;
export function resolveJourneyMaterial(
  color: string,
  roughness: number,
  metalness: number,
  envMapIntensity: number,
): RingMaterialTreatment;
export function resolveJourneyMaterial(
  input: number | string,
  roughness?: number,
  metalness?: number,
  envMapIntensity?: number,
): RingMaterialTreatment {
  if (typeof input === "string") {
    return {
      color: input,
      roughness: roughness ?? 0.24,
      metalness: metalness ?? 0.82,
      envMapIntensity: envMapIntensity ?? 1.65,
    };
  }

  const rawSilverMix = input;
  const silverMix = clamp01(rawSilverMix);
  return {
    color: mixHex("#181b1e", "#b5bbc1", silverMix),
    envMapIntensity: mix(1.65, 2.1, silverMix),
    metalness: mix(0.82, 0.92, silverMix),
    roughness: mix(0.24, 0.22, silverMix),
  };
}

export function resolveModeLights(mode: LivingRingMode) {
  return {
    left: mode === "flash" ? 1 : 0,
    right: mode === "vibe" ? 1 : 0,
  };
}

export interface ConnectionTreatment {
  exteriorSweep: number;
  contactReflection: number;
}

export function resolveRingMaterial(
  materialName: string,
): RingMaterialTreatment | null {
  if (materialName === "材质.001") {
    return {
      color: "#08090a",
      envMapIntensity: 0.35,
      metalness: 0.18,
      roughness: 0.48,
    };
  }
  if (materialName === "材质.002" || materialName === "材质.004") {
    return {
      color: "#a5aaaf",
      envMapIntensity: 1.35,
      metalness: 0.88,
      roughness: 0.3,
    };
  }
  return null;
}

export function resolveConnectionTreatment(
  connectionStatus: string,
  reducedMotion: boolean,
): ConnectionTreatment {
  return {
    exteriorSweep:
      !reducedMotion && connectionStatus === "scanning" ? 1 : 0,
    contactReflection:
      connectionStatus === "connected"
        ? 0.16
        : connectionStatus === "connecting"
          ? 0.08
          : 0,
  };
}
