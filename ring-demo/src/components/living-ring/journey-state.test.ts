import { describe, expect, it } from "vitest";

import {
  resolveRingJourney,
  resolveRingPosterStyle,
} from "./journey-state";

describe("resolveRingJourney", () => {
  it("moves continuously from the hero anchor into the connect anchor", () => {
    const hero = resolveRingJourney(0);
    const beforeConnect = resolveRingJourney(0.549);
    const connect = resolveRingJourney(0.55);

    expect(hero.position[0]).toBeGreaterThan(1);
    expect(hero.rotation[0]).toBeGreaterThan(-0.72);
    expect(hero.rotation[0]).toBeLessThan(-0.58);
    expect(Math.abs(hero.rotation[1])).toBeLessThan(0.2);
    expect(hero.scale).toBeCloseTo(0.88);
    expect(Math.abs(connect.position[0] - beforeConnect.position[0])).toBeLessThan(
      0.02,
    );
    expect(connect.scale).toBeLessThan(hero.scale);
  });

  it("holds the connect position while the material keeps changing", () => {
    const arrival = resolveRingJourney(0.58);
    const departure = resolveRingJourney(0.72);

    expect(departure.position).toEqual(arrival.position);
    expect(arrival.silverMix).toBeGreaterThan(0.9);
    expect(departure.silverMix).toBeLessThan(arrival.silverMix);
  });

  it("returns to graphite and settles on the mode split", () => {
    const mode = resolveRingJourney(1);

    expect(mode.position[0]).toBeCloseTo(0);
    expect(mode.position[1]).toBeCloseTo(-0.42);
    expect(mode.scale).toBeCloseTo(0.28);
    expect(mode.silverMix).toBe(0);
    expect(mode.modeMix).toBe(1);
    expect(mode.opacity).toBe(1);
  });

  it("moves from the runway toward the Flash photo target", () => {
    const neutral = resolveRingJourney(1, false, null, false);
    const flash = resolveRingJourney(1, false, "flash", false);

    expect(flash.position[0]).toBeLessThan(neutral.position[0]);
    expect(flash.scale).toBeLessThan(neutral.scale);
    expect(flash.opacity).toBe(0);
  });

  it("moves toward the opposite target for Vibe", () => {
    const neutral = resolveRingJourney(1, false, null, false);
    const vibe = resolveRingJourney(1, false, "vibe", false);

    expect(vibe.position[0]).toBeGreaterThan(neutral.position[0]);
    expect(vibe.opacity).toBe(0);
  });

  it("keeps the live Ring opaque until the final handoff segment", () => {
    const beforeFade = resolveRingJourney(1, false, "flash", false, 0.84);
    const duringFade = resolveRingJourney(1, false, "flash", false, 0.92);

    expect(beforeFade.opacity).toBe(1);
    expect(duringFade.opacity).toBeGreaterThan(0);
    expect(duringFade.opacity).toBeLessThan(1);
  });

  it("keeps reduced-motion focus centered and opaque", () => {
    const neutral = resolveRingJourney(1);
    const pose = resolveRingJourney(1, false, "vibe", true);

    expect(pose.position).toEqual(neutral.position);
    expect(pose.opacity).toBe(1);
  });

  it("clamps progress without producing invalid material values", () => {
    expect(resolveRingJourney(-2)).toEqual(resolveRingJourney(0));
    expect(resolveRingJourney(4)).toEqual(resolveRingJourney(1));
  });

  it("keeps a compact viewport in a visible mobile hero anchor", () => {
    const compact = resolveRingJourney(0.8, true);

    expect(compact.position[0]).toBeLessThan(0.4);
    expect(compact.position[1]).toBeLessThan(-0.3);
    expect(compact.scale).toBeLessThan(0.75);
    expect(compact.silverMix).toBe(0);
    expect(compact.modeMix).toBe(0);
  });
});

describe("resolveRingPosterStyle", () => {
  it("maps the realtime journey into a viewport-relative poster transform", () => {
    const hero = resolveRingPosterStyle(resolveRingJourney(0), 1920, 1080);
    const mode = resolveRingPosterStyle(resolveRingJourney(1), 1920, 1080);

    expect(hero.translateX).toBeGreaterThan(480);
    expect(hero.scale).toBeCloseTo(1);
    expect(mode.translateX).toBe(0);
    expect(mode.translateY).toBeGreaterThan(160);
    expect(mode.scale).toBeCloseTo(0.28 / 0.88);
  });

  it("carries the handoff fade into the poster fallback", () => {
    const handoff = resolveRingPosterStyle(
      resolveRingJourney(1, false, "flash", false, 0.94),
      1440,
      900,
    );

    expect(handoff.translateX).toBeLessThan(0);
    expect(handoff.scale).toBeLessThan(0.28 / 0.88);
    expect(handoff.opacity).toBeGreaterThan(0);
    expect(handoff.opacity).toBeLessThan(1);
  });
});
