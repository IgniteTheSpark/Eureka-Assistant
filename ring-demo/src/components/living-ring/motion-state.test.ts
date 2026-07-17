import { describe, expect, it } from "vitest";

import { resolveLivingRingPose } from "./motion-state";

describe("resolveLivingRingPose", () => {
  it("moves from the hero pose into the launcher's connection marker", () => {
    const hero = resolveLivingRingPose({
      connectionStatus: "disconnected",
      focusedMode: null,
      reducedMotion: false,
      travelProgress: 0,
    });
    const launcher = resolveLivingRingPose({
      connectionStatus: "disconnected",
      focusedMode: null,
      reducedMotion: false,
      travelProgress: 1,
    });

    expect(hero.position).toEqual([1.25, 0.1, 0]);
    expect(hero.rotation[1]).toBeLessThanOrEqual(-0.5);
    expect(launcher.position[0]).toBeLessThanOrEqual(-1.5);
    expect(launcher.position[1]).toBeCloseTo(-0.08);
    expect(launcher.scale).toBeLessThanOrEqual(0.46);
    expect(Math.abs(launcher.rotation[1])).toBeGreaterThanOrEqual(0.2);
  });

  it("leans toward the focused mode and changes accent", () => {
    const flash = resolveLivingRingPose({
      connectionStatus: "disconnected",
      focusedMode: "flash",
      reducedMotion: false,
      travelProgress: 1,
    });
    const vibe = resolveLivingRingPose({
      connectionStatus: "disconnected",
      focusedMode: "vibe",
      reducedMotion: false,
      travelProgress: 1,
    });

    expect(flash.rotation[1]).toBeLessThan(launcherYaw());
    expect(vibe.rotation[1]).toBeGreaterThan(launcherYaw());
    expect(Math.abs(flash.rotation[1])).toBeGreaterThanOrEqual(0.2);
    expect(Math.abs(vibe.rotation[1])).toBeGreaterThanOrEqual(0.2);
    expect(flash.accent).toBe("flash");
    expect(vibe.accent).toBe("vibe");
  });

  it("clamps travel and stabilizes animation for reduced motion", () => {
    const pose = resolveLivingRingPose({
      connectionStatus: "scanning",
      focusedMode: "flash",
      reducedMotion: true,
      travelProgress: 4,
    });

    expect(pose.travelProgress).toBe(1);
    expect(pose.idleAmplitude).toBe(0);
  });
});

function launcherYaw() {
  return resolveLivingRingPose({
    connectionStatus: "disconnected",
    focusedMode: null,
    reducedMotion: false,
    travelProgress: 1,
  }).rotation[1];
}
