import { describe, expect, it } from "vitest";

import { MODE_SCENES, resolveModeSceneLayout } from "./mode-scene-state";

describe("resolveModeSceneLayout", () => {
  it("calibrates both desktop targets to the photographed speaking hand", () => {
    expect(MODE_SCENES.flash.handoff.desktop).toMatchObject({
      position: [-1.02, 0.29, 0],
      scale: 0.04,
    });
    expect(MODE_SCENES.vibe.handoff.desktop).toMatchObject({
      position: [0.5, 0.17, 0],
      scale: 0.04,
    });
  });

  it("keeps a neutral center runway", () => {
    expect(resolveModeSceneLayout(null, false, false)).toMatchObject({
      columns: [41, 18, 41],
      ringTarget: "center",
      handoffOpacity: 1,
    });
  });

  it("expands Flash and exposes its calibrated handoff", () => {
    const state = resolveModeSceneLayout("flash", false, false);

    expect(state.columns).toEqual([59, 12, 29]);
    expect(state.ringTarget).toBe("flash");
    expect(state.target).toEqual(MODE_SCENES.flash.handoff.desktop);
  });

  it("expands Vibe in the opposite direction", () => {
    const state = resolveModeSceneLayout("vibe", false, false);

    expect(state.columns).toEqual([29, 12, 59]);
    expect(state.ringTarget).toBe("vibe");
    expect(state.target).toEqual(MODE_SCENES.vibe.handoff.desktop);
  });

  it("keeps the Ring centered on compact and reduced-motion layouts", () => {
    expect(resolveModeSceneLayout("vibe", true, false).ringTarget).toBe(
      "center",
    );
    expect(resolveModeSceneLayout("vibe", false, true).ringTarget).toBe(
      "center",
    );
  });
});
