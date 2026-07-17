import { Suspense, useEffect, useMemo, useRef } from "react";
import type { MutableRefObject } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { Environment, Lightformer, useGLTF } from "@react-three/drei";
import {
  Color,
  Group,
  Material,
  MathUtils,
  Mesh,
  MeshBasicMaterial,
  PointLight,
  Vector2,
} from "three";

import { resolveLandingRingFrame } from "./landing-journey";
import { resolveRingJourney, type RingJourneyFrame } from "./journey-state";
import type { LivingRingMode } from "./motion-state";
import {
  resolveConnectionTreatment,
  resolveJourneyMaterial,
  resolveModeLights,
} from "./product-treatment";
import {
  PRODUCT_CAMERA,
  PRODUCT_GEOMETRY,
  PRODUCT_LIGHTING,
  PRODUCT_RENDERING,
} from "./scene-config";
import { prepareSourceRing } from "./source-model";

interface SceneProps {
  connectionStatus: string;
  focusedMode: LivingRingMode;
  journeyRef: MutableRefObject<RingJourneyFrame>;
  onReady: () => void;
  reducedMotion: boolean;
}

function ProductRing({ onReady, ...input }: SceneProps) {
  const source = useGLTF(PRODUCT_GEOMETRY.source).scene;
  const prepared = useMemo(
    () =>
      prepareSourceRing(source, {
        conformCircuitSurface: PRODUCT_GEOMETRY.conformCircuitSurface,
        refineSurface: PRODUCT_GEOMETRY.refineSourceSurface,
        touchSurfaceMaterial: PRODUCT_GEOMETRY.touchSurfaceMaterial,
      }),
    [source],
  );
  const centeredPosition = useMemo(
    () => prepared.center.clone().multiplyScalar(-1),
    [prepared],
  );
  const fadeMaterials = useMemo(() => {
    const materials = new Map<Material, number>();
    prepared.object.traverse((child) => {
      if (!(child instanceof Mesh)) return;
      const childMaterials = Array.isArray(child.material)
        ? child.material
        : [child.material];
      childMaterials.forEach((material) => {
        if (materials.has(material)) return;
        materials.set(material, material.opacity);
        material.transparent = true;
        material.needsUpdate = true;
      });
    });
    return [...materials.entries()];
  }, [prepared]);
  const touchMaterialStates = useMemo(
    () =>
      prepared.touchMaterials.map((material) => ({
        baseColor: material.color.clone(),
        baseEmissive: material.emissive.clone(),
        baseEmissiveIntensity: material.emissiveIntensity,
        baseEnvMapIntensity: material.envMapIntensity,
        baseRoughness: material.roughness,
        highlightColor: material.color.clone().lerp(new Color("#6847b8"), 0.2),
        highlightEmissive: new Color("#6c42d8"),
        material,
      })),
    [prepared],
  );
  const group = useRef<Group>(null);
  const scanMaterial = useRef<MeshBasicMaterial>(null);
  const leftLight = useRef<PointLight>(null);
  const rightLight = useRef<PointLight>(null);
  const contactLight = useRef<PointLight>(null);
  const pointer = useRef(new Vector2());
  const targetColor = useRef(new Color("#252a2e"));
  const handoffProgress = useRef(0);

  useEffect(() => onReady(), [onReady, prepared]);

  useEffect(() => {
    if (input.reducedMotion) return;
    const handlePointer = (event: PointerEvent) => {
      pointer.current.set(
        (event.clientX / window.innerWidth) * 2 - 1,
        -(event.clientY / window.innerHeight) * 2 + 1,
      );
    };
    window.addEventListener("pointermove", handlePointer, { passive: true });
    return () => window.removeEventListener("pointermove", handlePointer);
  }, [input.reducedMotion]);

  useFrame(({ size }, delta) => {
    if (!group.current) return;
    const journey = input.journeyRef.current;
    const landingFrame = resolveLandingRingFrame(
      journey.progress,
      size.width <= 760,
      input.reducedMotion,
    );
    const handoffTarget =
      landingFrame.chapter === "modes" &&
      input.focusedMode &&
      !input.reducedMotion
        ? 1
        : 0;
    handoffProgress.current = MathUtils.damp(
      handoffProgress.current,
      handoffTarget,
      handoffTarget ? 3.4 : 5.8,
      delta,
    );
    const modeHandoff = resolveRingJourney(
      1,
      size.width <= 760,
      input.focusedMode,
      input.reducedMotion,
      handoffProgress.current,
    );
    const pose =
      landingFrame.chapter === "modes" && input.focusedMode
        ? {
            ...landingFrame,
            position: modeHandoff.position,
            rotation: modeHandoff.rotation,
            scale: modeHandoff.scale,
            opacity: modeHandoff.opacity,
          }
        : landingFrame;
    const material = resolveJourneyMaterial(
      landingFrame.color,
      landingFrame.roughness,
      landingFrame.metalness,
      landingFrame.envMapIntensity,
    );
    const modeLights = resolveModeLights(input.focusedMode);
    const connection = resolveConnectionTreatment(
      input.connectionStatus,
      input.reducedMotion,
    );
    const motionEase = 1 - Math.exp(-delta * 5.6);
    const materialEase = 1 - Math.exp(-delta * 4.2);
    const pointerX = input.reducedMotion ? 0 : pointer.current.x * 0.045;
    const pointerY = input.reducedMotion ? 0 : pointer.current.y * 0.03;
    const connectionLean =
      input.connectionStatus === "connecting" ||
      input.connectionStatus === "connected"
        ? -0.06
        : 0;
    const hopOffset =
      input.reducedMotion || landingFrame.chapter === "modes"
        ? 0
        : Math.sin(landingFrame.segmentProgress * Math.PI) *
          landingFrame.hop *
          0.075;

    group.current.position.x = MathUtils.lerp(
      group.current.position.x,
      pose.position[0],
      motionEase,
    );
    group.current.position.y = MathUtils.lerp(
      group.current.position.y,
      pose.position[1] + hopOffset,
      motionEase,
    );
    group.current.position.z = MathUtils.lerp(
      group.current.position.z,
      pose.position[2],
      motionEase,
    );
    group.current.rotation.x = MathUtils.lerp(
      group.current.rotation.x,
      Math.PI / 2 + pose.rotation[0] + pointerY,
      motionEase,
    );
    group.current.rotation.y = MathUtils.lerp(
      group.current.rotation.y,
      pose.rotation[1] + journey.rotation * landingFrame.spin + pointerX,
      motionEase,
    );
    group.current.rotation.z = MathUtils.lerp(
      group.current.rotation.z,
      pose.rotation[2] + connectionLean,
      motionEase,
    );
    group.current.scale.setScalar(
      MathUtils.lerp(group.current.scale.x, pose.scale, motionEase),
    );

    fadeMaterials.forEach(([material, baseOpacity]) => {
      material.opacity = MathUtils.lerp(
        material.opacity,
        baseOpacity * pose.opacity,
        materialEase,
      );
      material.depthWrite = material.opacity > 0.92;
    });

    targetColor.current.set(material.color);
    prepared.exteriorMaterials.forEach((exterior) => {
      exterior.color.lerp(targetColor.current, materialEase);
      exterior.roughness = MathUtils.lerp(
        exterior.roughness,
        material.roughness,
        materialEase,
      );
      exterior.metalness = MathUtils.lerp(
        exterior.metalness,
        material.metalness,
        materialEase,
      );
      exterior.envMapIntensity = MathUtils.lerp(
        exterior.envMapIntensity,
        material.envMapIntensity,
        materialEase,
      );
    });

    const touchActive = journey.effectChapter === "touch";
    touchMaterialStates.forEach((state) => {
      state.material.color.lerp(
        touchActive ? state.highlightColor : state.baseColor,
        materialEase,
      );
      state.material.emissive.lerp(
        touchActive ? state.highlightEmissive : state.baseEmissive,
        materialEase,
      );
      state.material.emissiveIntensity = MathUtils.lerp(
        state.material.emissiveIntensity,
        touchActive ? 0.34 : state.baseEmissiveIntensity,
        materialEase,
      );
      state.material.envMapIntensity = MathUtils.lerp(
        state.material.envMapIntensity,
        touchActive
          ? state.baseEnvMapIntensity + 0.28
          : state.baseEnvMapIntensity,
        materialEase,
      );
      state.material.roughness = MathUtils.lerp(
        state.material.roughness,
        touchActive
          ? Math.max(0.58, state.baseRoughness * 0.72)
          : state.baseRoughness,
        materialEase,
      );
    });

    if (leftLight.current) {
      leftLight.current.color.lerp(targetColor.current, materialEase);
      leftLight.current.intensity = MathUtils.lerp(
        leftLight.current.intensity,
        (modeLights.left * 44 + landingFrame.pulse * 12) *
          (1 + Math.sin(journey.rotation * 0.45) * 0.08),
        materialEase,
      );
    }
    if (rightLight.current) {
      rightLight.current.color.lerp(targetColor.current, materialEase);
      rightLight.current.intensity = MathUtils.lerp(
        rightLight.current.intensity,
        (modeLights.right * 44 + landingFrame.pulse * 12) *
          (1 - Math.sin(journey.rotation * 0.45) * 0.08),
        materialEase,
      );
    }
    if (contactLight.current) {
      contactLight.current.intensity = MathUtils.lerp(
        contactLight.current.intensity,
        connection.contactReflection,
        materialEase,
      );
    }
    if (scanMaterial.current) {
      scanMaterial.current.opacity = MathUtils.lerp(
        scanMaterial.current.opacity,
        connection.exteriorSweep * 0.5,
        materialEase,
      );
    }
  });

  return (
    <>
      <group ref={group}>
        <group scale={prepared.uniformScale}>
          <primitive object={prepared.object} position={centeredPosition} />
        </group>
        <mesh rotation={[Math.PI / 2, 0, 0]}>
          <torusGeometry args={[1.045, 0.006, 12, 256]} />
          <meshBasicMaterial
            color="#d2aa65"
            opacity={0}
            ref={scanMaterial}
            toneMapped={false}
            transparent
          />
        </mesh>
      </group>
      <pointLight
        color="#d2aa65"
        decay={2}
        distance={7}
        intensity={0}
        position={[-1.25, -0.42, 2]}
        ref={leftLight}
      />
      <pointLight
        color="#84aee2"
        decay={2}
        distance={7}
        intensity={0}
        position={[1.25, -0.42, 2]}
        ref={rightLight}
      />
      <pointLight
        color="#c9a96e"
        intensity={0}
        position={[0, 0.8, 1.6]}
        ref={contactLight}
      />
    </>
  );
}

function ProductEnvironment() {
  return (
    <>
      <Environment resolution={128}>
        <Lightformer
          color="#f4f0e8"
          intensity={2.8}
          position={[0, 4, 2]}
          rotation={[Math.PI / 2, 0, 0]}
          scale={[7, 2.4, 1]}
        />
        <Lightformer
          color="#dce4ec"
          intensity={2.1}
          position={[-4, 0.5, 1]}
          rotation={[0, Math.PI / 2, 0]}
          scale={[4.5, 1.4, 1]}
        />
        <Lightformer
          color="#f2e5cb"
          intensity={1.2}
          position={[4, -1, 2]}
          rotation={[0, -Math.PI / 2, 0]}
          scale={[3, 1, 1]}
        />
      </Environment>
      <ambientLight intensity={PRODUCT_LIGHTING.ambient} />
      <hemisphereLight
        args={["#ffffff", "#8d969f", PRODUCT_LIGHTING.hemisphere]}
      />
      <directionalLight
        color="#ffffff"
        intensity={PRODUCT_LIGHTING.key}
        position={[3.8, 4.8, 5]}
      />
      <directionalLight
        color="#e9eef2"
        intensity={PRODUCT_LIGHTING.frontFill}
        position={[-2.6, 0.6, 5.4]}
      />
      <directionalLight
        color="#9daab8"
        intensity={PRODUCT_LIGHTING.rim}
        position={[-4, -2, 1.5]}
      />
    </>
  );
}

export default function LivingRingScene(props: SceneProps) {
  return (
    <Canvas
      camera={{ position: PRODUCT_CAMERA.position, zoom: PRODUCT_CAMERA.zoom }}
      className="living-ring-canvas"
      dpr={PRODUCT_RENDERING.dpr}
      gl={{ alpha: true, antialias: true, powerPreference: "high-performance" }}
      orthographic
    >
      <ProductEnvironment />
      <Suspense fallback={null}>
        <ProductRing {...props} />
      </Suspense>
    </Canvas>
  );
}

useGLTF.preload(PRODUCT_GEOMETRY.source);
