# Eureka Ring Mode Layout And Scroll Float Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved centered mode corridor, mirrored Flash/Vibe quadrants, continuous Z-shaped Ring journey, and restrained section-title Scroll Float without adding Decrypted Text.

**Architecture:** Keep `HomePage` as the scroll coordinator and `LivingRingStage` as the only WebGL stage. Add a scoped `ScrollFloatText` React component powered by the existing GSAP runtime, restructure semantic landing markup into mirrored two-by-two grids, and encode the route in `LANDING_RING_STOPS`.

**Tech Stack:** React 18, TypeScript, GSAP 3, `@gsap/react`, ScrollTrigger, Vitest, Testing Library, CSS.

## Global Constraints

- Keep one fixed `LivingRingStage`; do not add Canvas or GLB instances.
- Do not implement Decrypted Text or add `motion`.
- Hero `h1` remains static.
- Animate only transform and opacity.
- Reduced motion renders complete static text.
- Preserve all existing Flash/Vibe demo functionality outside the landing page.

---

### Task 1: Add the semantic Scroll Float heading

**Files:**
- Create: `ring-demo/src/components/landing/ScrollFloatText.tsx`
- Create: `ring-demo/src/components/landing/ScrollFloatText.test.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/pages/HomePage.tsx`

**Interfaces:**
- Consumes: `text: string`, `as?: "h2" | "h3"`, `id?: string`, `className?: string`.
- Produces: one accessible semantic heading plus `span.scroll-float-char` visual characters.

- [ ] **Step 1: Write the failing component test**

```tsx
render(<ScrollFloatText as="h2" id="title" text="录音只是开始。" />);
expect(screen.getByRole("heading", { name: "录音只是开始。" })).toBeInTheDocument();
expect(container.querySelectorAll(".scroll-float-char")).toHaveLength(7);
```

- [ ] **Step 2: Verify RED**

Run: `npm test -- --run src/components/landing/ScrollFloatText.test.tsx`

Expected: FAIL because `ScrollFloatText` does not exist.

- [ ] **Step 3: Implement the scoped GSAP component**

Use `useGSAP` with the heading ref as scope. Animate `.scroll-float-char` from `{ autoAlpha: 0, yPercent: 65, scaleY: 0.82 }` to `{ autoAlpha: 1, yPercent: 0, scaleY: 1, duration: 0.72, ease: "power3.out", stagger: 0.022 }` and a top-level ScrollTrigger configured with `start: "top 82%"`, `once: true`. Render the full text as an `sr-only` span and mark the visual character wrapper `aria-hidden="true"`.

- [ ] **Step 4: Verify GREEN**

Run: `npm test -- --run src/components/landing/ScrollFloatText.test.tsx`

Expected: PASS.

### Task 2: Build the mode corridor and mirrored quadrants

**Files:**
- Modify: `ring-demo/src/pages/HomePage.test.tsx`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: existing landing copy and scene images.
- Produces: `.mode-title-line-primary`, `.mode-title-line-secondary`, `.mode-ring-corridor`, `.landing-mode-grid`, and mirrored Flash/Vibe grid areas.

- [ ] **Step 1: Write failing layout tests**

```tsx
expect(screen.getByText("一枚戒指")).toHaveClass("mode-title-line-primary");
expect(screen.getByText("两种智能体验")).toHaveClass("mode-title-line-secondary");
expect(container.querySelector(".mode-ring-corridor")).toBeInTheDocument();
expect(container.querySelector(".landing-flash .landing-scene")).toHaveClass("landing-mode-scene");
expect(container.querySelector(".landing-vibe .landing-section-copy")).toHaveClass("landing-mode-title");
```

- [ ] **Step 2: Verify RED**

Run: `npm test -- --run src/pages/HomePage.test.tsx src/components/landing/LandingStory.test.tsx`

Expected: FAIL because the split title, corridor, and mirrored grid classes are absent.

- [ ] **Step 3: Implement semantic markup and CSS grid areas**

Render the two title lines separately and add an `aria-hidden` corridor element. Give Flash the areas `title ring / scene detail`, and Vibe `ring title / detail scene`. Reserve the center corridor on desktop, stack naturally below 760px, and add `will-change` only to animated character spans.

- [ ] **Step 4: Verify GREEN**

Run: `npm test -- --run src/pages/HomePage.test.tsx src/components/landing/LandingStory.test.tsx`

Expected: PASS.

### Task 3: Encode the approved continuous Ring route

**Files:**
- Modify: `ring-demo/src/components/living-ring/landing-journey.test.ts`
- Modify: `ring-demo/src/components/living-ring/landing-journey.ts`

**Interfaces:**
- Consumes: the existing twelve narrative stop IDs.
- Produces: desktop X route `modes=0`, `flash-intro>0`, `flash-scene<0`, `vibe-intro<0`, `vibe-scene>0`.

- [ ] **Step 1: Write the failing route test**

```ts
expect(stop("modes").position[0]).toBe(0);
expect(stop("flash-intro").position[0]).toBeGreaterThan(1);
expect(stop("flash-scene").position[0]).toBeLessThan(-0.5);
expect(stop("vibe-intro").position[0]).toBeLessThan(-1);
expect(stop("vibe-scene").position[0]).toBeGreaterThan(0.5);
```

- [ ] **Step 2: Verify RED**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts`

Expected: FAIL because the current Flash and Vibe intro positions are reversed.

- [ ] **Step 3: Update the stops without changing interpolation**

Set `flash-intro.position` to a positive X safe zone and `vibe-intro.position` to a negative X safe zone. Keep the scene stops on the matching hand side, their small scale, and zero opacity.

- [ ] **Step 4: Verify GREEN and regression**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts src/components/living-ring/LivingRingStage.test.tsx`

Expected: PASS.

### Task 4: Verify the complete landing experience

**Files:**
- Verify only; modify the smallest relevant file if verification exposes a defect.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: a buildable, responsive landing page without text obstruction.

- [ ] **Step 1: Run all automated checks**

Run: `npm test -- --run && npm run typecheck && npm run build`

Expected: all tests pass, TypeScript exits 0, and Vite build exits 0.

- [ ] **Step 2: Check the implementation diff**

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 3: Browser-check desktop and mobile**

At 1440×900 and 390×844, verify that the Ring uses the center corridor, does not cover either title line, Flash/Vibe grids mirror correctly, and reduced-motion content remains visible.

### Task 5: Apply the user-approved visual revision

**Files:**
- Modify: `ring-demo/src/components/landing/ScrollFloatText.tsx`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/CommunityCta.tsx`
- Modify: `ring-demo/src/components/living-ring/landing-journey.ts`
- Modify: matching tests and `ring-demo/src/styles.css`

- [x] Drive Scroll Float with scroll progress and cover every chapter heading.
- [x] Add a small centered `mode-bridge` ring stop before Flash expands.
- [x] Separate Flash ordered features from its outcome examples.
- [x] Replace the Vibe target rows with an accessible, reduced-motion-safe Logo Loop.
- [x] Expand the loop into a broader software ecosystem and end it with `and even more`.
- [x] Keep the Ring hidden between the Vibe scene and the system chapter so it never crosses ecosystem copy.
- [x] Remove decorative numbering and repeated uppercase metadata that do not carry meaning.
- [x] Re-run desktop/mobile browser QA and the full automated suite.
