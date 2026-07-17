import { describe, expect, it } from "vitest";

import {
  resolveConnectionTreatment,
  resolveJourneyMaterial,
  resolveModeLights,
  resolveRingMaterial,
} from "./product-treatment";

describe("product photography treatment", () => {
  it("keeps the inner liner dark and softer than the exterior metal", () => {
    expect(resolveRingMaterial("材质.001")).toEqual({
      color: "#08090a",
      envMapIntensity: 0.35,
      metalness: 0.18,
      roughness: 0.48,
    });
    expect(resolveRingMaterial("材质.002")).toEqual({
      color: "#a5aaaf",
      envMapIntensity: 1.35,
      metalness: 0.88,
      roughness: 0.3,
    });
    expect(resolveRingMaterial("材质.004")).toEqual(
      resolveRingMaterial("材质.002"),
    );
    expect(resolveRingMaterial("材质.003")).toBeNull();
  });

  it("moves scan feedback outside and keeps connected reflection restrained", () => {
    expect(resolveConnectionTreatment("scanning", false)).toEqual({
      exteriorSweep: 1,
      contactReflection: 0,
    });
    expect(resolveConnectionTreatment("connected", false)).toEqual({
      exteriorSweep: 0,
      contactReflection: 0.16,
    });
    expect(resolveConnectionTreatment("connecting", false)).toEqual({
      exteriorSweep: 0,
      contactReflection: 0.08,
    });
    expect(resolveConnectionTreatment("scanning", true).exteriorSweep).toBe(0);
  });

  it("interpolates a titanium finish from graphite to silver", () => {
    expect(resolveJourneyMaterial(0)).toEqual({
      color: "#181b1e",
      envMapIntensity: 1.65,
      metalness: 0.82,
      roughness: 0.24,
    });
    expect(resolveJourneyMaterial(1)).toEqual({
      color: "#b5bbc1",
      envMapIntensity: 2.1,
      metalness: 0.92,
      roughness: 0.22,
    });
    expect(resolveJourneyMaterial(0.5).color).not.toBe("#151719");
  });

  it("accepts a landing intelligence-state material directly", () => {
    expect(resolveJourneyMaterial("#ef6a45", 0.27, 0.76, 1.9)).toEqual({
      color: "#ef6a45",
      roughness: 0.27,
      metalness: 0.76,
      envMapIntensity: 1.9,
    });
  });

  it("selects only the side light belonging to the focused mode", () => {
    expect(resolveModeLights("flash")).toEqual({ left: 1, right: 0 });
    expect(resolveModeLights("vibe")).toEqual({ left: 0, right: 1 });
    expect(resolveModeLights(null)).toEqual({ left: 0, right: 0 });
  });
});
