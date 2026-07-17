import { describe, expect, it } from "vitest";

import {
  PRODUCT_CAMERA,
  PRODUCT_GEOMETRY,
  PRODUCT_LIGHTING,
  PRODUCT_RENDERING,
} from "./scene-config";

describe("PRODUCT_CAMERA", () => {
  it("uses an orthographic product view so the band keeps an even silhouette", () => {
    expect(PRODUCT_CAMERA.projection).toBe("orthographic");
    expect(PRODUCT_CAMERA.zoom).toBeGreaterThan(240);
    expect(PRODUCT_CAMERA.position[2]).toBeGreaterThan(4);
  });

  it("uses restrained fill and directional contrast for recessed hardware", () => {
    expect(PRODUCT_LIGHTING.ambient).toBeLessThan(0.4);
    expect(PRODUCT_LIGHTING.hemisphere).toBeLessThan(0.5);
    expect(PRODUCT_LIGHTING.frontFill).toBeLessThan(1);
    expect(PRODUCT_LIGHTING.key).toBeGreaterThan(
      PRODUCT_LIGHTING.frontFill * 2,
    );
    expect(PRODUCT_LIGHTING.rim).toBeGreaterThan(
      PRODUCT_LIGHTING.frontFill,
    );
  });

  it("uses the complete ring-only source model without reconstructed geometry", () => {
    expect(PRODUCT_GEOMETRY.source).toBe("/ring/ring-capacitive-7-17.glb");
    expect(PRODUCT_GEOMETRY.touchSurfaceMaterial).toBe("材质.005");
    expect(PRODUCT_GEOMETRY.removeOnly).toEqual(["hand"]);
    expect(PRODUCT_GEOMETRY.proceduralShell).toBe(false);
    expect(PRODUCT_GEOMETRY.proceduralCircuit).toBe(false);
    expect(PRODUCT_GEOMETRY.refineSourceSurface).toBe(false);
    expect(PRODUCT_GEOMETRY.conformCircuitSurface).toBe(true);
  });

  it("caps pixel density for a smooth full-page scroll experience", () => {
    expect(PRODUCT_RENDERING.dpr[0]).toBe(1);
    expect(PRODUCT_RENDERING.dpr[1]).toBeLessThanOrEqual(1.5);
  });
});
