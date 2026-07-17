# Ring Demo Continuous Product Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one real-time 3D Ring that moves continuously from Hero to Connect to the Flash/Vibe axis, rotates without a turn limit, transitions black-to-silver-to-black, and responds to mode hover with left/right accent lighting.

**Architecture:** `HomePage` writes scroll progress and uncapped rotation into a mutable journey ref. Pure functions resolve piecewise spatial and material phases, while `LivingRingScene` dampens toward those targets per WebGL frame. A high-segment procedural titanium band replaces the GLB's visible low-resolution shell; retained GLB detail meshes and PNG fallback remain available.

**Tech Stack:** React 18, TypeScript, GSAP ScrollTrigger, React Three Fiber, Three.js, Vitest, Testing Library.

## Global Constraints

- Home must remain scrollable; no blocking full-page pin.
- Spatial position holds at Connect while rotation and color remain scroll-responsive.
- Rotation is derived from absolute scroll distance and has no fixed turn cap.
- Product colors are graphite black and cool silver-gray titanium.
- Mode hover changes lighting only: Flash is warm gold on the left, Vibe is cool blue on the right.
- Flash/Vibe routes, Ring Desktop behavior, connection behavior, and backend flows must not change.
- Reduced motion removes continuous spin and pointer parallax.

---

### Task 1: Pure Journey Model

**Files:**
- Create: `ring-demo/src/components/living-ring/journey-state.ts`
- Create: `ring-demo/src/components/living-ring/journey-state.test.ts`
- Modify: `ring-demo/src/components/living-ring/motion-state.ts`

**Interfaces:**
- Produces: `RingJourneyFrame { progress: number; rotation: number }`
- Produces: `RingJourneyPose { position; rotation; scale; silverMix; modeMix }`
- Produces: `resolveRingJourney(progress: number): RingJourneyPose`

- [ ] **Step 1: Write failing tests for continuous anchors, Connect hold, and color phases**

```ts
expect(resolveRingJourney(0).silverMix).toBe(0);
expect(resolveRingJourney(0.5).silverMix).toBeGreaterThan(0.9);
expect(resolveRingJourney(1).silverMix).toBe(0);
expect(resolveRingJourney(0.46).position).toEqual(resolveRingJourney(0.58).position);
expect(resolveRingJourney(0.78).position[0]).toBeCloseTo(0);
```

- [ ] **Step 2: Run `npm test -- --run src/components/living-ring/journey-state.test.ts` and verify it fails because the module does not exist**

- [ ] **Step 3: Implement clamped smoothstep interpolation across Hero, Connect hold, and Mode anchors**

```ts
export function resolveRingJourney(rawProgress: number): RingJourneyPose {
  const progress = clamp01(rawProgress);
  const toConnect = smoothstep(0.12, 0.38, progress);
  const toMode = smoothstep(0.62, 0.84, progress);
  const silverMix = smoothstep(0.2, 0.42, progress) *
    (1 - smoothstep(0.58, 0.82, progress));
  return interpolateAnchors(toConnect, toMode, silverMix);
}
```

- [ ] **Step 4: Re-run the focused test and verify all journey assertions pass**

### Task 2: Procedural Titanium Product Model

**Files:**
- Create: `ring-demo/src/components/living-ring/product-band.ts`
- Create: `ring-demo/src/components/living-ring/product-band.test.ts`
- Modify: `ring-demo/src/components/living-ring/product-treatment.ts`
- Modify: `ring-demo/src/components/living-ring/product-treatment.test.ts`

**Interfaces:**
- Produces: `createBandProfile(): Vector2[]`
- Produces: `resolveJourneyMaterial(silverMix: number): RingMaterialTreatment`
- Produces: `resolveModeLights(mode: LivingRingMode): { left: number; right: number }`

- [ ] **Step 1: Write failing tests for a closed rounded band profile, black/silver endpoints, and left/right light selection**

```ts
expect(createBandProfile().length).toBeGreaterThanOrEqual(12);
expect(resolveJourneyMaterial(0).color).toBe("#090a0b");
expect(resolveJourneyMaterial(1).color).toBe("#aeb3b8");
expect(resolveModeLights("flash")).toEqual({ left: 1, right: 0 });
expect(resolveModeLights("vibe")).toEqual({ left: 0, right: 1 });
```

- [ ] **Step 2: Run both focused test files and verify they fail on missing exports**

- [ ] **Step 3: Implement the rounded radial profile and material/light resolvers**

```ts
const BLACK = new Color("#090a0b");
const SILVER = new Color("#aeb3b8");
export function resolveJourneyMaterial(mix: number) {
  return {
    color: `#${BLACK.clone().lerp(SILVER, clamp01(mix)).getHexString()}`,
    metalness: lerp(0.78, 0.9, mix),
    roughness: lerp(0.46, 0.34, mix),
    envMapIntensity: lerp(1.15, 1.65, mix),
  };
}
```

- [ ] **Step 4: Re-run the focused tests and verify they pass**

### Task 3: Continuous Scroll Controller

**Files:**
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/pages/HomePage.test.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`

**Interfaces:**
- Consumes: `RingJourneyFrame`
- Produces: a stable `MutableRefObject<RingJourneyFrame>` passed through the stage to WebGL

- [ ] **Step 1: Update tests to require a real-time 3D default and no threshold-derived `hero:launcher` state**

```ts
expect(stage).toHaveAttribute("data-product-medium", "realtime-3d");
expect(stage).not.toHaveAttribute("data-scene-state");
```

- [ ] **Step 2: Run Home and Stage tests and verify the old photograph/threshold implementation fails**

- [ ] **Step 3: Replace `travelProgress` React state with a mutable journey ref updated by one full-Home ScrollTrigger**

```ts
const journeyRef = useRef<RingJourneyFrame>({ progress: 0, rotation: 0 });
ScrollTrigger.create({
  trigger: homeRef.current,
  start: "top top",
  end: "bottom bottom",
  onUpdate: ({ progress }) => {
    journeyRef.current.progress = progress;
    journeyRef.current.rotation = window.scrollY * 0.012;
  },
});
```

- [ ] **Step 4: Make WebGL the default medium, keep the PNG visible until ready/error, and pass the stable journey ref into the lazy scene**

- [ ] **Step 5: Re-run Home and Stage tests and verify they pass**

### Task 4: Real-Time Scene, Material Journey, and Mode Lights

**Files:**
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `resolveRingJourney`, `resolveJourneyMaterial`, `resolveModeLights`, `createBandProfile`, and the journey ref
- Produces: one persistent WebGL Ring with damped position, scale, spin, material, and accent lights

- [ ] **Step 1: Build `LatheGeometry(createBandProfile(), 256)` once and add a dark inner liner plus retained non-shell GLB details**

- [ ] **Step 2: Add a deterministic repeating micro-roughness texture and mutate one `MeshPhysicalMaterial` in place from `silverMix`**

- [ ] **Step 3: In `useFrame`, damp group position/scale/tilt toward `resolveRingJourney(journeyRef.current.progress)` and damp Y spin toward `journeyRef.current.rotation`**

- [ ] **Step 4: Add left warm-gold and right cool-blue spotlights whose intensities follow `resolveModeLights(focusedMode)`**

- [ ] **Step 5: Remove photograph-specific threshold CSS while preserving the poster as load/error fallback and the external connection sweep**

- [ ] **Step 6: Run living-ring tests, typecheck, and build**

### Task 5: Browser Calibration and Regression Verification

**Files:**
- Modify only the exact journey constants or product CSS needed by visual evidence

**Interfaces:**
- Consumes: the complete Home implementation
- Produces: verified desktop and mobile product journey

- [ ] **Step 1: Start the fixed-port full Demo and inspect Hero, Connect, and Mode anchors in a headed browser**

- [ ] **Step 2: Verify continuous movement at intermediate scroll positions and that Connect holds spatially while rotation/color continue**

- [ ] **Step 3: Verify Flash/Vibe hover lights illuminate only the intended side and actionable copy remains unobstructed**

- [ ] **Step 4: Verify 390×844 has no horizontal overflow and reduced motion removes continuous spin**

- [ ] **Step 5: Run `npm test -- --run && npm run typecheck && npm run build && git diff --check` and require zero failures**
