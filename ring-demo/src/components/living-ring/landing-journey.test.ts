import { describe, expect, it } from "vitest";

import {
  LANDING_RING_STOPS,
  mapLandingScrollProgress,
  resolveSenseEffectChapter,
  resolveLandingRingFrame,
} from "./landing-journey";

const anchorIds = [
  "hero",
  "modes",
  "mode-bridge",
  "flash-intro",
  "flash-scene",
  "vibe-intro",
  "vibe-scene",
  "vibe-exit",
  "speak",
  "touch",
  "feel",
  "system-start",
  "system-end",
  "community",
] as const;

describe("mapLandingScrollProgress", () => {
  it("maps every narrative anchor onto its matching ring stop", () => {
    const anchors = anchorIds.map((id, index) => ({
      id,
      pageProgress: index / (anchorIds.length - 1),
    }));

    for (const anchor of anchors) {
      const stop = LANDING_RING_STOPS.find(({ id }) => id === anchor.id)!;
      expect(mapLandingScrollProgress(anchor.pageProgress, anchors)).toBeCloseTo(
        stop.progress,
      );
    }
  });
});

describe("resolveSenseEffectChapter", () => {
  it("waits until the speak anchor is reached before revealing voice cards", () => {
    expect(resolveSenseEffectChapter(0.66)).toBe("");
    expect(resolveSenseEffectChapter(0.68)).toBe("speak");
  });

  it("hands each effect off at its own anchor and clears before the system", () => {
    expect(resolveSenseEffectChapter(0.76)).toBe("touch");
    expect(resolveSenseEffectChapter(0.84)).toBe("feel");
    expect(resolveSenseEffectChapter(0.9)).toBe("");
  });
});

describe("resolveLandingRingFrame", () => {
  it("resolves every narrative stop in order", () => {
    expect(LANDING_RING_STOPS.map(({ id }) => id)).toEqual(anchorIds);
    expect(
      LANDING_RING_STOPS.map((stop) =>
        resolveLandingRingFrame(stop.progress).chapter,
      ),
    ).toEqual(anchorIds);
  });

  it("moves into each scenario image by shrinking and fading away", () => {
    const flashScene = LANDING_RING_STOPS.find(
      ({ id }) => id === "flash-scene",
    )!;
    const vibeScene = LANDING_RING_STOPS.find(
      ({ id }) => id === "vibe-scene",
    )!;

    expect(flashScene.scale).toBeLessThanOrEqual(0.12);
    expect(vibeScene.scale).toBeLessThanOrEqual(0.12);
    expect(flashScene.opacity).toBe(0);
    expect(vibeScene.opacity).toBe(0);
  });

  it("reappears while leaving Vibe so it can enter the interaction chapter", () => {
    const vibeScene = LANDING_RING_STOPS.find(
      ({ id }) => id === "vibe-scene",
    )!;
    const vibeExit = LANDING_RING_STOPS.find(
      ({ id }) => id === "vibe-exit",
    )!;

    expect(vibeExit.opacity).toBe(1);
    expect(vibeExit.scale).toBeGreaterThanOrEqual(0.18);
    const handoff = resolveLandingRingFrame(
      (vibeScene.progress + vibeExit.progress) / 2,
    );
    expect(handoff.opacity).toBeGreaterThan(0);
    expect(handoff.opacity).toBeLessThan(1);
  });

  it("follows the centered-to-mirrored Z route through both modes", () => {
    const stop = (id: (typeof anchorIds)[number]) =>
      LANDING_RING_STOPS.find((candidate) => candidate.id === id)!;

    expect(stop("modes").position[0]).toBe(0);
    expect(stop("mode-bridge").position[0]).toBe(0);
    expect(stop("mode-bridge").scale).toBeLessThanOrEqual(0.2);
    expect(stop("flash-intro").position[0]).toBeGreaterThan(1);
    expect(stop("flash-intro").scale).toBeGreaterThanOrEqual(0.6);
    expect(stop("flash-scene").position[0]).toBeLessThan(-0.5);
    expect(stop("vibe-intro").position[0]).toBeLessThan(-1);
    expect(stop("vibe-intro").scale).toBeGreaterThanOrEqual(0.6);
    expect(stop("vibe-scene").position[0]).toBeGreaterThan(0.5);
  });

  it("drops down the system rail after the three interaction scenes", () => {
    const systemStart = LANDING_RING_STOPS.find(
      ({ id }) => id === "system-start",
    )!;
    const systemEnd = LANDING_RING_STOPS.find(
      ({ id }) => id === "system-end",
    )!;

    expect(systemStart.position[0]).toBeCloseTo(systemEnd.position[0]);
    expect(Math.abs(systemStart.position[0])).toBeLessThan(0.3);
    expect(systemStart.position[1]).toBeGreaterThan(systemEnd.position[1]);
    expect(systemStart.scale).toBeLessThanOrEqual(0.32);
    expect(systemEnd.scale).toBeLessThanOrEqual(0.32);
    expect(systemStart.progress).toBeGreaterThan(
      LANDING_RING_STOPS.find(({ id }) => id === "feel")!.progress,
    );
    expect(systemEnd.progress - systemStart.progress).toBeGreaterThanOrEqual(
      0.09,
    );
  });

  it("lands between the community copy and QR code", () => {
    const community = LANDING_RING_STOPS.find(
      ({ id }) => id === "community",
    )!;

    expect(community.position[0]).toBeGreaterThan(0.35);
    expect(community.position[0]).toBeLessThan(0.8);
    expect(Math.abs(community.position[1])).toBeLessThan(0.16);
  });

  it("coin-flips through the sense scenes and makes room for haptics on the right", () => {
    const speak = LANDING_RING_STOPS.find(({ id }) => id === "speak")!;
    const touch = LANDING_RING_STOPS.find(({ id }) => id === "touch")!;
    const feel = LANDING_RING_STOPS.find(({ id }) => id === "feel")!;

    expect(speak.position[0]).toBeGreaterThan(0.9);
    expect(touch.position[0]).toBeGreaterThan(0.9);
    expect(feel.position[0]).toBeGreaterThan(0.35);
    expect(feel.position[0]).toBeLessThan(0.8);
    expect(touch.rotation[1] - speak.rotation[1]).toBeCloseTo(Math.PI, 1);
    expect(feel.rotation[1] - touch.rotation[1]).toBeCloseTo(Math.PI, 1);
  });

  it("interpolates opacity and color continuously between anchors", () => {
    const flash = LANDING_RING_STOPS.find(
      ({ id }) => id === "flash-intro",
    )!;
    const scene = LANDING_RING_STOPS.find(
      ({ id }) => id === "flash-scene",
    )!;
    const middle = resolveLandingRingFrame(
      (flash.progress + scene.progress) / 2,
    );

    expect(middle.color).not.toBe(flash.color);
    expect(middle.color).not.toBe(scene.color);
    expect(middle.opacity).toBeGreaterThan(0);
    expect(middle.opacity).toBeLessThan(1);
    expect(middle.segmentProgress).toBeCloseTo(0.5);
  });

  it("removes spin, pulse and hop when reduced motion is requested", () => {
    const frame = resolveLandingRingFrame(0.82, false, true);

    expect(frame.spin).toBe(0);
    expect(frame.pulse).toBe(0);
    expect(frame.hop).toBe(0);
  });

  it("keeps compact layouts centered and unobtrusive", () => {
    for (const stop of LANDING_RING_STOPS) {
      const frame = resolveLandingRingFrame(stop.progress, true);
      expect(Math.abs(frame.position[0])).toBeLessThanOrEqual(0.32);
      expect(frame.scale).toBeLessThanOrEqual(0.48);
    }

    expect(resolveLandingRingFrame(0, true).position[1]).toBeLessThan(-0.45);
    expect(resolveLandingRingFrame(1, true).position[1]).toBeGreaterThan(0.3);
    expect(
      resolveLandingRingFrame(
        LANDING_RING_STOPS.find(({ id }) => id === "system-start")!.progress,
        true,
      ).position[1],
    ).toBeGreaterThan(1);
    expect(
      resolveLandingRingFrame(
        LANDING_RING_STOPS.find(({ id }) => id === "system-end")!.progress,
        true,
      ).position[1],
    ).toBeLessThan(-1);
  });

  it("clamps progress before resolving a segment", () => {
    expect(resolveLandingRingFrame(-1)).toEqual(resolveLandingRingFrame(0));
    expect(resolveLandingRingFrame(2)).toEqual(resolveLandingRingFrame(1));
  });
});
