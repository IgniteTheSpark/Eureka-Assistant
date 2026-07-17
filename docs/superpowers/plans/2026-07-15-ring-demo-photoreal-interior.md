# Ring Demo Photoreal Interior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Home 3D Ring read like premium product photography by prioritizing the exterior shell, removing the artificial inner torus, and moving connection effects outside the interior.

**Architecture:** Extend the pure pose mapper with stable three-quarter base angles and add a pure presentation mapper for material and connection-effect decisions. `LivingRingScene` consumes those contracts for the GLB, while `LivingRingStage` and CSS render the exterior/background scan treatment without changing semantic Home controls.

**Tech Stack:** React 18, TypeScript, React Three Fiber, Three.js, GSAP, Vitest, Testing Library

## Global Constraints

- The camera must not look straight through the center of the Ring.
- No full gray or emissive torus may be visible inside the Ring.
- The inner liner remains one to two stops darker than the exterior edge highlight.
- Scanning appears on the background orbit or exterior edge, never as a complete inner ring.
- Flash, Vibe, Ring Desktop protocols, and physical gesture mappings remain unchanged.
- Reduced motion and PNG fallback remain usable.

---

### Task 1: Product photography contracts

**Files:**
- Modify: `ring-demo/src/components/living-ring/motion-state.ts`
- Modify: `ring-demo/src/components/living-ring/motion-state.test.ts`
- Create: `ring-demo/src/components/living-ring/product-treatment.ts`
- Create: `ring-demo/src/components/living-ring/product-treatment.test.ts`

**Interfaces:**
- Produces: `resolveLivingRingPose(input): LivingRingPose`
- Produces: `resolveRingMaterial(name): RingMaterialTreatment`
- Produces: `resolveConnectionTreatment(status, reducedMotion): ConnectionTreatment`

- [ ] **Step 1: Write failing pose and treatment tests**

```ts
expect(hero.rotation[1]).toBeLessThanOrEqual(-0.5);
expect(Math.abs(launcher.rotation[1])).toBeGreaterThanOrEqual(0.2);
expect(Math.abs(flash.rotation[1])).toBeGreaterThanOrEqual(0.2);
expect(Math.abs(vibe.rotation[1])).toBeGreaterThanOrEqual(0.2);
expect(resolveConnectionTreatment("scanning", false)).toEqual({ exteriorSweep: 1, contactReflection: 0 });
expect(resolveConnectionTreatment("connected", false)).toEqual({ exteriorSweep: 0, contactReflection: 0.16 });
expect(resolveRingMaterial("材质.001").color).toBe("#08090a");
```

- [ ] **Step 2: Run focused tests to verify failure**

Run: `npm test -- --run src/components/living-ring/motion-state.test.ts src/components/living-ring/product-treatment.test.ts`
Expected: FAIL because launcher base yaw and `product-treatment` do not exist.

- [ ] **Step 3: Implement deterministic pose, material, and connection mappings**

```ts
export function resolveConnectionTreatment(status: string, reducedMotion: boolean) {
  return {
    exteriorSweep: !reducedMotion && status === "scanning" ? 1 : 0,
    contactReflection: status === "connected" ? 0.16 : status === "connecting" ? 0.08 : 0,
  };
}

export function resolveRingMaterial(name: string): RingMaterialTreatment | null {
  if (name === "材质.001") {
    return { color: "#08090a", metalness: 0.18, roughness: 0.48 };
  }
  if (name === "材质.002" || name === "材质.004") {
    return { color: "#0b0d0f", metalness: 0.78, roughness: 0.32 };
  }
  return null;
}
```

- [ ] **Step 4: Run focused tests to verify pass**

Run: `npm test -- --run src/components/living-ring/motion-state.test.ts src/components/living-ring/product-treatment.test.ts`
Expected: PASS.

### Task 2: Scene and scan treatment

**Files:**
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `resolveRingMaterial` and `resolveConnectionTreatment`.
- Produces: a soft three-light product rig, no inner torus mesh, and a CSS background scan orbit keyed by `data-scene-state`.

- [ ] **Step 1: Add a failing stage test for exterior scan state**

```tsx
render(<LivingRingStage connectionStatus="scanning" focusedMode={null} reducedMotion={false} travelProgress={1} />);
expect(screen.getByTestId("living-ring-stage")).toHaveAttribute("data-exterior-sweep", "true");
```

- [ ] **Step 2: Run the stage test to verify failure**

Run: `npm test -- --run src/components/living-ring/LivingRingStage.test.tsx`
Expected: FAIL because `data-exterior-sweep` is absent.

- [ ] **Step 3: Implement scene and CSS treatment**

Remove the `glow` and `scan` torus meshes. Apply material treatment through `resolveRingMaterial`. Drive a restrained warm point light from `contactReflection`:

```tsx
const treatment = resolveConnectionTreatment(input.connectionStatus, input.reducedMotion);
if (contactLight.current) {
  contactLight.current.intensity = MathUtils.lerp(
    contactLight.current.intensity,
    treatment.contactReflection,
    ease,
  );
}

<ambientLight intensity={0.32} />
<directionalLight color="#f2eee6" intensity={1.45} position={[3.8, 4.8, 5]} />
<directionalLight color="#71829a" intensity={0.38} position={[-4, -2, 1.5]} />
<spotLight angle={0.32} color="#ffffff" intensity={1.05} penumbra={0.9} position={[-2.5, 3.5, 4]} />
<pointLight color="#c9a96e" intensity={0} position={[0, 0.7, 1.5]} ref={contactLight} />
```

Add `data-exterior-sweep={treatment.exteriorSweep > 0}` to `LivingRingStage`. Render the sweep behind the product:

```css
.living-ring-halo::after {
  content: "";
  position: absolute;
  inset: -1px;
  border-radius: inherit;
  border: 1px solid transparent;
  opacity: 0;
}

.living-ring-stage[data-exterior-sweep="true"] .living-ring-halo::after {
  border-top-color: rgb(220 214 201 / 65%);
  opacity: 1;
  animation: living-ring-exterior-sweep 1.4s linear infinite;
}
```

- [ ] **Step 4: Run focused tests and typecheck**

Run: `npm test -- --run src/components/living-ring src/pages/HomePage.test.tsx && npm run typecheck`
Expected: PASS with no TypeScript errors.

### Task 3: Verification

**Files:**
- Modify only if verification reveals a scoped defect.

- [ ] **Step 1: Run the complete automated gate**

Run: `npm test -- --run && npm run typecheck && npm run build && git diff --check`
Expected: 89 or more tests pass, typecheck exits 0, production build exits 0, and diff check is clean.

- [ ] **Step 2: Verify real WebGL at 1440×900**

Confirm: three-quarter Hero pose, no gray inner torus, no broad white inner patch, neutral launcher does not cover mode titles, and Flash/Vibe focus remain distinct.

- [ ] **Step 3: Verify 390×844 fallback/responsive layout**

Confirm: no horizontal overflow, semantic links remain enabled while disconnected, and reduced-motion/fallback content stays usable.
