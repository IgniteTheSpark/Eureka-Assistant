# Ring Demo Living Object Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent 3D Living Object Ring across the Home Hero and launcher without mapping physical Ring gestures to the webpage.

**Architecture:** A pure scene-state mapper translates scroll, connection, and mode focus into targets. A lazy-loaded React Three Fiber stage consumes those targets, while GSAP ScrollTrigger updates normalized travel progress and the existing DOM keeps all controls semantic.

**Tech Stack:** React 18, TypeScript, React Three Fiber, Drei, Three.js, GSAP, ScrollTrigger, Vitest, Testing Library

## Global Constraints

- Physical Ring gestures never control the Home page.
- Flash and Vibe remain clickable while disconnected.
- Existing Flash/Vibe routes and workflows remain unchanged.
- Native scrolling is never pinned or hijacked.
- WebGL failure and reduced-motion preferences preserve a usable experience.

---

### Task 1: Scene state contract

**Files:**
- Create: `ring-demo/src/components/living-ring/motion-state.ts`
- Test: `ring-demo/src/components/living-ring/motion-state.test.ts`

**Interfaces:**
- Produces: `resolveLivingRingPose(input: LivingRingInput): LivingRingPose`

- [ ] Write tests for hero, travel, connection, Flash, Vibe, and reduced-motion poses.
- [ ] Run the focused test and confirm the module is missing.
- [ ] Implement clamped deterministic pose mapping.
- [ ] Run the focused test and confirm it passes.

### Task 2: Persistent lazy 3D stage

**Files:**
- Create: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Create: `ring-demo/src/components/living-ring/LivingRingScene.tsx`
- Create: `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`
- Copy: `ring-demo/public/ring/ring.glb`
- Modify: `ring-demo/package.json`
- Modify: `ring-demo/package-lock.json`

**Interfaces:**
- Consumes: `LivingRingInput`
- Produces: a decorative, pointer-transparent canvas with poster fallback and `data-scene-state` observability.

- [ ] Write a failing test for fallback, state attributes, and the absence of gesture listeners.
- [ ] Install `three`, `@react-three/fiber`, `@react-three/drei`, `gsap`, and `@gsap/react`.
- [ ] Implement lazy scene loading, GLB node filtering, interpolation, and WebGL fallback.
- [ ] Run the focused test and confirm it passes.

### Task 3: Home travel and mode fields

**Files:**
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/pages/HomePage.test.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Supplies stage progress, shared connection state, and focused mode.

- [ ] Extend Home tests for focus-driven mode state and disconnected route availability.
- [ ] Run the focused test and confirm failure.
- [ ] Add one stage, ScrollTrigger progress, connection-state plumbing, and environmental mode fields.
- [ ] Add responsive and reduced-motion CSS using transforms/opacity only.
- [ ] Run the focused tests and confirm they pass.

### Task 4: Verification

**Files:**
- Modify only if verification reveals a scoped defect.

- [ ] Run `npm test -- --run` from `ring-demo` and require all tests to pass.
- [ ] Run `npm run typecheck` and require exit code 0.
- [ ] Run `npm run build` and require exit code 0.
- [ ] Browser-check desktop and mobile Home states, standard scrolling, keyboard focus, and no horizontal overflow.
