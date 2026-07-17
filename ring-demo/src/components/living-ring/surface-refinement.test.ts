import { CylinderGeometry } from "three";
import { describe, expect, it } from "vitest";

import { refineProductSurface } from "./surface-refinement";

function largestSilhouetteGap(geometry: CylinderGeometry) {
  const position = geometry.getAttribute("position");
  let largestRadius = 0;
  for (let index = 0; index < position.count; index += 1) {
    largestRadius = Math.max(
      largestRadius,
      Math.hypot(position.getX(index), position.getZ(index)),
    );
  }
  const angles = new Set<number>();
  for (let index = 0; index < position.count; index += 1) {
    const x = position.getX(index);
    const z = position.getZ(index);
    if (Math.hypot(x, z) >= largestRadius * 0.98) {
      angles.add(Number(Math.atan2(z, x).toFixed(5)));
    }
  }
  const ordered = [...angles].sort((a, b) => a - b);
  return ordered.reduce(
    (largest, angle, index) =>
      index === 0 ? largest : Math.max(largest, angle - ordered[index - 1]),
    0,
  );
}

describe("refineProductSurface", () => {
  it("densifies a low-segment product silhouette without mutating the source", () => {
    const source = new CylinderGeometry(1, 1, 0.4, 32);
    const sourceCount = source.getAttribute("position").count;
    const sourceGap = largestSilhouetteGap(source);

    const refined = refineProductSurface(source, 2);

    expect(source.getAttribute("position").count).toBe(sourceCount);
    expect(refined.getAttribute("position").count).toBeGreaterThan(
      sourceCount * 4,
    );
    expect(largestSilhouetteGap(refined as CylinderGeometry)).toBeLessThan(
      sourceGap * 0.4,
    );
    expect(refined.getAttribute("normal")).toBeDefined();
  });
});
