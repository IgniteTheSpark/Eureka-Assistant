# Eureka Ring Product Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the existing Ring Demo home into an eight-chapter Chinese product landing page with one continuous, color-shifting 3D Ring journey and a replaceable beta-community QR CTA.

**Architecture:** Keep `HomePage` as the route-level composition owner, move long-form Chinese content into focused landing components, and add a pure `landing-journey` state resolver that maps normalized scroll progress to chapter anchors and material/motion parameters. The existing `LivingRingScene` and poster fallback consume that resolver so WebGL and non-WebGL presentations share the same narrative path.

**Tech Stack:** React 18, TypeScript 5.7, GSAP ScrollTrigger, React Three Fiber/Three.js, CSS, Vitest, Testing Library.

## Global Constraints

- Keep `/flash` and `/vibe` behavior unchanged.
- All visitor-facing landing copy is Chinese; `Flash Mode` and `Vibe Mode` include Chinese explanations on first appearance.
- Continue using `/ring/ring-single-hires.glb`; do not reconstruct the shell or circuit procedurally.
- Do not claim unverified hardware weight, battery, waterproofing, material, pricing, or release dates.
- Dynamic Ring colors represent intelligence states, not purchasable colorways.
- The final QR asset contract is `/community/eureka-ring-beta-qr.png`; until supplied, render an explicitly non-scannable placeholder.
- Every animation has a `prefers-reduced-motion` alternative.
- Preserve existing Ring connection, demo entry, session, and Operator Controls behavior.

---

### Task 1: Define the Chinese Landing Content Model

**Files:**
- Create: `ring-demo/src/components/landing/landing-content.ts`
- Create: `ring-demo/src/components/landing/landing-content.test.ts`

**Interfaces:**
- Produces: `LANDING_CONTENT`, `LandingFeature`, `LandingFlowStep`, `LandingHardwareDetail`.
- Consumes: no runtime dependencies.

- [ ] **Step 1: Write the failing content contract test**

```ts
import { describe, expect, it } from "vitest";
import { LANDING_CONTENT } from "./landing-content";

describe("LANDING_CONTENT", () => {
  it("defines every Chinese product chapter without unverified specs", () => {
    expect(LANDING_CONTENT.flash.examples).toHaveLength(4);
    expect(LANDING_CONTENT.features).toHaveLength(5);
    expect(LANDING_CONTENT.system.steps.map((step) => step.title)).toEqual([
      "Eureka Ring",
      "本地桌面连接",
      "个人智能层",
      "工具与资产",
    ]);
    expect(JSON.stringify(LANDING_CONTENT)).not.toMatch(/续航|防水|克重|价格/);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm test -- --run src/components/landing/landing-content.test.ts`  
Expected: FAIL because `landing-content.ts` does not exist.

- [ ] **Step 3: Implement the typed Chinese content object**

Create interfaces for the five features, four system steps, Flash examples, Vibe targets, hardware details, and CTA copy. Export one immutable `LANDING_CONTENT` object containing the exact approved Chinese copy from the design spec.

- [ ] **Step 4: Run the test to verify it passes**

Run: `npm test -- --run src/components/landing/landing-content.test.ts`  
Expected: PASS.

### Task 2: Define the Eight-Chapter Ring Journey

**Files:**
- Create: `ring-demo/src/components/living-ring/landing-journey.ts`
- Create: `ring-demo/src/components/living-ring/landing-journey.test.ts`
- Modify: `ring-demo/src/components/living-ring/journey-state.ts`

**Interfaces:**
- Produces: `LandingChapterId`, `LandingRingFrame`, `LANDING_RING_STOPS`, `resolveLandingRingFrame(progress, compact, reducedMotion)`.
- Consumes: `clamp01` and the existing Ring pose tuple conventions.

- [ ] **Step 1: Write failing journey tests**

Test that progress `0` resolves to `hero`, each exact stop resolves to its chapter, colors interpolate between `#202327` (hero), `#ef6a45` (Flash), `#5367ff` (Vibe), `#39d7c1` (system), and a neutral hardware material, and reduced motion returns `hop = 0`, `spin = 0`, `pulse = 0`.

- [ ] **Step 2: Run the journey test to verify failure**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts`  
Expected: FAIL because the resolver is missing.

- [ ] **Step 3: Implement stop interpolation**

Define eight ordered stops (`hero`, `modes`, `flash`, `vibe`, `system`, `features`, `hardware`, `community`). Each stop includes normalized page progress, `position`, `rotation`, `scale`, `color`, `roughness`, `metalness`, `envMapIntensity`, `pulse`, `spin`, and `hop`. Resolve the surrounding stops and interpolate numeric/tuple/color values with smoothstep easing.

- [ ] **Step 4: Preserve focused-mode handoff**

When the active chapter is `modes`, continue applying the existing Flash/Vibe photographed-hand targets and opacity merge. Outside `modes`, ignore `focusedMode` so hover state cannot leak into later chapters.

- [ ] **Step 5: Run journey tests**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts src/components/living-ring/journey-state.test.ts`  
Expected: PASS.

### Task 3: Build the Semantic Landing Sections

**Files:**
- Create: `ring-demo/src/components/landing/LandingStory.tsx`
- Create: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Create: `ring-demo/src/components/landing/CommunityCta.tsx`
- Create: `ring-demo/public/community/eureka-ring-beta-qr-placeholder.svg`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/pages/HomePage.test.tsx`

**Interfaces:**
- Consumes: `LANDING_CONTENT`.
- Produces: semantic Sections with `data-ring-chapter` values matching `LandingChapterId` and a CTA that references `/community/eureka-ring-beta-qr.png` only when the real file is present.

- [ ] **Step 1: Write failing semantic rendering tests**

Render `LandingStory` and assert the headings `录音只是开始。`, `不需要切换到另一块屏幕。`, `它不是一个缩小的语音助手。`, `一枚戒指背后的五件事`, and `一个安静的入口，始终戴在手上。`. Assert every Section exposes the correct `data-ring-chapter`. Assert the CTA contains `扫码加入内测群` and the placeholder alt text.

- [ ] **Step 2: Run the tests to verify failure**

Run: `npm test -- --run src/components/landing/LandingStory.test.tsx src/pages/HomePage.test.tsx`  
Expected: FAIL because the components are missing and Home is not fully Chinese.

- [ ] **Step 3: Implement `LandingStory`**

Build five semantic sections with distinct structures: Flash semantic pipeline, Vibe application rails, system connection chain, alternating feature bands, and hardware gallery using existing `/ring/` assets. Avoid a repeated identical-card grid.

- [ ] **Step 4: Implement `CommunityCta`**

Render the approved CTA, a deliberately non-scannable placeholder SVG, the fixed final asset contract in a `data-qr-target` attribute, the qualification note, and a native anchor back to `#top`.

- [ ] **Step 5: Compose sections in `HomePage` and translate existing copy**

Add `id="top"`, translate Hero, connection and Mode Scene copy, preserve links and controls, then render `LandingStory` and `CommunityCta` after the existing mode selector.

- [ ] **Step 6: Run semantic tests**

Run: `npm test -- --run src/components/landing/LandingStory.test.tsx src/pages/HomePage.test.tsx src/components/mode-scenes/ModeSceneStage.test.tsx`  
Expected: PASS.

### Task 4: Connect Scroll Progress to the New Journey

**Files:**
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/product-treatment.ts`
- Modify: `ring-demo/src/components/living-ring/product-treatment.test.ts`

**Interfaces:**
- Consumes: `resolveLandingRingFrame`.
- Produces: one continuous 3D/fallback journey with chapter color, spin, pulse and hop.

- [ ] **Step 1: Write failing material tests**

Add tests for `resolveJourneyMaterial(color, roughness, metalness, envMapIntensity)` using direct Landing Journey material values, while keeping `resolveRingMaterial` source-model behavior unchanged.

- [ ] **Step 2: Run material tests to verify failure**

Run: `npm test -- --run src/components/living-ring/product-treatment.test.ts`  
Expected: FAIL on the new material signature.

- [ ] **Step 3: Update ScrollTrigger progress**

Keep the whole-page ScrollTrigger but recalculate end progress after images/fonts settle by calling `ScrollTrigger.refresh()`. Store normalized progress and scroll-driven rotation in the shared `journeyRef`.

- [ ] **Step 4: Apply the Landing Journey to WebGL**

In `useFrame`, resolve the current Landing frame. Apply its position/rotation/scale, add one-shot hop as a damped sine envelope around chapter boundaries, add spin to the Y rotation, interpolate exterior material treatment, and drive internal/mode lights from `pulse` and chapter accent color.

- [ ] **Step 5: Apply the same journey to the poster fallback**

Resolve identical position/rotation/scale/opacity values in `LivingRingStage`; set CSS custom properties for chapter color approximation, pulse shadow and fallback opacity. Keep focused-mode handoff behavior on the mode chapter.

- [ ] **Step 6: Run living-ring tests**

Run: `npm test -- --run src/components/living-ring`  
Expected: PASS.

### Task 5: Art-Direct the Eight Chapters

**Files:**
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: landing component class names and Ring CSS variables.
- Produces: desktop, tablet, mobile and reduced-motion layouts.

- [ ] **Step 1: Add the shared landing layout system**

Create section spacing tokens, a maximum content width, light/dark chapter surfaces, Chinese type sizing, balanced headings, 70ch prose caps and a semantic z-index stack.

- [ ] **Step 2: Add distinct section compositions**

Implement the Flash pipeline as expanding text/asset rails, Vibe as two application lanes, system as a vertical connection path, features as alternating full-width bands, hardware as an image-led product gallery, and community as a dark full-viewport CTA.

- [ ] **Step 3: Add Ring-safe content zones**

Reserve chapter-specific negative space so the fixed Ring never obscures headings, prose, controls or QR content at 1440×900 and 1920×1080.

- [ ] **Step 4: Add responsive and reduced-motion rules**

At `<=1040px`, reduce horizontal displacement and simplify two-column sections. At `<=760px`, stack content, keep the Ring in a top safe zone, hide complex runway markers and preserve a QR size of at least 220px. Under reduced motion, disable hop/spin/continuous transitions without hiding content.

- [ ] **Step 5: Run targeted UI tests and typecheck**

Run: `npm test -- --run src/components/landing src/pages/HomePage.test.tsx && npm run typecheck`  
Expected: PASS.

### Task 6: Verify Product and Demo Integrity

**Files:**
- Modify only if verification exposes a defect.

**Interfaces:**
- Consumes: completed Landing Page.
- Produces: evidence that the product page and existing Demo routes remain usable.

- [ ] **Step 1: Run the complete automated suite**

Run: `npm test -- --run`  
Expected: all test files and tests pass.

- [ ] **Step 2: Run type and production checks**

Run: `npm run typecheck && npm run build && git diff --check`  
Expected: exit 0; the existing Vite large-chunk warning is acceptable.

- [ ] **Step 3: Run browser QA at four sizes**

Use `/browse` at 1920×1080, 1440×900, 1024×768 and 390×844. Verify Chinese copy, Ring safe zones, Flash/Vibe links, connection controls, CTA placeholder, back-to-top, and no layout overflow.

- [ ] **Step 4: Verify reduced motion**

Emulate `prefers-reduced-motion: reduce`; verify content remains visible and Ring hop/spin/pulse stop.

- [ ] **Step 5: Preserve the branch**

Keep `codex/ring-demo` and the current worktree intact unless the user explicitly requests staging, committing implementation, pushing or merging.

