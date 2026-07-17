import {
  Box3,
  Mesh,
  MeshPhysicalMaterial,
  MeshStandardMaterial,
  Object3D,
  Vector3,
} from "three";

import {
  resolveJourneyMaterial,
  resolveRingMaterial,
} from "./product-treatment";
import { refineProductSurface } from "./surface-refinement";
import {
  conformCircuitToInnerWall,
  isInnerWallCircuitPatch,
} from "./circuit-surface";

export interface PreparedSourceRing {
  center: Vector3;
  exteriorMaterials: MeshStandardMaterial[];
  object: Object3D;
  touchMaterials: MeshStandardMaterial[];
  uniformScale: number;
}

interface PrepareSourceRingOptions {
  conformCircuitSurface?: boolean;
  refineSurface?: boolean;
  touchSurfaceMaterial?: string;
}

function isHandNode(name: string) {
  return name.toLowerCase().includes("hand");
}

export function prepareSourceRing(
  source: Object3D,
  options: PrepareSourceRingOptions = {},
): PreparedSourceRing {
  const object = source.clone(true);
  const handNodes: Object3D[] = [];

  object.traverse((child) => {
    if (isHandNode(child.name)) handNodes.push(child);
  });
  handNodes.forEach((child) => child.parent?.remove(child));
  object.updateMatrixWorld(true);

  const exteriorMaterials: MeshStandardMaterial[] = [];
  const touchMaterials: MeshStandardMaterial[] = [];
  const exteriorTreatment = resolveJourneyMaterial(0);

  object.traverse((child) => {
    if (!(child instanceof Mesh)) return;
    if (
      options.conformCircuitSurface &&
      isInnerWallCircuitPatch(child.name)
    ) {
      child.geometry = conformCircuitToInnerWall(child);
    }
    const sourceMaterials = Array.isArray(child.material)
      ? child.material
      : [child.material];
    const materials = sourceMaterials.map((material) => {
      const next = material.clone();
      if (!(next instanceof MeshStandardMaterial)) return next;

      next.flatShading = false;
      if (next.name === "材质") {
        if (options.refineSurface) {
          child.geometry = refineProductSurface(child.geometry);
        }
        const exterior = new MeshPhysicalMaterial({
          clearcoat: 0.18,
          clearcoatRoughness: 0.16,
          color: next.color,
          depthTest: next.depthTest,
          depthWrite: next.depthWrite,
          envMapIntensity: next.envMapIntensity,
          metalness: next.metalness,
          opacity: next.opacity,
          roughness: next.roughness,
          side: next.side,
          transparent: next.transparent,
          vertexColors: next.vertexColors,
        });
        exterior.name = next.name;
        exterior.color.set(exteriorTreatment.color);
        exterior.envMapIntensity = exteriorTreatment.envMapIntensity;
        exterior.metalness = exteriorTreatment.metalness;
        exterior.roughness = exteriorTreatment.roughness;
        exterior.needsUpdate = true;
        exteriorMaterials.push(exterior);
        return exterior;
      } else {
        if (options.refineSurface && next.name === "材质.001") {
          child.geometry = refineProductSurface(child.geometry);
        }
        const treatment = resolveRingMaterial(next.name);
        if (treatment) {
          next.color.set(treatment.color);
          next.envMapIntensity = treatment.envMapIntensity;
          next.metalness = treatment.metalness;
          next.roughness = treatment.roughness;
        }
        if (next.name === options.touchSurfaceMaterial) {
          touchMaterials.push(next);
        }
      }
      next.needsUpdate = true;
      return next;
    });
    child.material = Array.isArray(child.material) ? materials : materials[0];
  });

  const bounds = new Box3().setFromObject(object);
  const size = bounds.getSize(new Vector3());
  const center = bounds.getCenter(new Vector3());
  const largest = Math.max(size.x, size.y, size.z);

  return {
    center,
    exteriorMaterials,
    object,
    touchMaterials,
    uniformScale: largest > 0 ? 2 / largest : 1,
  };
}
